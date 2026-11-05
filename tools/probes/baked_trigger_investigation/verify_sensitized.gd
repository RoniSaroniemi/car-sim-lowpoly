extends SceneTree
const Vehicle=preload('res://tools/probes/baked_trigger_investigation/sensitized_vehicle.gd')
var checks: Dictionary={}
var runs: Array=[]
func _initialize() -> void:
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification/trigger_investigation'))
 call_deferred('_run')
func pitch_case(pitch: float,angle: float) -> void:
 var car:=Vehicle.new();car.setup()
 car.solver.barrier_min=Vector3(40,0,-8);car.solver.barrier_max=Vector3(41,3,8)
 car.reset(120,Vector3(37.5,0,0))
 var frame:=Basis(Vector3.UP,deg_to_rad(angle))*Basis(Vector3.BACK,deg_to_rad(pitch))
 for i in car.solver.points.size():car.solver.points[i]=frame*car.solver.rest[i]+Vector3(37.5,0,0)
 for wheel in car.solver.wheels.wheels:wheel.rotation=frame.get_rotation_quaternion();wheel.previous_rotation=wheel.rotation
 var lowest:=INF
 for wheel in car.solver.wheels.wheels:lowest=minf(lowest,car.solver.points[wheel.node].y+car.solver.wheels.support(wheel,Vector3.DOWN).y)
 for i in car.solver.points.size():car.solver.points[i].y+=.01-lowest
 car.compact.capture_shape()
 for step in 60:
  car.advance(1.0/120)
  if car.baked_count>0:break
 var key: String='%d_%d'%[roundi(pitch),roundi(angle)]
 checks[key+'_recovered']=car.baked_count==1
 checks[key+'_no_heavy_solver']=car.solver.step_count==0 and car.forecast.checks==0
 checks[key+'_no_pose_pop']=car.last_bake.get('handoff_position_jump_m',INF)<.00001
 runs.append({'id':key,'baked':car.baked_count,'clip':car.last_bake.get('id',''),'classification_band_m':car.used_band,'widened_activations':car.widened_activations,'full_steps':car.solver.step_count,'legacy_forecasts':car.forecast.checks})
 print('SENSITIZED_CASE ',JSON.stringify(runs[-1]))
func _run() -> void:
 for pitch in [-6.0,-10.0]:
  for angle in [0.0,30.0]:pitch_case(pitch,angle)
 var edge:=Vehicle.new();edge.setup()
 edge.solver.barrier_min=Vector3(40,0,-8);edge.solver.barrier_max=Vector3(41,3,8)
 edge.reset_wall_approach(120,30)
 for i in edge.solver.points.size():edge.solver.points[i].z+=7
 edge.compact.capture_shape()
 for frame in 100:edge.advance(1.0/120)
 checks['partial_corner_still_rejected']=edge.baked_count==0
 var cancelled:=Vehicle.new();cancelled.setup()
 cancelled.solver.barrier_min=Vector3(40,0,-8);cancelled.solver.barrier_max=Vector3(41,3,8)
 cancelled.reset(120,Vector3(35.5,0,0))
 for frame in 4:cancelled.advance(1.0/120)
 checks['prediction_was_actually_armed']=cancelled.armed
 checks['forecast_did_not_play_early']=cancelled.baked_count==0
 cancelled.solver.barrier_enabled=false
 for frame in 60:cancelled.advance(1.0/120)
 checks['cancelled_prediction_does_not_play']=cancelled.baked_count==0 and not cancelled.armed
 var passed: bool=checks.values().all(func(value):return value)
 FileAccess.open('res://verification/trigger_investigation/sensitized_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':runs},'\t'))
 print('SENSITIZED_VERIFIED ',passed)
 quit(0 if passed else 1)
