extends SceneTree
const Terrain=preload('res://arena/terrain.gd')
const Vehicle=preload('res://arena/vehicle.gd')
const FlatTerrain=preload('res://scripts/practice_terrain.gd')
var checks: Dictionary={}
var runs: Array=[]
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var terrain:=Terrain.new()
 var maximum_mesh_error:=0.0;var normal_error:=0.0
 for f in terrain.features:
  var mesh: ArrayMesh=terrain.feature_mesh(f)
  var arrays: Array=mesh.surface_get_arrays(0)
  for i in arrays[Mesh.ARRAY_VERTEX].size():
   var p: Vector3=arrays[Mesh.ARRAY_VERTEX][i];var surface:=terrain.sample(p)
   maximum_mesh_error=maxf(maximum_mesh_error,absf(p.y-.004-surface.w))
   normal_error=maxf(normal_error,arrays[Mesh.ARRAY_NORMAL][i].distance_to(Vector3(surface.x,surface.y,surface.z)))
 checks['render_vertices_match_collision_surface']=maximum_mesh_error<.00001
 checks['render_normals_match_collision_surface']=normal_error<.0015
 checks['arena_floor_flat_at_spawn']=terrain.sample(Vector3(-12,0,0)).w==0
 var normal_finite:=true
 for i in 1000:
  var p:=Vector3(-70+i*.14,0,sin(i*.13)*65)
  var surface:=terrain.sample(p)
  normal_finite=normal_finite and surface.is_finite() and absf(Vector3(surface.x,surface.y,surface.z).length()-1)<.00001
 checks['all_floor_samples_finite_unit_normals']=normal_finite
 for index in 4:
  var f: Dictionary=terrain.features[index]
  var car:=Vehicle.new();car.setup();car.solver.terrain=terrain;car.solver.barrier_enabled=false
  var speed: float=40 if f.get('pipe',false) else 58
  car.reset(speed,Vector3(f.start-17,0,f.z));car.solver.barrier_enabled=false;car.set_controls(.1,0,0)
  var finite:=true;var airborne:=false;var landed:=false;var max_gap:=0.0;var min_gap:=INF
  var began:=Time.get_ticks_usec()
  for tick in 720:
   car.advance(1.0/120)
   var gap:=INF
   for w in car.solver.wheels.wheels:
    var p: Vector3=car.solver.points[w.node]
    gap=minf(gap,p.y+car.solver.wheels.support(w,Vector3.DOWN).y-terrain.sample(p).w)
   max_gap=maxf(max_gap,gap);min_gap=minf(min_gap,gap)
   if gap>.10:airborne=true
   if airborne and gap<.03:landed=true
   for p in car.solver.points:finite=finite and p.is_finite()
  checks[f.id+'_finite_actual_driving']=finite
  checks[f.id+'_airborne_and_landed']=airborne and landed
  checks[f.id+'_no_heavy_solver_or_forecast']=car.full_steps==0 and car.forecast.checks==0
  checks[f.id+'_wheel_retention']=car.solver.wheels.wheels.all(func(w):return not w.detached)
  runs.append({'case':f.id,'speed_kmh':speed,'airborne':airborne,'landed':landed,'minimum_wheel_gap_m':min_gap,'maximum_air_gap_m':max_gap,'simulation_cpu_ms':(Time.get_ticks_usec()-began)/1000.,'stats':car.statistics()})
 var pair: Dictionary=terrain.features[4]
 for entry in [['steep',-2.3,42.0],['medium',2.3,24.0]]:
  var x: float=pair.start+3;var z: float=pair.z+entry[1]
  var slope: float=(terrain.height(x+.02,z)-terrain.height(x-.02,z))/.04
  checks['paired_'+entry[0]+'_actual_grade']=absf(rad_to_deg(atan(slope))-float(entry[2]))<.05
 checks['paired_common_zero_toe']=terrain.height(pair.start,pair.z-2.3)==0 and terrain.height(pair.start,pair.z+2.3)==0
 checks['paired_seam_continuous']=absf(terrain.height(pair.start+6,pair.z-.000001)-terrain.height(pair.start+6,pair.z+.000001))<.0001
 for entry in [['steep',-2.3],['medium',2.3],['straddle',0.0]]:
  var runtime:=Vehicle.new();runtime.setup();runtime.solver.terrain=terrain;runtime.reset(28,Vector3(pair.start-8,0,pair.z+entry[1]));runtime.solver.barrier_enabled=false;runtime.set_controls(.35,0,0)
  var finite:=true;var maximum_height:=0.0;var maximum_roll:=0.0
  for tick in 1440:
   runtime.advance(1.0/120)
   maximum_height=maxf(maximum_height,runtime.compact.center.y)
   var body_basis:=Basis(runtime.compact.rotation)
   maximum_roll=maxf(maximum_roll,absf(rad_to_deg(atan2(-body_basis.z.y,body_basis.y.y))))
   for p in runtime.solver.points:finite=finite and p.is_finite()
  checks['paired_'+entry[0]+'_finite_actual_drive']=finite and runtime.full_steps==0
  checks['paired_'+entry[0]+'_climbs']=maximum_height>1.5
  runs.append({'case':'pair_'+entry[0],'initial_speed_kmh':28,'maximum_center_height_m':maximum_height,'maximum_roll_deg':maximum_roll,'detached_wheels':runtime.solver.wheels.wheels.filter(func(w):return w.detached).size(),'final_position':str(runtime.compact.center),'stats':runtime.statistics(),'scope':'42/24degree asymmetric stress fixture. Roll and mount failure are outcomes, not artificially disabled.'})
 var car:=Vehicle.new();car.setup();car.solver.terrain=terrain;car.reset(55,Vector3(69,0,0));car.solver.barrier_enabled=false
 for tick in 360:car.advance(1.0/120)
 var radius:=Vector2(car.compact.center.x,car.compact.center.z).length()
 checks['visible_ring_wall_stops_vehicle']=car.boundary_contacts>0 and radius<76
 checks['ring_wall_uses_incremental_world_damage']=car.baked_count==1 and car.last_bake.get('incremental',false) and car.last_bake.get('contact_family','')=='arena_ring' and car.full_steps==0
 for angle in [PI*.5,PI,PI*1.5]:
  var heading:=Basis(Vector3.UP,-angle);var start:=heading*Vector3(69,0,0)
  car.reset(55,start);car.solver.barrier_enabled=false
  for node in car.solver.points.size():
   car.solver.points[node]=heading*car.solver.rest[node]+start;car.solver.velocities[node]=heading*Vector3(55.0/3.6,0,0)
  for wheel in car.solver.wheels.wheels:wheel.rotation=heading.get_rotation_quaternion();wheel.previous_rotation=wheel.rotation
  car.compact.capture_shape()
  for tick in 360:car.advance(1.0/120)
  checks['ring_wall_angle_%d'%roundi(rad_to_deg(angle))]=car.boundary_contacts>0 and Vector2(car.compact.center.x,car.compact.center.z).length()<76 and car.full_steps==0
 var samples: Array=[]
 for surface_ in [terrain,FlatTerrain.new()]:
  var began:=Time.get_ticks_usec();var checksum:=0.0
  for i in 20000:checksum+=surface_.sample(Vector3(-65+fmod(i*.19,130),0,sin(i*.037)*60)).w
  samples.append({'source':'arena' if surface_==terrain else 'practice','mean_sample_us':(Time.get_ticks_usec()-began)/20000.,'checksum':checksum})
 var moving: Array=[]
 for surface_ in [terrain,FlatTerrain.new()]:
  var runtime:=Vehicle.new();runtime.setup();runtime.solver.terrain=surface_;runtime.solver.barrier_enabled=false;runtime.reset(0,Vector3(-60,0,0));runtime.solver.barrier_enabled=false;runtime.set_controls(1,0,0)
  var costs: Array=[]
  for tick in 480:
   var began:=Time.get_ticks_usec();runtime.advance(1.0/120);costs.append(Time.get_ticks_usec()-began)
  var sum:=0.0
  for cost in costs:sum+=cost
  costs.sort()
  moving.append({'terrain':'arena' if surface_==terrain else 'practice','mean_us':sum/costs.size(),'p95_us':costs[floori(costs.size()*.95)],'p99_us':costs[floori(costs.size()*.99)],'speed_kmh':runtime.velocity().length()*3.6,'full_solver_steps':runtime.full_steps})
 var passed: bool=checks.values().all(func(v):return v)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification'))
 FileAccess.open('res://verification/arena_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':runs,'moving_physics_cost':moving,'floor_query_cost':samples,'max_mesh_height_error_m':maximum_mesh_error,'max_normal_error':normal_error,'boundary_final_radius_m':radius,'scope':'Shared compact driving, same analytic/render descriptors. Ringwall is bounded rigid response; decorative upperstadium remains outside drivearea.'},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('ARENA_VERIFIED ',passed,' checks=',checks.size(),' sampling=',JSON.stringify(samples))
 quit(0 if passed else 1)
