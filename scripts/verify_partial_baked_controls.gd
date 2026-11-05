extends SceneTree
const Driving=preload('res://scripts/driving_vehicle.gd')
const Arena=preload('res://arena/vehicle.gd')
const Terrain=preload('res://arena/terrain.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Stage=preload('res://scripts/partial_wall_staging.gd')
const Partial=preload('res://scripts/partial_crash_library.gd')
var checks: Array=[]
func check_(name_: String,value: bool,details: Dictionary={}) -> void:
 checks.append({'name':name_,'passed':value,'details':details});print('PARTIAL_CONTROL ',name_,' ',value,' ',JSON.stringify(details))
func _initialize() -> void:call_deferred('_run')
func car_(arena: bool=false) -> RefCounted:
 var car: RefCounted=Arena.new() if arena else Driving.new();car.setup()
 if arena:car.solver.terrain=Terrain.new()
 car.solver.barrier_min=Vector3(40,0,-8);car.solver.barrier_max=Vector3(41,3,8)
 return car
func _run() -> void:
 var directory: String='res://verification/partial_bakes'
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with('--directory='):directory=arg.trim_prefix('--directory=')
 Driving.cached_library=Clip.read_library()+Partial.read_library(directory)
 for arena in [false,true]:
  for angle in [0.,20.]:
   var car: RefCounted=car_(arena);Stage.stage(car,60,angle,.5,'right')
   var identifier: int=car.solver.get_instance_id();var mass: float=car.solver.config.mass_kg
   var actual:=false;var finite:=true;var max_gap:=-INF
   for frame in 480:
    if car.crash_player==null and car.baked_count==0:
     var packet: Dictionary=car.contact_sensor.event(car.solver,car.velocity(),1./120)
     if not packet.is_empty():
      var gap:=INF
      for i in car.solver.points.size():
       if car.solver.wheels.by_node.has(i) and car.solver.wheels.wheels[car.solver.wheels.by_node[i]].detached:continue
       gap=minf(gap,float(car.solver.barrier_distance(car.solver.points[i]+car.solver.velocities[i]*float(packet.toi)).distance)-car.solver.radii[i])
      max_gap=maxf(max_gap,gap);actual=gap<.0001
    car.advance(1./120)
    for p in car.solver.points:finite=finite and p.is_finite()
   var permanent:=0.0
   for link in car.solver.links:permanent=maxf(permanent,absf(link.length-link.original))
   var details: Dictionary={'clip':car.last_bake.get('id',''),'actual_contact_gap_m':max_gap,'permanent_rest_change_m':permanent,'rigid_contacts':car.rigid_contact_count,'heavy_steps':car.solver.step_count,'legacy_forecasts':car.forecast.checks}
   check_('aftermath_%s_%d'%['arena' if arena else 'driving',angle],car.baked_count==1 and car.last_bake.get('completed',false) and actual and finite and permanent>.005 and car.solver.get_instance_id()==identifier and car.solver.config.mass_kg==mass and car.solver.step_count==0 and car.forecast.checks==0,details)
 # Forecast can arm without contact, then must cancel when velocity reverses.
 var car: RefCounted=car_();Stage.stage(car,60,0,1,'none',3)
 for frame in 30:
  var packet: Dictionary=car.contact_sensor.event(car.solver,car.velocity(),1./120)
  if car.contact_sensor.armed:break
  car.advance(1./120)
 var armed: bool=car.contact_sensor.armed
 for i in car.solver.velocities.size():car.solver.velocities[i]=-car.solver.velocities[i]
 car.compact.linear_velocity=-car.compact.linear_velocity
 for frame in 15:car.advance(1./120)
 check_('moving_away_cancels',armed and not car.contact_sensor.armed and car.baked_count==0,car.contact_sensor.statistics())
 # Entire car clears wall: no partial signature must invent a crash.
 car=car_();Stage.stage(car,60,20,.0,'right')
 for i in car.solver.points.size():car.solver.points[i].z+=1.5
 car.compact.capture_shape()
 for frame in 80:car.advance(1./120)
 check_('near_miss',car.baked_count==0 and car.solver.step_count==0,car.contact_sensor.statistics())
 car=car_();Stage.stage(car,60,0,.5,'right');car.solver.barrier_max.y=.8
 for frame in 80:car.advance(1./120)
 check_('short_wall_uncovered',car.baked_count==0 and car.solver.step_count==0,car.contact_sensor.statistics())
 car=car_();Stage.stage(car,60,0,.05,'right')
 for frame in 80:car.advance(1./120)
 check_('tiny_footprint_no_full_wall_clip',car.baked_count==0 and car.solver.step_count==0,car.contact_sensor.statistics())
 # Safe road cost excludes bank ranking, authoring and full deformation physics.
 car=car_();Stage.stage(car,60,0,1,'none',30)
 var start: int=Time.get_ticks_usec()
 for frame in 1000:car._contact_event(1./120)
 check_('clear_road_cost',car.solver.step_count==0 and car.forecast.checks==0 and car.contact_sensor.actual_sweeps==0,{'us_per_query':(Time.get_ticks_usec()-start)/1000.0,'sensor':car.contact_sensor.statistics()})
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification/partial_coverage'))
 FileAccess.open('res://verification/partial_coverage/controls.json',FileAccess.WRITE).store_string(JSON.stringify(checks,'\t'))
 quit(0 if checks.all(func(row):return row.passed) else 1)
