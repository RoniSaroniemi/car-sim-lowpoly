extends SceneTree
const Terrain=preload('res://scripts/practice_terrain.gd')
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
var checks: Dictionary={}
var runs: Array=[]
var handoff: Dictionary={}
func _initialize() -> void:call_deferred('_run')

func make_vehicle(adaptive: bool,speed: float=0,start: Vector3=Vector3(-90,0,0)) -> RefCounted:
 var v=Vehicle.new()
 v.setup('res://vehicles/niva.json',true)
 v.solver.terrain=Terrain.new()
 v.adaptive_enabled=adaptive
 v.solver.barrier_min=Vector3(0,0,-8)
 v.solver.barrier_max=Vector3(1,3,8)
 v.reset(speed,start)
 return v

func _case(adaptive: bool,head_on: bool,trial: int) -> void:
 var v=make_vehicle(adaptive,80 if head_on else 0)
 v.solver.barrier_enabled=head_on
 v.set_controls(0 if head_on else 1,0,0)
 var seconds:=7.0 if head_on else 4.0
 var impact_speed: float=-1
 var samples: Array=[]
 var captured:=false
 var began: int=Time.get_ticks_usec()
 for frame in roundi(seconds*120):
  var speed_before: float=v.velocity().length()*3.6
  var had_impact: bool=v.solver.impact_started
  v.advance(1.0/120.0)
  if not had_impact and v.solver.impact_started:impact_speed=speed_before
  if head_on and adaptive and not captured and v.mode=='FULL':
   captured=true
   if handoff.is_empty():handoff={'state':v.solver.capture(),'link_overloads':v.solver.links.map(func(l):return l.overload_time)}
  if frame%12==0:
   samples.append({'time_s':v.solver.simulated_time,'mode':v.mode,'speed_kmh':v.velocity().length()*3.6,'body_x_m':v.solver.station_center(2).x,'plastic_work_kj':v.solver.plastic_work/1000.0,'full_steps':v.full_steps})
 var wall_ms: float=(Time.get_ticks_usec()-began)/1000.0
 var stats: Dictionary=v.statistics()
 stats['wall_ms']=wall_ms
 stats['scenario']='head_on' if head_on else 'clear_road'
 stats['adaptive']=adaptive
 stats['trial']=trial
 stats['impact_speed_kmh']=impact_speed
 stats['impact_time_s']=v.solver.impact_time
 stats['final_speed_kmh']=v.velocity().length()*3.6
 stats['final_body_x_m']=v.solver.station_center(2).x
 stats['damage']=v.solver.metrics()
 stats['samples']=samples
 stats['mass_kg']=v.solver.config.mass_kg
 var finite:=true
 for i in v.solver.points.size():finite=finite and v.solver.points[i].is_finite() and v.solver.velocities[i].is_finite()
 stats['finite']=finite
 if adaptive and head_on:
  var forecasted: Array=v.transitions.filter(func(t):return t.to=='FULL' and t.reason=='forecast_box')
  checks['head_on_wakes_from_forecast']=not forecasted.is_empty()
  if not forecasted.is_empty():
   stats['wake_time_s']=forecasted[0].time_s
   stats['wake_clearance_m']=forecasted[0].prediction.clearance_m
   stats['wake_lead_s']=v.solver.impact_time-forecasted[0].time_s
   checks['wake_precedes_contact']=stats.wake_lead_s>.05 and stats.wake_clearance_m>1.0
   checks['no_full_deformation_on_clear_approach']=v.transitions[0].reason=='forecast_box' and v.transitions[0].time_s>2.5
  checks['head_on_causes_live_deformation']=v.solver.plastic_work>1000 and v.full_steps>0
 if adaptive and not head_on:
  checks['clear_road_runs_zero_full_steps']=v.full_steps==0 and v.drive_steps>0
  checks['clear_road_drives_without_damage']=v.velocity().x>10 and v.solver.plastic_work==0
 checks['finite_'+str(head_on)+'_'+str(adaptive)+'_'+str(trial)]=finite
 checks['single_mass_'+str(head_on)+'_'+str(adaptive)+'_'+str(trial)]=absf(float(v.solver.config.mass_kg)-1210)<.01
 checks['continuous_handoff_'+str(head_on)+'_'+str(adaptive)+'_'+str(trial)]=v.handoff_max_position_error<.00001 and v.handoff_max_velocity_error<.00001
 runs.append(stats)
 print('ADAPTIVE_CASE ',stats.scenario,' adaptive=',adaptive,' trial=',trial,' wall_ms=',wall_ms,' sim_ms/s=',stats.cpu_ms_per_sim_second,' full_steps=',stats.full_steps,' impact=',impact_speed)

func _guards() -> void:
 var v=make_vehicle(true,80,Vector3(-5,0,0))
 var near: Dictionary=v.forecast.predict(v.solver,Vector3(80/3.6,0,0),Vector3.ZERO)
 checks['forward_prediction']=near.risk
 v.reset(-80,Vector3(6,0,0))
 checks['reverse_prediction']=v.forecast.predict(v.solver,Vector3(-80/3.6,0,0),Vector3.ZERO).risk
 v.solver.barrier_min=Vector3(-31,0,3)
 v.solver.barrier_max=Vector3(-29,3,4)
 v.reset(0,Vector3(-30,0,0))
 checks['sideways_prediction']=v.forecast.predict(v.solver,Vector3(0,0,15),Vector3.ZERO).risk
 v.solver.barrier_min=Vector3(-31,0,2)
 v.solver.barrier_max=Vector3(-29,3,3)
 checks['rotation_expands_bounds']=v.forecast.predict(v.solver,Vector3.ZERO,Vector3(0,3,0)).risk
 v.solver.barrier_min=Vector3(0,0,-8)
 v.solver.barrier_max=Vector3(1,3,8)
 v.reset(0,Vector3(-10,0,0))
 v.forecast.obstacle_velocity=Vector3(-80,0,0)
 checks['incoming_object_wakes_stationary_car']=v.forecast.predict(v.solver,Vector3.ZERO,Vector3.ZERO).risk
 v.forecast.obstacle_velocity=Vector3.ZERO
 v.solver.barrier_min=Vector3(0,0,6)
 v.solver.barrier_max=Vector3(1,3,8)
 v.reset(80,Vector3(-3,0,0))
 checks['near_miss_stays_cheap']=not v.forecast.predict(v.solver,Vector3(80/3.6,0,0),Vector3.ZERO).risk
 v.reset(0,Vector3(-30,3,0))
 checks['landing_prediction']=v.forecast.predict(v.solver,Vector3(0,-18,0),Vector3.ZERO).risk
 # Pure yaw and sideways speed must not masquerade as downward motion.
 var drifting=make_vehicle(true,60,Vector3(-40,0,0))
 drifting.solver.barrier_enabled=false
 checks['yaw_is_not_a_hard_landing']=not drifting.forecast.predict(drifting.solver,Vector3(12,0,7),Vector3(0,2,0)).risk
 for i in drifting.solver.velocities.size():drifting.solver.velocities[i]=Vector3(15,0,5)
 drifting.compact.capture_shape()
 for i in 120:drifting.advance(1.0/120.0)
 checks['ordinary_sideways_drift_stays_light']=drifting.full_steps==0 and drifting.mode=='DRIVE'
 # A forecast that clears without contact/damage is cancelled promptly.
 var miss=make_vehicle(true,60,Vector3(-4,0,0))
 miss.advance(1.0/120.0)
 var armed: bool=miss.mode=='FULL'
 miss.solver.barrier_enabled=false
 miss.set_controls(0,0,.15)
 for i in 72:miss.advance(1.0/120.0)
 checks['cleared_forecast_returns_to_light']=armed and miss.mode=='DRIVE' and miss.transitions.any(func(t):return t.reason=='forecast_cleared') and not miss.solver.impact_started
 checks['near_miss_full_time_is_bounded']=miss.full_seconds<.5
 # High forward kinetic energy alone must not hold the structural solver awake.
 var energy_test=make_vehicle(true,60,Vector3(-40,0,0))
 energy_test.solver.barrier_enabled=false
 energy_test.false_alarm_energy_j=0 # Isolate the energy exit from near-miss cancellation.
 energy_test.wake('energy_cutoff_test')
 for i in 240:energy_test.advance(1.0/120.0)
 checks['energy_gate_ignores_rigid_travel']=energy_test.mode=='DRIVE' and energy_test.solver.kinetic_energy()>10000 and energy_test.deformation_energy_j<energy_test.deformation_sleep_energy_j
 checks['energy_cutoff_is_profile_configured']=is_equal_approx(energy_test.deformation_sleep_energy_j,float(energy_test.profile.adaptive.deformation_sleep_energy_j))
 # New overlap must wake immediately even when the previous forecast was clear.
 v.reset(0,Vector3(-30,0,0))
 v.advance(1.0/120.0)
 v.solver.barrier_min=Vector3(-30,0,-2)
 v.solver.barrier_max=Vector3(-29,3,2)
 v.advance(1.0/120.0)
 checks['unexpected_overlap_wakes_full_solver']=v.full_steps>0
 # Explicit world/test loads wake before they change a compact body.
 var fixture=make_vehicle(true)
 fixture.wake('verification_external_force')
 fixture.advance(1.0/120.0)
 checks['explicit_force_wakes_full_solver']=fixture.full_steps>0 and fixture.transitions[0].reason=='verification_external_force'
 # A parked, settled car sleeps; throttle resumes cheap driving in clear space.
 var parked=make_vehicle(true)
 parked.solver.barrier_enabled=false
 for i in 600:parked.advance(1.0/120.0)
 checks['stationary_car_sleeps']=parked.sleep_steps>0
 parked.set_controls(.5,0,0)
 for i in 120:parked.advance(1.0/120.0)
 checks['sleep_wakes_on_input']=parked.mode=='DRIVE' and parked.velocity().x>.5

func _continuation() -> void:
 if handoff.is_empty():
  checks['matched_state_continuation']=false
  return
 var a=make_vehicle(false)
 var b=make_vehicle(true)
 b.wake('matched_state')
 for v in [a,b]:
  v.solver.restore(handoff.state)
  for i in v.solver.links.size():v.solver.links[i].overload_time=handoff.link_overloads[i]
 for i in 120:
  a.advance(1.0/120.0)
  b.advance(1.0/120.0)
 var error:=0.0
 for i in a.solver.points.size():error=maxf(error,a.solver.points[i].distance_to(b.solver.points[i]))
 checks['matched_state_continuation']=error<.00001 and absf(a.solver.plastic_work-b.solver.plastic_work)<.01
 print('MATCHED_STATE_MAX_ERROR_M ',error)

func _run() -> void:
 _guards()
 if '--guards-only' in OS.get_cmdline_user_args():
  var passed: bool=checks.values().all(func(v):return v)
  FileAccess.open('res://verification/adaptive_guard_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks},'	'))
  print('ADAPTIVE_GUARDS ',passed,' ',JSON.stringify(checks))
  quit(0 if passed else 1)
  return
 for trial in 2:
  for head_on in [false,true]:
   for adaptive in ([false,true] if trial==0 else [true,false]):_case(adaptive,head_on,trial)
 _continuation()
 for scenario in ['clear_road','head_on']:
  var baseline: Array=runs.filter(func(r):return r.scenario==scenario and not r.adaptive)
  var adaptive: Array=runs.filter(func(r):return r.scenario==scenario and r.adaptive)
  if scenario=='clear_road':
   checks['approach_speed_within_15_percent']=absf(baseline[0].final_speed_kmh-adaptive[0].final_speed_kmh)/baseline[0].final_speed_kmh<.15
   checks['clear_road_at_least_4x_less_work']=adaptive[0].cpu_ms_per_sim_second<baseline[0].cpu_ms_per_sim_second/4
  else:checks['impact_speed_within_10_percent']=absf(baseline[0].impact_speed_kmh-adaptive[0].impact_speed_kmh)/baseline[0].impact_speed_kmh<.10
 var passed: bool=checks.values().all(func(v):return v)
 var report: Dictionary={'passed':passed,'checks':checks,'runs':runs,'horizon_s':.18,'coarse_hz':120,'full_hz':480,'compact_iterations':3,'full_iterations':8,'scope':'Headless timed simulation code on this host; rendering excluded. Two serial trials, reversed order. Same mass/wheels/control code; compact body is an approximation. Moving-object guard tests prediction, not a general dynamic-world collision implementation.'}
 FileAccess.open('res://verification/adaptive_validation.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
 print('ADAPTIVE_VERIFICATION_COMPLETE ',passed,' ',JSON.stringify(checks))
 quit(0 if passed else 1)
