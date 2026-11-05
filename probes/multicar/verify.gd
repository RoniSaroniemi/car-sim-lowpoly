extends SceneTree
const World=preload('res://probes/multicar/world.gd')
const Library=preload('res://probes/multicar/library.gd')
var checks: Dictionary={}
var results: Array=[]
var performance: Array=[]
func _initialize() -> void:call_deferred('_run')
func check(key: String,value: bool) -> void:
 checks[key]=value
 if not value:print('FAILED ',key)
func counters(car: RefCounted) -> Array:
 return [car.graph.step_count,car.graph.effects.glass.membrane_solve_steps,car.graph.effects.interior.live_steps,car.graph.effects.interior.cloth_steps]
func run_case(name_: String) -> RefCounted:
 var sim:=World.new();sim.record_enabled=false;sim.start(name_)
 var initial_mass: float=sim.cars.size()*1210
 var counts: Array=sim.cars.map(func(car):return counters(car))
 var identity: Array=sim.cars.map(func(car):return car.graph.get_instance_id())
 var initial_p: Vector3=sim.momentum();var initial_energy: float=sim.energy()
 var finite:=true;var monotone:=true;var previous: Array=[]
 for car in sim.cars:previous.append(car.graph.capture())
 var max_depth:=0.0
 for step in 420:
  sim.step()
  for i in sim.cars.size():
   var car=sim.cars[i];var state: Dictionary=car.graph.capture()
   for node in state.points.size():finite=finite and state.points[node].is_finite() and state.velocities[node].is_finite()
   for node in state.damage.size():monotone=monotone and state.damage[node]+1e-6>=previous[i].damage[node]
   for link in state.broken.size():monotone=monotone and state.broken[link]>=previous[i].broken[link]
   previous[i]=state
  for i in sim.cars.size():
   for j in range(i+1,sim.cars.size()):
    var contact: Dictionary=sim.manifold(sim.cars[i],sim.cars[j])
    if not contact.is_empty():max_depth=maxf(max_depth,contact.depth)
 check(name_+'_single_mass_owner',absf(float(sim.stats().mass_kg)-initial_mass)<.001 and sim.cars.all(func(car):return car.transient_mass_owner_count==1))
 check(name_+'_zero_full_or_cloth_steps',counts==sim.cars.map(func(car):return counters(car)))
 check(name_+'_same_graphs',identity==sim.cars.map(func(car):return car.graph.get_instance_id()))
 check(name_+'_finite',finite)
 check(name_+'_no_healing',monotone)
 check(name_+'_momentum_preserved',initial_p.distance_to(sim.momentum())<.1)
 check(name_+'_energy_does_not_grow',sim.energy()<=initial_energy+1)
 check(name_+'_bounded_overlap',max_depth<.06)
 check(name_+'_actual_contacts',sim.contacts_count>0)
 check(name_+'_impulses_conserve_P_and_L',sim.pair_impulses.all(func(item):return item.momentum_error_ns<.1 and item.angular_error_nms<.05 and item.energy_after_j<=item.energy_before_j+1))
 results.append({'case':name_,'stats':sim.stats(),'cars':sim.cars.map(func(car):return {'id':car.id,'clip':car.clip_id,'selection':car.last_selection,'plastic_work_j':car.graph.plastic_work}),'max_overlap_m':max_depth})
 return sim
func _run() -> void:
 var head:=run_case('head_on')
 check('headon_both_front60',head.cars.all(func(car):return car.clip_id=='impact_000_60'))
 check('headon_relative120_maps_each60',head.cars.all(func(car):return absf(car.last_selection.equivalent_wall_kmh-60)<.1))
 check('headon_stops_symmetrically',head.cars[0].velocity.distance_to(-head.cars[1].velocity)<.0001 and head.cars[0].velocity.length()<1)
 var parked:=run_case('parked')
 check('parked_both_receive_deformation',parked.cars.all(func(car):return car.played==1 and car.graph.plastic_work>0))
 check('parked_receives_momentum',parked.cars[1].velocity.x>16 and parked.cars[0].velocity.x>15)
 var triple:=run_case('triple')
 check('triple_two_contacts_one_batch',triple.contact_batches.size()==1 and triple.contact_batches[0].contacts.size()==2)
 check('triple_center_uses_authored_composite',triple.cars[0].clip_id=='opposed_front_rear_60' and triple.cars[0].played==1)
 check('triple_outer_front60',triple.cars[1].clip_id=='impact_000_60' and triple.cars[2].clip_id=='impact_000_60')
 check('triple_energy_not_double_assigned',absf(triple.cars.reduce(func(total,car):return total+float(car.last_selection.get('assigned_energy_j',0)),0.0)-float(triple.contact_batches[0].removed_energy_j))<.01)
 check('composite_contains_both_end_crush',triple.cars[0].graph.metrics().front_shortening_m>.05 and (triple.cars[0].graph.station_center(2)-triple.cars[0].graph.station_center(0)).length()<2.1)
 var again:=run_case('triple')
 check('simultaneous_repeat_is_deterministic',triple.cars.map(func(car):return [car.center,car.velocity,car.omega,car.clip_id])==again.cars.map(func(car):return [car.center,car.velocity,car.omega,car.clip_id]))
 var corner:=run_case('corner')
 check('partial_corner_explicit_fallback',corner.cars.all(func(car):return car.played==0 and car.last_selection.reason=='partial_or_oblique_not_authored'))
 var low:=run_case('low')
 check('low_energy_contact_does_not_bake',low.cars.all(func(car):return car.played==0 and car.last_selection.reason=='low_energy_no_bake'))
 # Swept broadphase, separate islands, root continuity and pristine overwrite guards.
 var probe:=World.new();probe.record_enabled=false;probe.start('head_on')
 check('far_pair_rejected',not probe.broadphase(probe.cars[0],probe.cars[1],probe.h))
 probe.cars[0].velocity=Vector3.LEFT*60;probe.cars[1].velocity=Vector3.RIGHT*60
 check('moving_away_sweep_rejected',not is_finite(probe.swept_time(probe.cars[0],probe.cars[1],probe.h)))
 check('disjoint_contacts_use_two_islands',probe.contact_islands([{'a':0,'b':1},{'a':2,'b':3}]).size()==2)
 check('connected_contacts_one_island',probe.contact_islands([{'a':0,'b':1},{'a':2,'b':1}]).size()==1)
 var car=probe.cars[0];var before: Dictionary=car.capture()
 car.begin_clip('impact_000_60',{'reason':'continuity_test'})
 var jump:=0.0
 for node in car.graph.points.size():jump=maxf(jump,car.graph.points[node].distance_to(before.graph.points[node]))
 check('deformation_handoff_root_and_pose_continuous',car.center.distance_to(before.center)<.00001 and car.yaw==before.yaw and car.velocity==before.velocity and jump<.00001)
 var physical_velocity: Vector3=car.velocity
 car.advance_shape(.5)
 check('wall_root_does_not_override_moving_car',car.velocity==physical_velocity and car.graph.step_count==0)
 check('later_pristine_clip_rejected',not car.begin_clip('impact_180_60',{'reason':'invalid_second'}))
 # Disk sample replay restores exact world roots/shape/irreversible state without solve.
 var recording:=World.new();recording.start('triple')
 for step in 360:recording.step()
 var file:=FileAccess.open_compressed('res://verification/multicar_roundtrip.bin',FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD);file.store_var(recording.recorded);file.close()
 var reader:=FileAccess.open_compressed('res://verification/multicar_roundtrip.bin',FileAccess.READ,FileAccess.COMPRESSION_ZSTD);var decoded: Array=reader.get_var(false);reader.close()
 var replay:=World.new();replay.record_enabled=false;replay.start('triple')
 var exact:=true;var fx_exact:=true
 for frame in decoded:
  replay.restore(frame)
  for i in replay.cars.size():
   exact=exact and replay.cars[i].center==frame.cars[i].center and replay.cars[i].velocity==frame.cars[i].velocity and replay.cars[i].graph.points==frame.cars[i].graph.points and replay.cars[i].graph.capture().broken==frame.cars[i].graph.broken
   fx_exact=fx_exact and replay.cars[i].graph.effects.glass.debris==frame.cars[i].glass_transient.debris and replay.cars[i].graph.effects.glass.emitted==frame.cars[i].glass_transient.emitted and replay.cars[i].graph.effects.capture()==frame.cars[i].graph.effects
 check('disk_replay_roots_shapes_flags_exact',exact)
 check('disk_replay_effects_and_transient_particles_exact',fx_exact)
 check('recording_contains_transient_particles',decoded.any(func(frame):return frame.cars.any(func(item):return not item.glass_transient.debris.is_empty())))
 check('disk_replay_zero_full_cloth_calls',replay.cars.all(func(item):return counters(item)==[0,0,0,0]))
 replay.start('triple')
 check('repair_clears_recorded_damage',replay.cars.all(func(item):return item.played==0 and item.graph.plastic_work==0 and item.clip_id==''))
 # Prove the existing source record remains current and local shape has zero weighted COM.
 var source: Dictionary=Library.clips['impact_000_60']
 check('source_physical_fingerprints_current',Library.Clip.input_compatibility(source).compatible)
 check('composite_fingerprints_current',Library.Clip.input_compatibility(Library.clips['opposed_front_rear_60']).exact)
 var driving:=World.new();driving.record_enabled=false;driving.start('drive')
 for step in 720:
  driving.cars[0].throttle=1 if driving.contact_batches.is_empty() else 0
  driving.step()
 check('player_accelerates_from_rest_into_car',not driving.contact_batches.is_empty())
 check('player_and_struck_car_play_bakes',driving.cars[0].played==1 and driving.cars[1].played==1)
 check('drivable_case_no_heavy_solves',driving.cars.all(func(item):return counters(item)==[0,0,0,0]))
 results.append({'case':'drive_from_rest','stats':driving.stats(),'cars':driving.cars.map(func(item):return {'id':item.id,'clip':item.clip_id,'selection':item.last_selection})})
 var sample: Dictionary=Library.frame('impact_000_60',.5);var com:=Vector3.ZERO
 for i in sample.points.size():com+=sample.points[i]*car.graph.masses[i]
 check('body_local_shape_cannot_move_mass_center',com.length()/1210<.00001)
 # Contact impulse supports unequal aggregate mass independently of render graph weights.
 var unequal:=World.new();unequal.record_enabled=false;unequal.start('parked')
 unequal.cars[0].mass*=2;unequal.cars[0].inertia*=2
 var unequal_p: Vector3=unequal.momentum();var unequal_energy: float=unequal.energy()
 for step in 420:unequal.step()
 check('unequal_mass_impulses_preserve_momentum',unequal.momentum().distance_to(unequal_p)<.1)
 check('unequal_mass_does_not_create_energy',unequal.energy()<=unequal_energy+1)
 check('unequal_mass_velocity_transfer',unequal.cars[1].velocity.x>22 and unequal.cars[0].velocity.x>21)
 check('unequal_mass_severity_uses_each_mass',unequal.cars[0].last_selection.equivalent_wall_kmh<unequal.cars[1].last_selection.equivalent_wall_kmh)
 var release_fixture:=World.new();release_fixture.start('head_on')
 # Synthetic channel fixture: reject before any ownership transfer or shape application.
 Library.clips['_test_free_wheel']=Library.clips['impact_000_60'].duplicate(true)
 Library.clips['_test_free_wheel'].frames[-1].wheels[0].detached=true
 check('detached_wheel_channel_explicitly_rejected',not release_fixture.cars[0].begin_clip('_test_free_wheel',{'reason':'release_guard'}) and release_fixture.cars[0].last_selection.reason=='detached_wheel_channel_needs_independent_owner')
 Library.clips.erase('_test_free_wheel')
 var passed: bool=checks.values().all(func(value):return value)
 var report: Dictionary={'passed':passed,'checks':checks,'cases':results,'scope':'Isolated planar condensed rigid roots with finite car contacts and body-local recorded deformation. Explicit composite fixture; no 3D suspension or arbitrary composite/history coverage.'}
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification/multicar'))
 FileAccess.open('res://verification/multicar/validation.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
 print('MULTICAR_VERIFIED ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
