extends SceneTree
const Driving=preload('res://scripts/driving_vehicle.gd')
const Arena=preload('res://arena/vehicle.gd')
const Cases=preload('res://scripts/roof_landing_cases.gd')
const Geometry=preload('res://scripts/roof_landing_geometry.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
var checks: Dictionary={}
var runs: Array=[]
class RaisedFloor:
 extends RefCounted
 var height:=1.25
 func sample(_p: Vector3) -> Vector4:return Vector4(0,1,0,height)
class Slope:
 extends RefCounted
 func sample(p: Vector3) -> Vector4:return Vector4(-.1,1,0,p.x*.1)
func _initialize() -> void:call_deferred('_run')
func _counts(car: RefCounted) -> Array:
 return [car.full_steps,car.solver.step_count,car.solver.panels.active_steps,car.solver.effects.glass.membrane_solve_steps,car.solver.effects.interior.cloth_steps]
func _run_case(spec: Dictionary,yaw: float,step_s: float,arena: bool=false) -> void:
 var car: RefCounted=Arena.new() if arena else Driving.new();car.setup()
 car.solver.barrier_enabled=false
 Cases.place(car,spec,.30,Vector3(-45,0,0),yaw)
 car.baked_enabled=true;car.mode='DRIVE';car.solver.compact_active=true
 var graph_id: int=car.solver.get_instance_id();var saw_air:=false;var ground_error:=0.0
 var initial_height: float=car.solver.points[10].distance_to(car.solver.points[8])
 var minimum_height:=initial_height
 for tick in ceili(3.4/step_s):
  if car.mode!='BAKED' and car.baked_count==0:
   var gap: float=Geometry.minimum_gap(car.solver)
   if gap>.04:saw_air=true;checks[spec.id+'_no_early_'+str(yaw)+str(step_s)]=car.baked_count==0
  car.advance(step_s)
  if car.mode=='BAKED' and car.crash_player.time>.12:
   # Plane-preserving registration, even between roll bins and after yaw.
   var transform: Basis=car.crash_player.replay_rotation
   ground_error=maxf(ground_error,(transform*Vector3.UP).distance_to(Vector3.UP))
  minimum_height=minf(minimum_height,car.solver.points[10].distance_to(car.solver.points[8]))
 var key: String='%s_y%.2f_dt%.4f_arena%s'%[spec.id,yaw,step_s,str(arena)]
 var roof_hits: Array=car.impact_history.filter(func(hit):return hit.get('contact_family','')=='roof_landing_floor')
 var first: Dictionary=roof_hits[0] if not roof_hits.is_empty() else {}
 checks[key+'_first_landing_completed']=car.baked_count>=1 and first.get('completed',false)
 checks[key+'_actual_ground_contact']=saw_air and absf(float(first.get('contact_gap_m',INF)))<.001
 checks[key+'_zero_solvers']=_counts(car)==[0,0,0,0,0]
 checks[key+'_continuous_entry']=first.get('handoff_position_jump_m',INF)<.00001 and first.get('handoff_velocity_jump_mps',INF)<.0001
 checks[key+'_floor_not_tilted']=ground_error<.00001
 checks[key+'_same_graph_mass_finite']=graph_id==car.solver.get_instance_id() and absf(car.solver.owned_mass_kg()-1210)<.001 and Array(car.solver.points).all(func(p):return p.is_finite())
 checks[key+'_real_roof_deformation']=minimum_height<initial_height-.005
 runs.append({'case':key,'match':car.last_bake,'counters':_counts(car),'initial_cabin_height_m':initial_height,'minimum_cabin_height_m':minimum_height,'floor_rotation_error':ground_error,'mode_after':car.mode})
 print('ROOF_LANDING_CASE ',key,' ',car.last_bake.get('id','NONE'),' solves=',_counts(car))
func _negative_cases() -> void:
 var base: Dictionary=Cases.specifications()[1]
 var car:=Driving.new();car.setup();car.solver.barrier_enabled=false
 var upright: Dictionary=base.duplicate();upright.roll_deg=-180.;Cases.place(car,upright,.3)
 for tick in 60:car.advance(1.0/120)
 checks.upright_wheels_first_no_roof=car.baked_count==0 and car.roof_landing_sensor.probe_queries==0
 car=Driving.new();car.setup();car.solver.barrier_enabled=false;Cases.place(car,base,.3)
 for i in car.solver.velocities.size():car.solver.velocities[i].y=4
 car.compact.capture_shape();car.solver.panels.synchronize_inactive()
 for tick in 15:car.advance(1.0/120)
 checks.moving_away_does_not_trigger=car.baked_count==0
 car=Driving.new();car.setup();car.solver.barrier_enabled=false
 var gentle: Dictionary=base.duplicate();gentle.down_mps=.2;Cases.place(car,gentle,.001)
 for tick in 40:car.advance(1.0/120)
 checks.gentle_roof_contact_now_buckles=car.baked_count==1 and car.full_steps==0
 car=Driving.new();car.setup();car.solver.barrier_enabled=false;Cases.place(car,base,.3)
 car.solver.links[0].damage=.5
 for tick in 40:car.advance(1.0/120)
 checks.existing_damage_not_healed=car.baked_count==1 and car.last_bake.get('incremental',false) and car.solver.links[0].damage>=.5
 car=Driving.new();car.setup();car.solver.barrier_enabled=false;car.solver.terrain=Slope.new();Cases.place(car,base,.3)
 for tick in 40:car.advance(1.0/120)
 checks.slope_registers_recording_to_contact_plane=car.baked_count==1 and car.full_steps==0 and car.last_bake.get('ground_normal',[]).size()==3
 # Elevated flat ground must change only the replay origin's height.
 car=Driving.new();car.setup();car.solver.terrain=RaisedFloor.new();car.solver.barrier_enabled=false;Cases.place(car,base,.3)
 for tick in 60:car.advance(1.0/120)
 checks.raised_flat_ground_registered=car.baked_count==1 and absf(float(car.last_bake.get('floor_y',0))-1.25)<.0001 and Geometry.minimum_gap(car.solver)>-.025
func _bank_checks() -> void:
 var library: Array=Cases.read_library();checks.six_clips=library.size()==6
 for data in library:
  var id: String=data.metadata.id
  checks[id+'_exact_physical_sources']=Clip.input_compatibility(data).exact
  checks[id+'_quality_and_components']=data.metadata.physics_hz==1920 and data.frames.size()==301 and data.frames.all(func(frame):return frame.has('panels') and frame.has('effects'))
  var m: Dictionary=data.metadata.final_outcome.body_metrics
  checks[id+'_no_kinetic_explosion']=float(m.maximum_kinetic_kj)<float(m.initial_energy_kj)*1.05
func _ui_checks() -> void:
 for path in ['res://arena/colosseum.tscn','res://driving.tscn']:
  var scene: Node=load(path).instantiate();root.add_child(scene);scene.set_physics_process(false);scene.set_process(false)
  scene._start_roof_landing(40,4)
  var car: RefCounted=scene.car if path.contains('arena') else scene.vehicle
  for tick in 360:car.advance(1.0/120)
  checks[path+'_actual_shared_car_button']=car.baked_count>=1 and car.full_steps==0 and car.impact_history.any(func(hit):return hit.get('contact_family','')=='roof_landing_floor' and hit.get('completed',false))
  scene._reset();checks[path+'_repair_restores_drive']=car.baked_count==0 and car.mode=='DRIVE' and not scene.roof_landing_preview
  scene.queue_free()
func _run() -> void:
 _bank_checks()
 for spec in Cases.specifications():
  for yaw in [0.,1.1]:_run_case(spec,yaw,1.0/60)
 for roll in [-7.,7.]:
  var spec: Dictionary={'id':'unrecorded_roll_'+str(roll),'forward_kmh':60.,'down_mps':5.5,'roll_deg':roll,'roll_rate':signf(roll)*.2}
  _run_case(spec,-.8,1.0/30,true)
 _negative_cases();_ui_checks()
 var passed: bool=checks.values().all(func(v):return v)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification/roof_landing'))
 FileAccess.open('res://verification/roof_landing/validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':runs},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('ROOF_LANDINGS_VERIFIED ',passed,' checks=',checks.size(),' landings=',runs.size())
 quit(0 if passed else 1)
