extends SceneTree
const Simulation=preload('res://scripts/vehicle_simulation.gd')
const Demo=preload('res://scripts/wheel_mount_demo.gd')
const Solver=preload('res://scripts/structure_solver.gd')
var checks: Dictionary={}
var observations: Dictionary={}
func _initialize() -> void:call_deferred('_run')
func setup_bench() -> RefCounted:
 var s=Solver.new()
 s.setup()
 s.config.enforce_symmetry=false
 s.config.gravity_mps2=0
 s.barrier_enabled=false
 s.wheels.body_contact_enabled=false
 s.reset(0,Vector3(-10,3,0))
 return s
func load_wheel(s: RefCounted,lateral_force: float,torque: float,seconds: float) -> void:
 var w=s.wheels.wheels[3]
 var dt: float=s.config.fixed_step_s
 for i in roundi(seconds/dt):
  s.velocities[w.node].z+=lateral_force*s.inverse_masses[w.node]*dt
  w.angular_velocity+=s.wheels.inverse_inertia(w,Vector3(torque,0,0))*dt
  s.step(dt)
func _run() -> void:
 var light=setup_bench()
 load_wheel(light,2000,0,.12)
 var small: Dictionary=light.wheels.metrics()[3]
 observations['small_lateral_load']=small
 checks['small_load_no_lateral_flex']=absf(small.lateral_error_m)<.001
 checks['small_load_no_permanent_change']=absf(small.permanent_lateral_offset_m)<.00001 and small.permanent_alignment_deg<.01 and not small.detached
 var bent=setup_bench()
 load_wheel(bent,0,4000,.0125)
 var loaded: Dictionary=bent.wheels.metrics()[3]
 load_wheel(bent,0,0,.08)
 var unloaded: Dictionary=bent.wheels.metrics()[3]
 observations['loaded_mount']=loaded
 observations['unloaded_mount']=unloaded
 checks['strong_load_permanently_twists_mount']=loaded.permanent_alignment_deg>.05 and not loaded.detached
 checks['permanent_twist_survives_unloading']=unloaded.permanent_alignment_deg>.05 and not unloaded.detached
 var twisted_off=setup_bench()
 load_wheel(twisted_off,0,8000,.06)
 var angular_failure: Dictionary=twisted_off.wheels.metrics()[3]
 observations['angular_failure']=angular_failure
 checks['excessive_twist_releases_complete_wheel']=angular_failure.detached and angular_failure.detach_reason in ['permanent_alignment','angular_overload'] and twisted_off.wheels.wheels[3].links.all(func(l):return l.broken)
 var broken=setup_bench()
 load_wheel(broken,180000,0,.08)
 var failed: Dictionary=broken.wheels.metrics()[3]
 observations['overloaded_mount']=failed
 checks['large_load_detaches_all_supports']=failed.detached and broken.wheels.wheels[3].links.all(func(l):return l.broken)
 # A threshold release itself must preserve instantaneous momentum and pose.
 var w=bent.wheels.wheels[3]
 var p: Vector3=bent.points[w.node]
 var v: Vector3=bent.velocities[w.node]
 var rotation: Quaternion=w.rotation
 var omega: Vector3=w.angular_velocity
 var spin: float=w.spin_speed
 bent.wheels.detach(w,'verification')
 checks['release_preserves_motion']=p==bent.points[w.node] and v==bent.velocities[w.node] and rotation==w.rotation and omega==w.angular_velocity and spin==w.spin_speed
 var before: Vector3=bent.center_of_mass()
 bent.wheels.constrain_lateral_mounts(bent.config.fixed_step_s)
 checks['detached_mount_has_no_lateral_tether']=p==bent.points[w.node] and before.distance_to(bent.center_of_mass())<.00001
 var replay: Dictionary=broken.capture()
 broken.reset(0)
 checks['reset_clears_mount_state']=not broken.wheels.wheels[3].detached and is_equal_approx(broken.wheels.wheels[3].lateral_rest,broken.wheels.wheels[3].initial_lateral_rest)
 broken.restore(replay)
 checks['replay_restores_mount_failure']=broken.wheels.wheels[3].detached and broken.wheels.wheels[3].detach_reason==failed.detach_reason
 # Exercise the exact visible fixture, with gravity/floor and driving runtime.
 var visible=Simulation.new()
 visible.setup('res://vehicles/niva.json',true)
 visible.reset(0,Vector3(-25,0,0))
 var demo=Demo.new()
 demo.start(visible.solver)
 visible.before_step.connect(demo.step)
 var fixed_step: float=visible.solver.config.fixed_step_s
 for i in 1450:visible.step(fixed_step)
 checks['visible_demo_shows_all_three_stages']=demo.saw_aligned and demo.saw_bent and demo.saw_detached
 observations['visible_demo_retained_bend_deg']=demo.largest_retained_bend
 observations['visible_demo_detach_reason']=visible.solver.wheels.wheels[3].detach_reason
 var passed: bool=checks.values().all(func(c):return c)
 FileAccess.open('res://verification/wheel_mount_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'observations':observations},'\t'))
 print('WHEEL_MOUNT_VERIFICATION_COMPLETE ',passed,' ',JSON.stringify(checks),' ',JSON.stringify(observations))
 quit(0 if passed else 1)
