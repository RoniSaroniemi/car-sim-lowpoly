extends SceneTree
## Real driving owner, real contact sensor, current recorded effects and transitions.
const Vehicle=preload('res://scripts/driving_vehicle.gd')
const States=preload('res://scripts/conditioned_crash_transitions.gd')
const Player=preload('res://scripts/baked_crash_player.gd')
const Grid=preload('res://scripts/impact_zone_grid.gd')
var checks: Dictionary={}
var events: Array=[]
func _initialize() -> void:call_deferred('_run')
func effect_counts(car: RefCounted) -> Array:
 return [car.solver.effects.glass.membrane_solve_steps,car.solver.effects.interior.live_steps,car.solver.effects.interior.cloth_steps,car.solver.effects.interior.seat_steps]
func _run() -> void:
 var car:=Vehicle.new();car.setup()
 car.solver.barrier_min=Vector3(40,0,-8);car.solver.barrier_max=Vector3(41,3,8)
 var identity: int=car.solver.get_instance_id()
 checks['current_three_transition_bank']=car.conditioned_library.size()==3
 checks['sequence_starts']=car.start_baked_sequence()
 var previous_clock:=0.0;var previous_work:=0.0
 var monotonic:=true;var finite:=true;var damage_retained:=true
 var last_count:=0;var finished:=false
 var counters: Array=effect_counts(car)
 for step in 1800:
  car.set_controls(0,0,0,0);car.advance(1.0/120)
  monotonic=monotonic and car.solver.simulated_time+1e-8>=previous_clock
  previous_clock=car.solver.simulated_time
  damage_retained=damage_retained and car.solver.plastic_work+.01>=previous_work
  previous_work=car.solver.plastic_work
  for p in car.solver.points:finite=finite and p.is_finite()
  if car.baked_count!=last_count:
   events.append({'count':car.baked_count,'clock_s':car.solver.simulated_time,'clip':car.last_bake.duplicate(true),'work_j':previous_work})
   last_count=car.baked_count
  if not car.sequence_active:
   finished=car.baked_count==3 and car.last_bake.get('completed',false)
   break
 checks['three_contact_triggered_playbacks_complete']=finished
 checks['three_correct_clips']=events.size()==3 and events[0].clip.id=='impact_000_60' and events[1].clip.id=='front_60_60_120_step_1' and events[2].clip.id=='front_60_60_120_step_2'
 checks['same_graph_and_mass']=car.solver.get_instance_id()==identity and absf(float(car.solver.config.mass_kg)-1210)<.01
 checks['zero_full_structural_or_legacy_forecast']=car.full_steps==0 and car.solver.step_count==0 and car.forecast.checks==0
 checks['zero_live_glass_seat_airbag_solves']=effect_counts(car)==counters
 checks['clock_monotonic']=monotonic
 checks['plastic_work_never_decreases']=damage_retained
 checks['finite_poses']=finite
 checks['handoffs_continuous']=events.size()==3 and events.all(func(event):return event.clip.handoff_position_jump_m<.00001 and event.clip.handoff_velocity_jump_mps<.0001)
 checks['damaged_car_returns_to_lightweight']=car.mode=='DRIVE' and car.solver.plastic_work>200000
 var old_damage: float=car.solver.plastic_work
 for step in 120:car.advance(1.0/120)
 checks['post_sequence_driving_without_solver']=car.full_steps==0 and effect_counts(car)==counters and car.solver.plastic_work+.01>=old_damage
 # Independently stop after the first clip, then allow normal coarse settling.
 car.reset_wall_approach(60)
 for step in 700:
  car.advance(1.0/120)
  if car.last_bake.get('completed',false):break
 checks['successor_available_immediately']=States.next_supported(car.solver,car.conditioned_library).accepted
 for step in 120:car.advance(1.0/120)
 var settled: Dictionary=States.next_supported(car.solver,car.conditioned_library)
 checks['successor_available_after_one_second']=settled.accepted
 checks['staging_retains_damage']=car.stage_next_supported() and car.solver.plastic_work>0 and car.baked_count==1
 # Stress the player ownership boundary independently of state selection.
 # An old released wheel must never follow the next clip's recorded world path.
 car.reset_wall_approach(60)
 var wheel=car.solver.wheels.wheels[0];car.solver.wheels.detach(wheel,'ownership_test')
 car.solver.points[wheel.node]=Vector3(-20,5,25);car.solver.velocities[wheel.node]=Vector3(2,0,1)
 var free_position: Vector3=car.solver.points[wheel.node]
 var signature: Dictionary=car.bake_library.filter(func(clip):return clip.metadata.id=='impact_000_60')[0].metadata.signature
 var index: int=car.bake_library.find_custom(func(clip):return clip.metadata.id=='impact_000_60')
 var player:=Player.new();player.attach_live(car,car.bake_library,signature,{'accepted':true,'index':index})
 checks['old_free_wheel_handoff_stays_world_owned']=car.solver.points[wheel.node].distance_to(free_position)<.00001 and wheel.detached
 for step in 30:player.advance(1.0/120)
 var expected: Vector3=free_position+Vector3(.5,-.5*9.81*.25*.25,.25)
 checks['old_free_wheel_continues_ballistic_motion']=car.solver.points[wheel.node].distance_to(expected)<.02 and wheel.detached
 car.solver.points[wheel.node]=Vector3(40,1,100)
 car.solver.velocities[wheel.node]=Vector3(50,0,0)
 var clock_before: float=car.solver.simulated_time
 # Move attached probes to imminent ordinary full-wall contact.
 var leading: float=-INF
 for node in car.solver.points.size():
  if node!=wheel.node:leading=maxf(leading,car.solver.points[node].x+car.solver.radii[node])
 var shift: float=40-leading-.001
 for node in car.solver.points.size():
  if node!=wheel.node:
   car.solver.points[node].x+=shift;car.solver.velocities[node]=Vector3(60.0/3.6,0,0)
 car.compact.capture_shape();car.solver.compact_active=true
 var packet: Dictionary=car.contact_sensor.event(car.solver,Vector3(60.0/3.6,0,0),1.0/120)
 checks['old_free_wheel_excluded_from_contact_bounds']=not packet.is_empty() and packet.bounds_max.z<8 and not packet.signature.get('hit_nodes',[]).has(wheel.node) and car.solver.simulated_time==clock_before
 var passed: bool=checks.values().all(func(value):return value)
 FileAccess.open('res://verification/sandbox_sequence_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'events':events,'settled_successor':settled,'notice':car.sequence_notice,'stats':car.statistics()},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('SANDBOX_SEQUENCE_VERIFIED ',passed,' checks=',checks.size(),' impacts=',events.size(),' notice=',car.sequence_notice)
 quit(0 if passed else 1)
