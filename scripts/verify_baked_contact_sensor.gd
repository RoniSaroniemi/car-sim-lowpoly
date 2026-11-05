extends SceneTree
const Sensor=preload('res://scripts/baked_contact_sensor.gd')
class TestVehicle:
 extends 'res://scripts/driving_vehicle.gd'
 var test_sensor:=preload('res://scripts/baked_contact_sensor.gd').new()
 var selected_band:=0.0
 func reset(speed_kmh: float=0,start: Vector3=Vector3(-9,0,0),weaken: bool=false) -> void:
  test_sensor.reset();selected_band=0
  super.reset(speed_kmh,start,weaken)
 func _contact_event(horizon: float) -> Dictionary:
  var motion: Vector3=velocity()
  if not test_sensor.nearby(solver,motion):test_sensor.cancel('clear');return {}
  if not _basic_eligibility():test_sensor.cancel('ineligible');return {}
  var packet: Dictionary=test_sensor.event(solver,motion,horizon)
  if packet.is_empty():return {}
  if packet.bounds_min.z<solver.barrier_min.z+.1 or packet.bounds_max.z>solver.barrier_max.z-.1:
   test_sensor.note_rejection('partial_wall_width');return {}
  if packet.bounds_max.y>solver.barrier_max.y:
   test_sensor.note_rejection('partial_wall_height');return {}
  var candidates: Array=[{'band_m':.025,'signature':packet.signature}]
  candidates.append_array(packet.fallback_signatures)
  for candidate in candidates:
   var signature: Dictionary=candidate.signature
   if signature.is_empty():continue
   var normal:=Vector3(signature.world_normal[0],signature.world_normal[1],signature.world_normal[2])
   if absf(normal.x)<=.99:test_sensor.note_rejection('short_end_or_corner_normal');return {}
   var selection: Dictionary=_choose_speed_bin(signature)
   if not selection.get('accepted',false):continue
   selected_band=candidate.band_m
   selection['classification_band_m']=selected_band
   return {'toi':packet.toi,'signature':signature,'selection':selection}
  test_sensor.note_rejection('bank_match');return {}
var checks: Dictionary={}
var runs: Array=[]
func _initialize() -> void:call_deferred('_run')
func make_car() -> RefCounted:
 var car:=TestVehicle.new();car.setup()
 car.solver.barrier_min=Vector3(40,0,-8);car.solver.barrier_max=Vector3(41,3,8)
 return car
func pitch_case(pitch: float,angle: float) -> void:
 var car=make_car();car.reset(120,Vector3(37.5,0,0))
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
 var expected: String='frontal_120' if angle==0 else 'impact_030_120'
 checks[key+'_correct_clip']=car.baked_count==1 and car.last_bake.get('id','')==expected
 checks[key+'_no_heavy_solver']=car.solver.step_count==0 and car.forecast.checks==0
 checks[key+'_no_pose_pop']=car.last_bake.get('handoff_position_jump_m',INF)<.00001
 checks[key+'_armed_wide_band']=car.selected_band>.025 and car.test_sensor.arm_count>0
 runs.append({'id':key,'baked':car.baked_count,'clip':car.last_bake.get('id',''),'classification_band_m':car.selected_band,'sensor':car.test_sensor.statistics()})
 print('CONTACT_SENSOR_CASE ',key,' clip=',car.last_bake.get('id','NONE'),' band=',car.selected_band)
func _run() -> void:
 for pitch in [-6.0,-10.0]:
  for angle in [0.0,30.0]:pitch_case(pitch,angle)
 var ordinary=make_car();ordinary.reset_wall_approach(120,30)
 for frame in 100:
  ordinary.advance(1.0/120)
  if ordinary.baked_count>0:break
 checks['ordinary_narrow_match_still_works']=ordinary.baked_count==1 and ordinary.selected_band==.025
 var edge=make_car();edge.reset_wall_approach(120,30)
 for i in edge.solver.points.size():edge.solver.points[i].z+=7
 edge.compact.capture_shape()
 for frame in 100:edge.advance(1.0/120)
 checks['partial_corner_still_rejected']=edge.baked_count==0
 var low=make_car();low.solver.barrier_max.y=1.2;low.reset_wall_approach(120)
 for frame in 100:low.advance(1.0/120)
 checks['partial_height_still_rejected']=low.baked_count==0
 var cancelled=make_car();cancelled.reset(120,Vector3(35.5,0,0))
 for frame in 8:
  cancelled.advance(1.0/120)
  if cancelled.test_sensor.armed:break
 checks['prediction_was_actually_armed']=cancelled.test_sensor.armed
 checks['forecast_does_not_play_early']=cancelled.baked_count==0
 cancelled.solver.barrier_enabled=false
 for frame in 40:cancelled.advance(1.0/120)
 checks['removed_obstacle_cancels']=cancelled.baked_count==0 and not cancelled.test_sensor.armed
 var turning=make_car();turning.reset(120,Vector3(35.5,0,0))
 for frame in 8:
  turning.advance(1.0/120)
  if turning.test_sensor.armed:break
 for i in turning.solver.velocities.size():turning.solver.velocities[i]=Vector3(0,0,25)
 turning.compact.capture_shape()
 for frame in 20:turning.advance(1.0/120)
 checks['steering_away_invalidates']=turning.baked_count==0 and turning.test_sensor.cancel_count>0
 var remote=make_car();remote.reset(120,Vector3(-25,0,0))
 var sensor:=Sensor.new()
 var pristine: Dictionary=remote.solver.capture()
 for call_index in 600:sensor.event(remote.solver,remote.velocity(),1.0/120)
 checks['clear_road_no_node_sweep_or_rank']=sensor.forecast_checks==0 and sensor.actual_sweeps==0 and sensor.statistics().library_rankings==0
 checks['sensor_does_not_mutate_graph']=remote.solver.points==pristine.points and remote.solver.velocities==pristine.velocities and remote.solver.simulated_time==pristine.time
 var obstacle=make_car();obstacle.reset(120,Vector3(35.5,0,0))
 for frame in 8:
  obstacle.advance(1.0/120)
  if obstacle.test_sensor.armed:break
 obstacle.solver.barrier_min.x=70;obstacle.solver.barrier_max.x=71
 obstacle.test_sensor.event(obstacle.solver,obstacle.velocity(),1.0/120)
 checks['changed_obstacle_invalidates']=not obstacle.test_sensor.armed and obstacle.test_sensor.last_cancel=='obstacle_changed'
 checks['all_cases_completed']=runs.size()==4
 var passed: bool=checks.values().all(func(value):return value)
 FileAccess.open('res://verification/baked_contact_sensor_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':runs},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('BAKED_CONTACT_SENSOR_VERIFIED ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
