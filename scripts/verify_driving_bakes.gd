extends SceneTree
const Vehicle=preload('res://scripts/driving_vehicle.gd')
var checks: Dictionary={}
var runs: Array=[]
func _initialize() -> void:call_deferred('_run')
func test_case(speed: float,angle: float) -> void:
 var vehicle:=Vehicle.new();vehicle.setup()
 vehicle.solver.barrier_min=Vector3(40,0,-8);vehicle.solver.barrier_max=Vector3(41,3,8)
 vehicle.reset_wall_approach(speed,angle)
 var prior_clock:=0.0;var clock_ok:=true;var replay_steps:=0;var finite:=true
 var steps_at_start: int=-1;var zero_live_during_replay:=true;var stable_identity: int=vehicle.solver.get_instance_id()
 for i in 520:
  vehicle.set_controls(0,0,0)
  vehicle.advance(1.0/120)
  clock_ok=clock_ok and vehicle.solver.simulated_time+1e-8>=prior_clock
  prior_clock=vehicle.solver.simulated_time
  for p in vehicle.solver.points:finite=finite and p.is_finite()
  if vehicle.mode=='BAKED':
   replay_steps+=1
   if steps_at_start<0:steps_at_start=vehicle.solver.step_count
   zero_live_during_replay=zero_live_during_replay and vehicle.solver.step_count==steps_at_start
  if vehicle.last_bake.get('completed',false):break
 var key: String='%s_%s'%[speed,angle]
 checks[key+'_triggered']=vehicle.baked_count==1 and replay_steps>0
 checks[key+'_same_vehicle_graph']=vehicle.solver.get_instance_id()==stable_identity and vehicle.crash_player==null
 checks[key+'_light_driving_until_contact']=vehicle.bake_start_full_steps==0
 checks[key+'_no_solver_during_replay']=zero_live_during_replay and vehicle.last_bake.get('solver_steps_during_replay',-1)==0
 checks[key+'_continuous_pose_and_velocity']=vehicle.last_bake.get('handoff_position_jump_m',INF)<.00001 and vehicle.last_bake.get('handoff_velocity_jump_mps',INF)<.0001
 checks[key+'_clock_monotonic']=clock_ok
 checks[key+'_returns_rigid_with_damage']=vehicle.mode=='DRIVE' and Array(vehicle.solver.node_damage).max()>.001
 var damage_before: float=vehicle.solver.plastic_work
 for i in 120:vehicle.advance(1.0/120)
 checks[key+'_lightweight_physics_runs_after_clip']=vehicle.drive_steps>0 and vehicle.full_steps==0 and vehicle.forecast.checks==0 and vehicle.solver.plastic_work+1>=damage_before
 checks[key+'_finite']=finite and vehicle.solver.points[0].is_finite()
 var minimum_clearance:=INF
 for index in vehicle.compact.indices:minimum_clearance=minf(minimum_clearance,vehicle.solver.points[index].y-vehicle.solver.radii[index])
 checks[key+'_rigid_body_supported_after_replay']=minimum_clearance>-.03
 runs.append({'speed':speed,'angle':angle,'bake':vehicle.last_bake,'stats':vehicle.statistics()})
 print('DRIVE_BAKE_CASE ',key,' clip=',vehicle.last_bake.get('id','NONE'),' live_steps_in_replay=',vehicle.last_bake.get('solver_steps_during_replay',-1))
 vehicle.reset()
 checks[key+'_repair_rearms']=vehicle.baked_count==0 and not vehicle.baked_consumed and vehicle.crash_player==null and Array(vehicle.solver.node_damage).max()==0
func extra_checks() -> void:
 var car:=Vehicle.new();car.setup()
 car.solver.barrier_min=Vector3(40,0,-8);car.solver.barrier_max=Vector3(41,3,8)
 car.reset(0,Vector3(-25,0,0));car.set_controls(1,0,0)
 for i in 1000:
  car.advance(1.0/120)
  if car.mode=='BAKED':break
 checks['actual_throttle_from_rest_triggers_bake']=car.mode=='BAKED' and car.last_bake.actual_impact_kmh>70
 car.reset()
 checks['reset_interrupts_playback']=car.crash_player==null and car.mode=='DRIVE' and car.solver.step_count==0
 car.reset_wall_approach(60)
 for i in car.solver.points.size():car.solver.points[i].z+=20
 car.compact.capture_shape()
 for i in 120:car.advance(1.0/120)
 checks['passing_outside_wall_does_not_bake']=car.baked_count==0 and car.full_steps==0
 car.reset_wall_approach(60);car.baked_enabled=false
 for i in 160:car.advance(1.0/120)
 checks['disabled_uses_live_collision']=car.baked_count==0 and car.full_steps>0 and car.solver.plastic_work>0
 car.baked_enabled=true;car.reset(20,Vector3(36,0,0))
 for i in 160:car.advance(1.0/120)
 checks['low_speed_uses_rigid_contact']=car.baked_count==0 and car.full_steps==0 and car.rigid_contact_count>0
 car.reset_wall_approach(60);car.solver.links[0].damage=.2
 for i in 140:car.advance(1.0/120)
 checks['preexisting_damage_uses_rigid_without_healing']=car.baked_count==0 and car.full_steps==0 and car.rigid_contact_count>0 and car.solver.links[0].damage>=.2
 car.reset_wall_approach(60)
 for i in 50:car.advance(1.0/120)
 car.solver.barrier_enabled=false
 for i in 80:car.advance(1.0/120)
 checks['removed_barrier_stays_drivable']=car.baked_count==0 and car.mode=='DRIVE'
 var terrain=preload('res://scripts/practice_terrain.gd').new()
 car.solver.terrain=terrain
 for index in terrain.ramps.size():
  var ramp: Dictionary=terrain.ramps[index]
  car.reset(60,Vector3(ramp.start-18,0,ramp.z));car.set_controls(.1,0,0)
  var airborne:=false;var landed:=false
  for i in 600:
   car.advance(1.0/120)
   var gap:=INF
   for wheel in car.solver.wheels.wheels:
    var p: Vector3=car.solver.points[wheel.node]
    gap=minf(gap,p.y+car.solver.wheels.support(wheel,Vector3.DOWN).y-terrain.sample(p).w)
   if gap>.1:airborne=true
   if airborne and gap<.01:landed=true
  checks['ramp_%d_stays_lightweight_and_lands'%index]=car.baked_count==0 and car.full_steps==0 and car.forecast.checks==0 and airborne and landed
func tuning_checks() -> void:
 var slow:=Vehicle.new();slow.setup();slow.solver.barrier_enabled=false;slow.baked_enabled=false
 slow.set_engine_power_kw(110);slow.reset(0,Vector3(-30,0,0));slow.set_controls(1,0,0)
 for i in 240:slow.advance(1.0/120)
 var fast:=Vehicle.new();fast.setup();fast.solver.barrier_enabled=false;fast.baked_enabled=false
 fast.set_engine_power_kw(440);fast.reset(0,Vector3(-30,0,0));fast.set_controls(1,0,0)
 for i in 240:fast.advance(1.0/120)
 checks['power_slider_changes_actual_acceleration']=fast.velocity().length()>slow.velocity().length()*1.2
 slow.set_tire_friction(.35);slow.advance(.01)
 checks['grip_slider_reaches_wheel_contacts']=absf(slow.solver.wheels.friction_coefficient-.35)<.0001
 slow.reset()
 checks['repair_keeps_tuning']=slow.dynamics.parameters.power_w==110000 and absf(slow.dynamics.parameters.tire_friction-.35)<.0001
 checks['profile_defaults_are_not_rewritten']=slow.profile.dynamics.power_w==220000 and absf(slow.profile.dynamics.tire_friction-.65)<.0001
func _run() -> void:
 test_case(60,0)
 test_case(120,0)
 test_case(120,20)
 test_case(120,-20)
 test_case(120,90)
 test_case(120,180)
 checks['all_cases_completed']=runs.size()==6
 extra_checks()
 tuning_checks()
 checks['all_checks_executed']=checks.size()==80
 var passed: bool=checks.values().all(func(value):return value)
 FileAccess.open('res://verification/driving_bakes_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':runs},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('DRIVING_BAKES_VERIFIED ',passed)
 quit(0 if passed else 1)
