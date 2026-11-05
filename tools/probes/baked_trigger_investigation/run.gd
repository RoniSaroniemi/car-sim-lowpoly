extends SceneTree
const Audit=preload('res://tools/probes/baked_trigger_investigation/audit_vehicle.gd')
var runs: Array=[]
func _initialize() -> void:
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification/trigger_investigation'))
 call_deferred('_run')
func run_case(id: String,speed: float,angle: float,z_target: float,forward_motion: bool=true,throttle: float=0,start_distance: float=12,steering: float=0,wall_height: float=3) -> void:
 var car:=Audit.new();car.setup()
 car.solver.barrier_min=Vector3(40,0,-8);car.solver.barrier_max=Vector3(41,wall_height,8)
 var frame:=Basis(Vector3.UP,deg_to_rad(angle))
 var motion: Vector3=(frame*Vector3.RIGHT if forward_motion else Vector3.RIGHT)*(speed/3.6)
 var start:=Vector3(40-start_distance,0,z_target+(start_distance*tan(deg_to_rad(angle)) if forward_motion else 0))
 car.reset(speed,start)
 for i in car.solver.points.size():
  car.solver.points[i]=frame*car.solver.rest[i]+start
  car.solver.velocities[i]=motion
 for wheel in car.solver.wheels.wheels:
  wheel.rotation=frame.get_rotation_quaternion();wheel.previous_rotation=wheel.rotation
  wheel.spin_speed=-speed/3.6*(1 if forward_motion else cos(deg_to_rad(angle)))/wheel.radius
 car.compact.capture_shape()
 car.set_controls(throttle,0,steering)
 var wall_touched:=false
 var first_wall_s:=-1.0
 for step in 240:
  car.advance(1.0/120)
  if car.solver.contact_wall.has(1):
   if not wall_touched:first_wall_s=car.solver.simulated_time
   wall_touched=true
  if car.baked_count>0:break
  if wall_touched and car.solver.simulated_time>first_wall_s+.2:break
 var reasons: Array=[]
 for event in car.events:
  if event.reason not in reasons:reasons.append(event.reason)
 var result: Dictionary={'id':id,'speed_kmh':speed,'angle_deg':angle,'target_z':z_target,'forward_motion':forward_motion,'throttle':throttle,'steering':steering,'baked':car.baked_count>0,'clip':car.last_bake.get('id',''),'wall_touched':wall_touched,'first_physical_wall_s':first_wall_s,'reasons':reasons,'events':car.events,'cheap_forecasts':car.forecast_events,'legacy_forecast_calls':car.forecast.checks,'full_solver_steps':car.solver.step_count,'diagnostic_cpu_ms':car.detector_cpu_us/1000.0}
 runs.append(result)
 print('TRIGGER_AUDIT ',id,' baked=',result.baked,' touched=',wall_touched,' reasons=',reasons)
func run_pitch_case(pitch: float,angle: float) -> void:
 var car:=Audit.new();car.setup()
 car.solver.barrier_min=Vector3(40,0,-8);car.solver.barrier_max=Vector3(41,3,8)
 car.reset(120,Vector3(37.5,0,0))
 var frame:=Basis(Vector3.UP,deg_to_rad(angle))*Basis(Vector3.BACK,deg_to_rad(pitch))
 for i in car.solver.points.size():car.solver.points[i]=frame*car.solver.rest[i]+Vector3(37.5,0,0)
 for wheel in car.solver.wheels.wheels:
  wheel.rotation=frame.get_rotation_quaternion();wheel.previous_rotation=wheel.rotation
 var lowest:=INF
 for wheel in car.solver.wheels.wheels:lowest=minf(lowest,car.solver.points[wheel.node].y+car.solver.wheels.support(wheel,Vector3.DOWN).y)
 for i in car.solver.points.size():car.solver.points[i].y+=.01-lowest
 car.compact.capture_shape()
 var touched:=false
 for step in 60:
  car.advance(1.0/120)
  touched=touched or car.solver.contact_wall.has(1)
  if car.baked_count>0:break
 var reasons: Array=[]
 for event in car.events:
  if event.reason not in reasons:reasons.append(event.reason)
 var id: String='pitch_%d_yaw_%d'%[roundi(pitch),roundi(angle)]
 runs.append({'id':id,'speed_kmh':120,'angle_deg':angle,'pitch_deg':pitch,'target_z':0,'baked':car.baked_count>0,'clip':car.last_bake.get('id',''),'wall_touched':touched,'reasons':reasons,'events':car.events,'cheap_forecasts':car.forecast_events,'legacy_forecast_calls':car.forecast.checks,'full_solver_steps':car.solver.step_count})
 print('TRIGGER_AUDIT ',id,' baked=',car.baked_count>0,' reasons=',reasons)

func _run() -> void:
 for angle in [0.0,20.0,30.0,40.0]:
  run_case('forward_%d'%roundi(angle),120,angle,0)
  run_case('slam_%d'%roundi(angle),120,angle,0,false)
 for speed in [60.0,120.0]:
  for z in [5.0,6.0,6.8,7.2,7.8,8.2,8.8]:run_case('edge_%d_%.1f'%[roundi(speed),z],speed,30,z)
 run_case('throttle_30',60,30,0,true,1)
 run_case('steering_30',120,30,0,true,0,12,.12)
 run_case('steering_hard_30',120,30,0,true,0,12,.5)
 run_case('long_throttle_30',60,30,0,true,1,35,0)
 run_case('steering_full_30',120,30,0,true,0,12,1)
 for height in [.8,1.2,1.6]:run_case('height_%.1f'%height,120,0,0,true,0,12,0,height)
 for pitch in [-3.0,-6.0,-10.0,6.0]:
  for angle in [0.0,30.0]:run_pitch_case(pitch,angle)
 var bounded: bool=runs.size()==38 and runs.all(func(run):return run.full_solver_steps==0 and run.legacy_forecast_calls==0)
 FileAccess.open('res://verification/trigger_investigation/results.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':bounded,'runs':runs},'\t'))
 FileAccess.open('res://verification/trigger_investigation/source_fingerprints.json',FileAccess.WRITE).store_string(JSON.stringify({'frozen_wrapper_sha256':FileAccess.get_sha256('res://tools/probes/baked_trigger_investigation/baseline_driving_vehicle.gd'),'shared_core_sha256':FileAccess.get_sha256('res://scripts/vehicle_simulation.gd'),'grid_sha256':FileAccess.get_sha256('res://scripts/impact_zone_grid.gd')},'\t'))
 print('TRIGGER_AUDIT_COMPLETE ',bounded,' cases=',runs.size())
 quit(0 if bounded else 1)
