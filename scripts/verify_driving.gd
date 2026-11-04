extends SceneTree
const Simulation=preload('res://scripts/vehicle_simulation.gd')
var checks: Dictionary={}
var observations: Dictionary={}
func _initialize() -> void:call_deferred('_run')
func make_vehicle() -> RefCounted:
 var vehicle=Simulation.new()
 vehicle.setup('res://vehicles/niva.json',true)
 vehicle.solver.barrier_enabled=false
 vehicle.reset(0,Vector3(-30,0,0))
 return vehicle
func advance(vehicle: RefCounted,seconds: float) -> void:
 var dt: float=vehicle.solver.config.fixed_step_s
 for i in roundi(seconds/dt):vehicle.step(dt)
func finite_vehicle(vehicle: RefCounted) -> bool:
 for p in vehicle.solver.points:
  if not p.is_finite():return false
 for w in vehicle.solver.wheels.metrics():
  if not w.angular_finite:return false
 return vehicle.velocity().length()<80.0
func _run() -> void:
 var car=make_vehicle()
 advance(car,.6)
 var start: Vector3=car.solver.center_of_mass()
 car.set_controls(1,0,0)
 advance(car,3)
 var forward_speed: float=car.velocity().dot(car.forward())
 observations['accelerated_speed_kmh']=forward_speed*3.6
 observations['distance_m']=car.solver.center_of_mass().distance_to(start)
 observations['drive_damage']=car.solver.metrics()
 checks['throttle_accelerates_same_structural_vehicle']=forward_speed>3 and observations.distance_m>4
 checks['ordinary_straight_driving_keeps_suspension']=car.solver.links.all(func(l):return not l.broken)
 checks['ordinary_straight_driving_does_not_yield_structure']=car.solver.plastic_work==0
 checks['ordinary_driving_locks_sideways_wheel_mounts']=car.solver.wheels.metrics().all(func(w):return absf(w.lateral_error_m)<.001 and absf(w.permanent_lateral_offset_m)<.00001)
 car.set_controls(0,1,0)
 advance(car,2)
 observations['braked_speed_kmh']=car.velocity().length()*3.6
 checks['brake_reduces_speed']=car.velocity().length()<forward_speed*.6
 checks['finite_acceleration_and_braking']=finite_vehicle(car)
 var turns: Array=[]
 for steer in [1.0,-1.0]:
  var turn=make_vehicle()
  turn.reset(18,Vector3(-30,0,0))
  turn.set_controls(.15,0,steer*.5)
  advance(turn,1.5)
  turns.append({'z':turn.solver.station_center(2).z,'forward':turn.forward(),'finite':finite_vehicle(turn),'broken':turn.solver.metrics().broken_suspension_links,'work':turn.solver.plastic_work})
 observations['turns']=turns
 checks['left_input_turns_left']=turns[0].z>.05
 checks['right_input_turns_right']=turns[1].z<-.05
 checks['ordinary_turning_keeps_suspension']=turns.all(func(t):return t.broken==0)
 checks['ordinary_turning_does_not_yield_structure']=turns.all(func(t):return t.work==0)
 checks['finite_turns']=turns.all(func(t):return t.finite)
 var full_lock=make_vehicle()
 full_lock.reset(12,Vector3(-30,0,0))
 full_lock.set_controls(.1,0,1)
 advance(full_lock,1.5)
 observations['full_lock_mounts']=full_lock.solver.wheels.metrics()
 observations['full_lock_work_kj']=full_lock.solver.plastic_work/1000.0
 checks['commanded_full_lock_does_not_damage_mounts']=full_lock.solver.wheels.metrics().all(func(w):return not w.detached and w.permanent_alignment_deg<.01 and absf(w.permanent_lateral_offset_m)<.00001) and full_lock.solver.plastic_work==0
 var reverse=make_vehicle()
 reverse.set_controls(-1,0,0)
 advance(reverse,2)
 observations['reverse_speed_kmh']=reverse.velocity().dot(reverse.forward())*3.6
 checks['reverse_moves_backward']=observations.reverse_speed_kmh< -3
 # Same controller supports alternative tuning without touching either scene.
 var gentle=make_vehicle()
 gentle.dynamics.parameters.drive_torque_nm=600.0
 gentle.set_controls(1,0,0)
 advance(gentle,3)
 observations['gentle_speed_kmh']=gentle.velocity().dot(gentle.forward())*3.6
 checks['car_profile_changes_acceleration']=observations.gentle_speed_kmh<forward_speed*3.6*.85
 # Damage and driving coexist in one graph; acceleration cannot reset a wreck.
 var crash=make_vehicle()
 crash.solver.barrier_enabled=true
 crash.solver.set_impact_mode(0)
 crash.reset(80,Vector3(-9,0,0))
 advance(crash,1)
 var permanent: float=crash.solver.plastic_work
 crash.set_controls(.5,0,.1)
 advance(crash,.5)
 checks['crash_and_driving_share_persistent_damage']=permanent>1000 and crash.solver.plastic_work>=permanent and finite_vehicle(crash)
 crash.reset()
 checks['reset_clears_controls_and_damage']=crash.dynamics.throttle==0 and crash.dynamics.steering==0 and crash.solver.plastic_work==0
 # Losing a wheel must release it from driver inputs as well as body supports.
 var loose=make_vehicle()
 var free_wheel=loose.solver.wheels.wheels[3]
 free_wheel.detached=true
 free_wheel.joint_broken=true
 free_wheel.spin_speed=7.0
 free_wheel.steering_angle=.12
 loose.set_controls(1,1,1,1)
 loose.dynamics.step(loose.solver.config.fixed_step_s)
 checks['detached_wheel_receives_no_drive_brake_or_steering']=free_wheel.spin_speed==7.0 and free_wheel.steering_angle==.12
 # Rendering tick size must not change the fixed-step vehicle integration.
 var slow_frames=make_vehicle()
 var fast_frames=make_vehicle()
 slow_frames.set_controls(.4,0,.1)
 fast_frames.set_controls(.4,0,.1)
 for i in 30:slow_frames.advance(1.0/30.0)
 for i in 120:fast_frames.advance(1.0/120.0)
 var clock_error:=0.0
 for i in slow_frames.solver.points.size():clock_error=maxf(clock_error,slow_frames.solver.points[i].distance_to(fast_frames.solver.points[i]))
 observations['frame_chunking_max_position_error_m']=clock_error
 checks['render_frame_chunking_preserves_physics']=clock_error<.00001 and slow_frames.solver.step_count==fast_frames.solver.step_count
 var passed: bool=checks.values().all(func(value):return value)
 FileAccess.open('res://verification/driving_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'observations':observations},'\t'))
 print('DRIVING_VERIFICATION_COMPLETE ',passed,' ',JSON.stringify(checks),' ',JSON.stringify(observations))
 quit(0 if passed else 1)
