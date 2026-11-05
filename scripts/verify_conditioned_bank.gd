extends SceneTree
## Runs only after the current v3/material/effects conditioned bank is generated.
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Player=preload('res://scripts/baked_crash_player.gd')
const States=preload('res://scripts/conditioned_crash_transitions.gd')
const Author=preload('res://scripts/conditioned_crash_authoring.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Grid=preload('res://scripts/impact_zone_grid.gd')
var checks: Dictionary={}
var runs: Array=[]
var max_body_error:=0.0
var max_wheel_error:=0.0
var max_effect_pose_error:=0.0
var graph_id:=0
func _initialize() -> void:call_deferred('_run')

func write_report(passed: bool,reason: String='') -> void:
 FileAccess.open('res://verification/conditioned_bank_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'reason':reason,'checks':checks,'runs':runs,'max_body_sample_error_m':max_body_error,'max_wheel_rotation_spin_error':max_wheel_error,'max_effect_pose_error_m':max_effect_pose_error,'scope':'Real v3 conditioned family, shared graph/player/controllers. Fixture reorients/relaunches between hits; not arbitrary state coverage.'},'\t'))
func counter(object: RefCounted,name: String) -> int:
 if object==null:return -1
 for property in object.get_property_list():
  if str(property.name)==name:return int(object.get(name))
 return -1
func live_counts(effects: RefCounted) -> Array:
 return [counter(effects.glass,'membrane_solve_steps'),counter(effects.interior,'live_steps'),counter(effects.interior,'cloth_steps'),counter(effects.interior,'seat_steps')]
func effect_pose_error(actual: Variant,expected: Variant,context_key: String='') -> float:
 if 'veloc' in context_key or context_key.begins_with('previous'):return 0.0
 var error:=0.0
 if expected is Dictionary:
  if not actual is Dictionary:return INF
  for key in expected:
   if actual.has(key):error=maxf(error,effect_pose_error(actual[key],expected[key],str(key)))
   elif expected[key] is PackedVector3Array:return INF
 elif expected is Array:
  if not actual is Array or actual.size()!=expected.size():return INF
  for index in expected.size():error=maxf(error,effect_pose_error(actual[index],expected[index],context_key))
 elif expected is PackedVector3Array:
  if not actual is PackedVector3Array or actual.size()!=expected.size():return INF
  for index in expected.size():error=maxf(error,actual[index].distance_to(expected[index]))
 return error
func effects_monotonic(previous: Dictionary,current: Dictionary) -> bool:
 var a: Dictionary=previous.get('glass',{}).get('panes',{})
 var b: Dictionary=current.get('glass',{}).get('panes',{})
 for id in a:
  if not b.has(id):return false
  var old: Dictionary=a[id];var next: Dictionary=b[id]
  if int(next.get('stage',0))<int(old.get('stage',0)):return false
  if float(next.get('crack',0))+1e-6<float(old.get('crack',0)):return false
  for key in ['mask','broken','released']:
   var old_array: Variant=old.get(key,PackedByteArray())
   var next_array: Variant=next.get(key,PackedByteArray())
   if next_array.size()<old_array.size():return false
   for index in old_array.size():
    if key=='mask' and int(next_array[index])>int(old_array[index]):return false
    if key!='mask' and int(next_array[index])<int(old_array[index]):return false
  var ids: Dictionary={}
  for event in next.get('events',[]):ids[str(event.id)]=true
  for event in old.get('events',[]):
   if not ids.has(str(event.id)):return false
 var ia: Dictionary=previous.get('interior',{});var ib: Dictionary=current.get('interior',{})
 var old_seats: Array=ia.get('seats',[]);var new_seats: Array=ib.get('seats',[])
 if old_seats.size()!=new_seats.size():return false
 for index in old_seats.size():
  if float(new_seats[index].get('plastic_work',0))+1e-4<float(old_seats[index].get('plastic_work',0)):return false
 if ia.get('airbag',{}).get('triggered',false) and not ib.get('airbag',{}).get('triggered',false):return false
 return true

func _run() -> void:
 var directory: String=States.DIRECTORY
 var chain: String=Author.CHAIN_ID
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with('--directory='):directory=argument.trim_prefix('--directory=')
  if argument.begins_with('--chain='):chain=argument.trim_prefix('--chain=')
 var clips: Array=States.read_library(directory).filter(func(clip):return clip.metadata.get('conditioned',{}).get('chain_id','')==chain)
 clips.sort_custom(func(a,b):return int(a.metadata.conditioned.step)<int(b.metadata.conditioned.step))
 checks['three_current_transitions_present']=clips.size()==3
 if clips.size()!=3:
  write_report(false,'not_generated_yet_or_incomplete_conditioned_bank')
  push_error('Generate the rebuilt v3 conditioned bank first: '+directory)
  quit(1);return
 checks['v3_frames_have_real_effects']=clips.all(func(clip):return int(clip.metadata.get('version',0))>=3 and clip.frames.size()==301 and clip.frames.all(func(frame):return frame.has('effects') and frame.effects.get('version',0)==1))
 if not checks.v3_frames_have_real_effects:
  write_report(false,'legacy_or_missing_effects_frames');quit(1);return
 var vehicle=Vehicle.new();vehicle.setup('res://vehicles/niva.json',false)
 var graph: RefCounted=vehicle.solver;graph.config.enforce_symmetry=false;graph_id=graph.get_instance_id()
 var effects: RefCounted=States.effects_owner(graph)
 checks['real_effects_controllers_present']=effects!=null
 if effects==null:write_report(false,'effects_controllers_not_integrated');quit(1);return
 var first: Dictionary=clips[0]
 var first_origin:=Vector3(first.metadata.origin[0],first.metadata.origin[1],first.metadata.origin[2])
 effects.begin_playback(first.frames[0].effects)
 Clip.apply(graph,first,0,first_origin)
 var previous: Dictionary={}
 var global_fx_monotonic:=true
 var any_glass_damage:=false
 var any_seat_plastic:=false
 var any_deployed:=false
 for stage in 3:
  var clip: Dictionary=clips[stage]
  var label: String='stage_%d'%stage
  if stage>0:
   var before: Dictionary=States.capture(graph)
   Author.prepare(graph,{'speed':clip.metadata.speed_kmh,'angle':clip.metadata.heading_deg})
   var prepared: Dictionary=States.capture(graph)
   checks[label+'_fixture_preserves_lengths_failures_effects']=before.lengths==prepared.lengths and before.broken==prepared.broken and States.irreversible_effects(before.effects)==States.irreversible_effects(prepared.effects)
  checks[label+'_state_compatible']=States.compatible(graph,clip).accepted
  var signature: Dictionary=Grid.new().signature(graph,Vector3(float(clip.metadata.speed_kmh)/3.6,0,0))
  var selected: Dictionary=States.choose(graph,signature,clips)
  checks[label+'_actual_contact_selects_next']=selected.get('accepted',false) and selected.get('id','')==clip.metadata.id
  if not selected.get('accepted',false):
   runs.append({'stage':stage,'selection':selected,'compatibility':States.compatible(graph,clip)});continue
  var prior_free: PackedInt32Array=States.detached_wheel_indices(graph)
  var free_start: Dictionary={}
  for index in prior_free:free_start[index]={'point':graph.points[graph.wheels.wheels[index].node],'velocity':graph.velocities[graph.wheels.wheels[index].node]}
  var player:=Player.new();player.attach_live(vehicle,clips,signature,selected)
  var free_continuous:=true
  for index in prior_free:
   free_continuous=free_continuous and graph.points[graph.wheels.wheels[index].node].distance_to(free_start[index].point)<.00001 and graph.velocities[graph.wheels.wheels[index].node].distance_to(free_start[index].velocity)<.0001
  checks[label+'_contact_pose_velocity_continuous']=player.handoff_position_jump_m<.00001 and player.handoff_velocity_jump_mps<.0001 and free_continuous
  var counters: Array=live_counts(effects)
  checks[label+'_live_effect_counters_observable']=counters.all(func(value):return value>=0)
  var samples_finite:=true;var body_monotonic:=true;var wheel_flags:=true;var fx_exact:=true
  var source_error:=0.0;var orientation_error:=0.0
  for sample in 301:
   if sample>0:player.advance(1.0/120)
   var actual: Dictionary=States.capture(graph)
   var expected: Dictionary=clip.frames[sample]
   if sample>=12:
    for node in graph.points.size():
     if graph.wheels.by_node.has(node) and graph.wheels.by_node[node] in prior_free:continue
     var expected_point: Vector3=player.replay_rotation*expected.points[node]+player.origin
     source_error=maxf(source_error,graph.points[node].distance_to(expected_point))
   for node in graph.points.size():samples_finite=samples_finite and graph.points[node].is_finite() and graph.velocities[node].is_finite()
   for index in graph.wheels.wheels.size():
    wheel_flags=wheel_flags and (not expected.wheels[index].detached or graph.wheels.wheels[index].detached)
    if index not in prior_free:
     var target: Quaternion=(player.replay_rotation.get_rotation_quaternion()*expected.wheels[index].rotation).normalized()
     if sample>=12:
      orientation_error=maxf(orientation_error,1-absf(graph.wheels.wheels[index].rotation.dot(target)))
      var expected_spin: float=expected.wheels[index].spin+player.wheel_spin_offsets[index]
      orientation_error=maxf(orientation_error,absf(angle_difference(graph.wheels.wheels[index].spin,expected_spin)))
   max_effect_pose_error=maxf(max_effect_pose_error,effect_pose_error(actual.effects,expected.effects))
   fx_exact=fx_exact and States.irreversible_effects(actual.effects)==States.irreversible_effects(expected.effects)
   if not previous.is_empty():
    for node in graph.node_damage.size():body_monotonic=body_monotonic and actual.damage[node]+1e-6>=previous.damage[node]
    for index in graph.links.size():body_monotonic=body_monotonic and actual.broken[index]>=previous.broken[index] and actual.link_damage[index]+1e-6>=previous.link_damage[index]
    for index in graph.wheels.wheels.size():wheel_flags=wheel_flags and (not previous.wheels[index].detached or graph.wheels.wheels[index].detached)
    global_fx_monotonic=global_fx_monotonic and effects_monotonic(previous.effects,actual.effects)
   for pane in actual.effects.glass.get('panes',{}).values():any_glass_damage=any_glass_damage or int(pane.get('stage',0))>0
   for seat in actual.effects.interior.get('seats',[]):any_seat_plastic=any_seat_plastic or absf(float(seat.get('plastic_angle',0)))>.00001
   any_deployed=any_deployed or actual.effects.interior.get('airbag',{}).get('triggered',false)
   previous=actual
  max_body_error=maxf(max_body_error,source_error);max_wheel_error=maxf(max_wheel_error,orientation_error)
  checks[label+'_completed_without_full_or_live_effect_solve']=player.state=='COMPLETE' and graph.step_count==0 and live_counts(effects)==counters
  checks[label+'_same_1210kg_graph']=graph.get_instance_id()==graph_id and graph.points.size()==38 and absf(float(graph.config.mass_kg)-1210)<.01
  checks[label+'_authored_pose_and_wheels_match']=source_error<.0001 and orientation_error<.00001
  checks[label+'_body_damage_is_monotonic']=body_monotonic and wheel_flags
  checks[label+'_actual_effect_state_matches_saved_samples']=fx_exact
  checks[label+'_all_samples_finite']=samples_finite
  runs.append({'stage':stage,'clip':clip.metadata.id,'selection':selected,'prior_detached_indices':Array(prior_free),'body_sample_error_m':source_error,'wheel_rotation_error':orientation_error,'full_solver_steps':graph.step_count,'effect_solver_counters':live_counts(effects),'handoff_position_jump_m':player.handoff_position_jump_m,'handoff_velocity_jump_mps':player.handoff_velocity_jump_mps})
 checks['all_three_stages_executed']=runs.size()==3 and runs.all(func(run):return run.has('full_solver_steps'))
 checks['effects_damage_and_release_never_heal']=global_fx_monotonic
 checks['glass_actually_damaged_in_this_family']=any_glass_damage
 checks['seats_actually_yielded_in_this_family']=any_seat_plastic
 checks['enabled_airbag_actually_deployed']=not first.frames[0].effects.interior.get('airbag_enabled',false) or any_deployed
 checks['attachment_local_effect_poses_match']=max_effect_pose_error<.0001
 checks['expected_checks_executed']=checks.size()==41
 var passed: bool=checks.values().all(func(value):return value)
 write_report(passed)
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('CONDITIONED_BANK_VERIFIED ',passed,' checks=',checks.size(),' body_error=',max_body_error,' effect_pose_error=',max_effect_pose_error)
 quit(0 if passed else 1)
