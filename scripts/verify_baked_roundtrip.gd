extends SceneTree
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Player=preload('res://scripts/baked_crash_player.gd')
const Recorder=preload('res://scripts/crash_bake_recorder.gd')
const Zones=preload('res://scripts/impact_zone_grid.gd')
var checks: Dictionary={}
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var data: Dictionary=Clip.read()
 if data.is_empty():
  push_error('Bake the clip first');quit(1);return
 checks['301_frames']=data.frames.size()==301
 checks['structure_matches']=data.metadata.structure_sha256==FileAccess.get_sha256('res://structure.json')
 checks['wheel_solver_matches']=data.metadata.wheel_solver_sha256==FileAccess.get_sha256('res://scripts/wheel_physics.gd')
 var provenance_matches: bool=data.metadata.has('input_sha256')
 for path in data.metadata.get('input_sha256',{}):
  provenance_matches=provenance_matches and data.metadata.input_sha256[path]==FileAccess.get_sha256('res://'+path)
 checks['all_recorded_inputs_match']=provenance_matches
 var player:=Player.new();player.setup(data)
 for i in 500:
  player.advance(1.0/120)
  if player.state in ['COMPLETE','REJECTED']:break
 checks['collision_triggered_replay']=player.state=='COMPLETE' and player.match_result.get('accepted',false)
 checks['exact_zone_match']=player.match_result.get('zone_overlap',0)>.99999
 checks['nonempty_impact_history']=not data.metadata.zone_contact_history.is_empty()
 checks['no_structural_solver_steps']=player.vehicle.solver.step_count==0
 checks['continuous_contact_handoff']=player.handoff_position_jump_m<.0001
 var playback_ms: float=player.player_cpu_us/1000.0
 var origin:=Vector3(data.metadata.origin[0],data.metadata.origin[1],data.metadata.origin[2])
 var max_position_error:=0.0;var max_damage_error:=0.0;var max_rotation_error:=0.0
 var max_spin_error:=0.0;var discrete_states_equal:=true
 for index in data.frames.size():
  Clip.apply(player.vehicle.solver,data,float(index)/120.0,origin)
  var actual: Dictionary=player.vehicle.solver.capture()
  var expected: Dictionary=data.frames[index]
  for i in actual.points.size():
   max_position_error=maxf(max_position_error,actual.points[i].distance_to(expected.points[i]+origin))
   max_damage_error=maxf(max_damage_error,absf(actual.damage[i]-expected.damage[i]))
  for i in actual.wheels.size():
   max_rotation_error=maxf(max_rotation_error,1-absf(actual.wheels[i].rotation.dot(expected.wheels[i].rotation)))
   max_spin_error=maxf(max_spin_error,absf(angle_difference(actual.wheels[i].spin,expected.wheels[i].spin)))
   discrete_states_equal=discrete_states_equal and actual.wheels[i].detached==expected.wheels[i].detached
  discrete_states_equal=discrete_states_equal and actual.broken==expected.broken and actual.lengths==expected.lengths
 checks['all_authored_positions_match']=max_position_error<.00001
 checks['all_authored_damage_matches']=max_damage_error<.00001
 checks['wheel_orientation_and_spin_match']=max_rotation_error<.00001 and max_spin_error<.00001
 checks['broken_links_lengths_and_wheel_release_match']=discrete_states_equal
 # Between samples the pose must interpolate, not invoke dynamics.
 Clip.apply(player.vehicle.solver,data,.5/120,origin)
 var midpoint_error:=0.0
 for i in player.vehicle.solver.points.size():
  var expected: Vector3=data.frames[0].points[i].lerp(data.frames[1].points[i],.5)+origin
  midpoint_error=maxf(midpoint_error,expected.distance_to(player.vehicle.solver.points[i]))
 checks['subframe_interpolation_matches']=midpoint_error<.00001
 checks['scrubbing_uses_no_solver_steps']=player.vehicle.solver.step_count==0
 var zones:=Zones.new()
 var wrong: Dictionary=data.metadata.signature.duplicate(true)
 wrong.zones=[{'id':0,'weight':1.0}]
 checks['different_zone_rejected']=not zones.match_signature(wrong,data.metadata.signature).accepted
 wrong=data.metadata.signature.duplicate(true);wrong.normal=[1,0,0]
 checks['opposite_direction_rejected']=not zones.match_signature(wrong,data.metadata.signature).accepted
 wrong=data.metadata.signature.duplicate(true);wrong.incident_impulse_proxy_ns*=.5
 checks['different_severity_rejected']=not zones.match_signature(wrong,data.metadata.signature).accepted
 var slow:=Player.new();slow.setup(data);slow.incoming_velocity*=.5
 for i in 150:slow.advance(1.0/120)
 checks['actual_low_speed_approach_rejected']=slow.state=='REJECTED' and slow.vehicle.solver.step_count==0
 # Re-run the live solver independently to validate the actual bake round trip.
 var live:=Recorder.new();live.start()
 while not live.completed:live.step()
 # Verify a local disk round trip; do not demand bit-identical live physics
 # between the published macOS bake and another platform's floating-point solver.
 Clip.save(live.result,'res://verification/roundtrip_live.crashclip')
 var local_data: Dictionary=Clip.read('res://verification/roundtrip_live.crashclip')
 var live_error:=0.0;var live_damage_error:=0.0
 checks['live_reference_frame_count']=local_data.frames.size()==live.frames.size()
 if local_data.frames.size()==live.frames.size():
  for f in local_data.frames.size():
   for i in local_data.frames[f].points.size():
    live_error=maxf(live_error,live.frames[f].points[i].distance_to(local_data.frames[f].points[i]))
    live_damage_error=maxf(live_damage_error,absf(live.frames[f].damage[i]-local_data.frames[f].damage[i]))
 var local_player:=Player.new();local_player.setup(local_data)
 for i in 500:local_player.advance(1.0/120)
 checks['fresh_live_disk_roundtrip_matches']=live_error<.00001 and live_damage_error<.00001 and local_player.state=='COMPLETE' and local_player.vehicle.solver.step_count==0
 var passed: bool=checks.values().all(func(c):return c)
 var report: Dictionary={'passed':passed,'checks':checks,'frames':data.frames.size(),'fresh_live_max_position_error_m':live_error,'fresh_live_max_damage_error':live_damage_error,'clip_bytes':FileAccess.get_file_as_bytes(Clip.PATH).size(),'match':player.match_result,'full_solver_steps_recording':data.metadata.full_solver_steps,'full_solver_steps_playback':player.vehicle.solver.step_count,'handoff_jump_m':player.handoff_position_jump_m,'max_sample_position_error_m':max_position_error,'max_sample_damage_error':max_damage_error,'max_wheel_rotation_dot_error':max_rotation_error,'max_wheel_spin_error_rad':max_spin_error,'record_cpu_ms':data.metadata.record_cpu_ms,'playback_cpu_ms':playback_ms,'scope':'One controlled fixed-heading frontal case; timings exclude rendering, skin updates and setup. Zone impulses/energies are incident proxies.'}
 FileAccess.open('res://verification/baked_roundtrip_validation.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
 print('BAKED_ROUNDTRIP ',JSON.stringify(report))
 quit(0 if passed else 1)
