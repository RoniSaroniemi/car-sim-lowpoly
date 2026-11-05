extends RefCounted
## One mass owner; adaptive stepping changes body representation, not the car.
signal before_step(dt: float)
const Structure=preload('res://scripts/structure_solver.gd')
const Dynamics=preload('res://scripts/vehicle_dynamics.gd')
const Compact=preload('res://scripts/compact_chassis.gd')
const Forecast=preload('res://scripts/collision_forecast.gd')
const Effects=preload('res://scripts/vehicle_effects.gd')
var solver: RefCounted
var dynamics: RefCounted
var profile: Dictionary
var driving:=false
var adaptive_enabled:=true
var accumulator:=0.0
var compact: RefCounted
var forecast: RefCounted
var mode: String='FULL'
var coarse_step:=1.0/120.0
var last_prediction: Dictionary={}
var transitions: Array[Dictionary]=[]
var drive_steps:=0
var full_steps:=0
var sleep_steps:=0
var drive_seconds:=0.0
var full_seconds:=0.0
var sleep_seconds:=0.0
var drive_cpu_us:=0
var full_cpu_us:=0
var sleep_cpu_us:=0
var handoff_max_position_error:=0.0
var handoff_max_velocity_error:=0.0
var full_since:=0.0
var full_minimum_until:=0.0
var forecast_clear_time:=0.0
var contact_since_wake:=false
var wake_plastic_work:=0.0
var last_wake_reason: String=''
var settle_poll:=0.0
var quiet_time:=0.0
var drive_quiet_time:=0.0
var last_plastic_work:=0.0
var sleeping_box_min:=Vector3.ZERO
var sleeping_box_max:=Vector3.ZERO
var sleep_energy_removed_j:=0.0
var deformation_sleep_energy_j:=2.0
var energy_quiet_s:=.25
var false_alarm_energy_j:=5.0
var forecast_clear_s:=.15
var deformation_energy_j:=0.0

func setup(profile_path: String='res://vehicles/niva.json',enable_driving: bool=false) -> void:
 profile=JSON.parse_string(FileAccess.get_file_as_string(profile_path))
 solver=Structure.new()
 solver.setup(profile.structure)
 solver.effects=Effects.new()
 solver.effects.setup(solver,profile.get('effects',{}))
 driving=enable_driving
 dynamics=Dynamics.new()
 dynamics.setup(solver,profile.dynamics)
 compact=Compact.new()
 compact.setup(solver)
 solver.compact=compact
 forecast=Forecast.new()
 var options: Dictionary=profile.get('adaptive',{})
 forecast.horizon=float(options.get('lookahead_s',.18))
 deformation_sleep_energy_j=float(options.get('deformation_sleep_energy_j',2.0))
 energy_quiet_s=float(options.get('energy_quiet_s',.25))
 false_alarm_energy_j=float(options.get('false_alarm_energy_j',5.0))
 forecast_clear_s=float(options.get('forecast_clear_s',.15))
 if driving:solver.config.enforce_symmetry=false
 reset()

func reset(speed_kmh: float=0,start: Vector3=Vector3(-9,0,0),weaken: bool=false) -> void:
 accumulator=0
 solver.compact_active=false
 dynamics.reset()
 solver.reset(speed_kmh,start,weaken)
 solver.wake_requested=''
 solver.wake_hold_seconds=0
 compact.capture_shape()
 mode='DRIVE' if driving and adaptive_enabled else 'FULL'
 solver.compact_active=mode=='DRIVE'
 transitions.clear()
 drive_steps=0;full_steps=0;sleep_steps=0
 drive_seconds=0;full_seconds=0;sleep_seconds=0
 drive_cpu_us=0;full_cpu_us=0;sleep_cpu_us=0
 handoff_max_position_error=0;handoff_max_velocity_error=0
 full_since=0;settle_poll=0;quiet_time=0;drive_quiet_time=0;last_plastic_work=0
 sleep_energy_removed_j=0
 deformation_energy_j=0
 full_minimum_until=0;forecast_clear_time=0;contact_since_wake=false;wake_plastic_work=0;last_wake_reason=''
 forecast.checks=0
 last_prediction={}

func set_simulation_quality(multiplier: int=1) -> void:
 var factor: int=multiplier if multiplier in [1,2,4] else 1
 solver.config['simulation_quality_multiplier']=factor
 solver.config.fixed_step_s=1.0/(480.0*factor)
 for link in solver.links:
  link.damping_fraction=1-exp(-link.damping_ns_per_m*link.weight_sum*float(solver.config.fixed_step_s))

func set_controls(throttle: float,brake: float,steering: float,handbrake: float=0) -> void:
 dynamics.set_controls(throttle,brake,steering,handbrake)

func wake(reason: String='external_load') -> void:
 solver.request_full_solve(reason)
 if mode!='FULL':_wake(reason)

func _wake(reason: String) -> void:
 if mode=='FULL':
  full_minimum_until=maxf(full_minimum_until,solver.simulated_time+solver.wake_hold_seconds)
  solver.wake_hold_seconds=0
  solver.wake_requested=''
  return
 var previous: String=mode
 # Exported node state already IS the current physical state. Keep it intact.
 var positions: PackedVector3Array=solver.points.duplicate()
 var velocities: PackedVector3Array=solver.velocities.duplicate()
 solver.compact_active=false
 mode='FULL'
 full_since=solver.simulated_time
 full_minimum_until=solver.simulated_time+maxf(.15,solver.wake_hold_seconds)
 solver.wake_hold_seconds=0
 forecast_clear_time=0
 contact_since_wake=false
 wake_plastic_work=solver.plastic_work
 last_wake_reason=reason
 quiet_time=0
 last_plastic_work=solver.plastic_work
 solver.wake_requested=''
 var position_error:=0.0
 var velocity_error:=0.0
 for i in positions.size():
  position_error=maxf(position_error,positions[i].distance_to(solver.points[i]))
  velocity_error=maxf(velocity_error,velocities[i].distance_to(solver.velocities[i]))
 handoff_max_position_error=maxf(handoff_max_position_error,position_error)
 handoff_max_velocity_error=maxf(handoff_max_velocity_error,velocity_error)
 transitions.append({'from':previous,'to':'FULL','reason':reason,'time_s':solver.simulated_time,'position_jump_m':position_error,'velocity_jump_mps':velocity_error,'prediction':last_prediction.duplicate()})

func step(dt: float) -> void:
 advance(dt)

func advance(elapsed: float,time_scale: float=1.0) -> void:
 accumulator+=elapsed*time_scale
 var fine: float=solver.config.fixed_step_s
 while true:
  var required: float=coarse_step if mode!='FULL' else fine
  if accumulator+1e-10<required:break
  var began: int=Time.get_ticks_usec()
  if mode=='DRIVE':
   if not adaptive_enabled:_wake('full_reference')
   elif solver.wake_requested!='':_wake(solver.wake_requested)
   else:
    last_prediction=forecast.predict(solver,compact.linear_velocity,compact.angular_velocity)
    if last_prediction.risk:_wake(last_prediction.reason)
  elif mode=='SLEEP':
   if solver.wake_requested!='' or sleeping_box_min!=solver.barrier_min or sleeping_box_max!=solver.barrier_max or forecast.obstacle_velocity.length()>.001:
    _wake('sleep_wakeup')
   elif absf(dynamics.throttle)+absf(dynamics.steering)>.001:
    last_prediction=forecast.predict(solver,Vector3.ZERO,Vector3.ZERO)
    if last_prediction.risk:_wake('input_near_contact')
    else:
     compact.capture_shape()
     solver.compact_active=true
     mode='DRIVE'
     drive_quiet_time=0
     transitions.append({'from':'SLEEP','to':'DRIVE','reason':'driving_input','time_s':solver.simulated_time})
  var h: float=fine if mode=='FULL' else coarse_step
  before_step.emit(h)
  if mode!='FULL' and (solver.wake_requested!='' or compact.external_change()):
   _wake(solver.wake_requested if solver.wake_requested!='' else 'external_state_change')
   # The fixture supplied an impulse for h. Integrate that same interval once.
   var remaining: float=h
   while remaining>fine*.5:
    if driving:dynamics.step(fine)
    solver.step(fine)
    solver.effects.step_live(fine)
    full_steps+=1;full_seconds+=fine
    remaining-=fine
   full_cpu_us+=Time.get_ticks_usec()-began
  elif mode=='DRIVE':
   if driving:dynamics.step(h)
   compact.step(h)
   solver.effects.step_live(h)
   drive_steps+=1;drive_seconds+=h
   if compact.wake_reason!='':_wake(compact.wake_reason)
   else:_try_sleep_drive(h)
   drive_cpu_us+=Time.get_ticks_usec()-began
  elif mode=='FULL':
   if solver.wake_requested!='':_wake(solver.wake_requested)
   if driving:dynamics.step(h)
   solver.step(h)
   solver.effects.step_live(h)
   full_steps+=1;full_seconds+=h
   _try_settle(h)
   full_cpu_us+=Time.get_ticks_usec()-began
  else:
   solver.simulated_time+=h
   solver.effects.step_live(h)
   sleep_steps+=1;sleep_seconds+=h
   sleep_cpu_us+=Time.get_ticks_usec()-began
  accumulator=maxf(0,accumulator-h)

func _stationary() -> bool:
 if absf(dynamics.throttle)+absf(dynamics.steering)>.001:return false
 if compact.linear_velocity.length()>.04 or compact.angular_velocity.length()>.03:return false
 for w in solver.wheels.wheels:
  if solver.velocities[w.node].length()>.04 or w.angular_velocity.length()>.08 or absf(w.spin_speed)*w.radius>.04:return false
 return solver.kinetic_energy()<1.0

func _enter_sleep() -> void:
 var previous: String=mode
 var energy: float=solver.kinetic_energy()
 solver.velocities.fill(Vector3.ZERO)
 for w in solver.wheels.wheels:
  w.angular_velocity=Vector3.ZERO
  w.spin_speed=0
 compact.capture_shape()
 solver.compact_active=false
 sleep_energy_removed_j+=energy
 mode='SLEEP'
 sleeping_box_min=solver.barrier_min
 sleeping_box_max=solver.barrier_max
 transitions.append({'from':previous,'to':mode,'reason':'stationary_settled','time_s':solver.simulated_time,'energy_removed_j':energy})

func _try_sleep_drive(dt: float) -> void:
 drive_quiet_time=drive_quiet_time+dt if _stationary() else 0.0
 if drive_quiet_time>=.5:_enter_sleep()

func _internal_motion_energy() -> float:
 var energy:=0.0
 for i in compact.indices:energy+=.5*solver.masses[i]*solver.velocities[i].distance_squared_to(compact.point_velocity(i))
 for w in solver.wheels.wheels:
  if w.detached:continue
  var rigid_velocity: Vector3=compact.linear_velocity+compact.angular_velocity.cross(solver.points[w.node]-compact.center)
  energy+=.5*solver.masses[w.node]*solver.velocities[w.node].distance_squared_to(rigid_velocity)
  energy+=.5*w.inertia_tilt*w.angular_velocity.distance_squared_to(compact.angular_velocity)
 # Forward travel, whole-car rotation and free bearing spin are not deformation.
 return energy

func _try_settle(dt: float) -> void:
 if not adaptive_enabled or not driving:return
 for i in solver.points.size():
  if solver.contact_wall[i] or (solver.contact_floor[i] and not solver.wheels.by_node.has(i)):contact_since_wake=true
 settle_poll+=dt
 if settle_poll<.05:return
 var interval: float=settle_poll
 settle_poll=0
 compact.capture_shape()
 last_prediction=forecast.predict(solver,compact.linear_velocity,compact.angular_velocity)
 var residual_energy:=0.0
 for i in compact.indices:residual_energy+=.5*solver.masses[i]*solver.velocities[i].distance_squared_to(compact.point_velocity(i))
 deformation_energy_j=_internal_motion_energy()
 var undamaged: bool=solver.plastic_work-wake_plastic_work<1.0
 if not last_prediction.risk and not contact_since_wake and undamaged and residual_energy<false_alarm_energy_j:
  forecast_clear_time+=interval
 else:forecast_clear_time=0
 if forecast_clear_time>=forecast_clear_s and solver.simulated_time>=full_minimum_until:
  _return_to_drive('forecast_cleared')
  return
 if solver.simulated_time-full_since<.6:return
 var damage_delta: float=solver.plastic_work-last_plastic_work
 last_plastic_work=solver.plastic_work
 if deformation_energy_j>deformation_sleep_energy_j or damage_delta>1.0:
  quiet_time=0
  return
 quiet_time+=interval
 if quiet_time<energy_quiet_s:return
 last_prediction=forecast.predict(solver,compact.linear_velocity,compact.angular_velocity)
 if not last_prediction.risk:_return_to_drive('structure_settled')
 elif _stationary():_enter_sleep()

func _return_to_drive(reason: String) -> void:
 var previous: String=mode
 var before_energy: float=solver.kinetic_energy()
 solver.compact_active=true
 compact.flush()
 var removed_energy: float=before_energy-solver.kinetic_energy()
 mode='DRIVE'
 drive_quiet_time=0
 transitions.append({'from':previous,'to':mode,'reason':reason,'time_s':solver.simulated_time,'residual_energy_removed_j':removed_energy})

func velocity() -> Vector3:
 return dynamics.body_velocity()

func forward() -> Vector3:
 return dynamics.body_forward()

func statistics() -> Dictionary:
 var seconds: float=drive_seconds+full_seconds+sleep_seconds
 return {'mode':mode,'drive_steps':drive_steps,'full_steps':full_steps,'sleep_steps':sleep_steps,'drive_seconds':drive_seconds,'full_seconds':full_seconds,'sleep_seconds':sleep_seconds,'drive_cpu_ms':drive_cpu_us/1000.0,'full_cpu_ms':full_cpu_us/1000.0,'total_cpu_ms':(drive_cpu_us+full_cpu_us+sleep_cpu_us)/1000.0,'cpu_ms_per_sim_second':float(drive_cpu_us+full_cpu_us+sleep_cpu_us)/1000.0/maxf(.001,seconds),'forecast_checks':forecast.checks,'full_time_fraction':full_seconds/maxf(.001,seconds),'handoff_position_jump_m':handoff_max_position_error,'handoff_velocity_jump_mps':handoff_max_velocity_error,'deformation_energy_j':deformation_energy_j,'deformation_sleep_energy_j':deformation_sleep_energy_j,'sleep_energy_removed_j':sleep_energy_removed_j,'transitions':transitions.duplicate(true)}
