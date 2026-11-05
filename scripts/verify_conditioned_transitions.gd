extends SceneTree
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const States=preload('res://scripts/conditioned_crash_transitions.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Author=preload('res://scripts/conditioned_crash_authoring.gd')
var checks: Dictionary={}

func _initialize() -> void:call_deferred('_run')
func fixture_effects(clock: float=0,mask: int=3,plastic: float=.12) -> Dictionary:
 return {'version':1,'glass':{'profile':'test_laminate_v1','time_s':clock,'panes':[{'stage':2,'retained_mask':PackedByteArray([mask]),'tear_links':PackedInt32Array([7]),'event_ids':PackedInt32Array([12]),'points':PackedVector3Array([Vector3(clock,0,0)]),'nodes':PackedVector3Array([Vector3(clock,0,0)])}]},'interior':{'profile':'test_seat_v1','time_s':clock,'seats':[{'plastic_angle':plastic,'angle':clock,'omega':clock}],'event_time':clock,'airbag':{'deployed':true,'trigger_time':clock,'deployment':clock,'positions':PackedVector3Array([Vector3(clock,0,0)])}}}
func restore_body(graph: RefCounted,state: Dictionary) -> void:
 var snapshot: Dictionary=state.duplicate(true)
 var actual: Dictionary=States.capture(graph)
 if actual.has('effects'):snapshot.effects=actual.effects
 else:snapshot.erase('effects')
 graph.restore(snapshot)
func _run() -> void:
 var v=Vehicle.new();v.setup('res://vehicles/niva.json',false)
 var g: RefCounted=v.solver
 var first: Dictionary=Clip.read(Clip.case_path(0,60))
 checks['prefix_available']=not first.is_empty()
 checks['author_rejects_missing_prefix']=not Author.validate_prefix({}).accepted
 checks['author_rejects_legacy_prefix']=Author.validate_prefix(first).get('reason','')=='prefix_requires_version3' if int(first.get('metadata',{}).get('version',0))<3 else true
 if first.is_empty():quit(1);return
 var clip: Dictionary=first.duplicate(true)
 Clip.apply(g,clip,2.5,Vector3(clip.metadata.origin[0],clip.metadata.origin[1],clip.metadata.origin[2]))
 var state: Dictionary=States.capture(g)
 state['effects']=fixture_effects()
 # A unit fixture defines a transition starting from an existing damaged state.
 clip.frames[0]=state.duplicate(true);clip.frames[-1]=state.duplicate(true)
 clip.metadata.id='unit_transition';States.stamp(clip,state,g,'unit_chain',1)
 checks['exact_state_matches']=States.compatible(g,clip,state).accepted
 var moved: Dictionary=state.duplicate(true)
 var rotation:=Basis(Vector3.UP,.7)*Basis(Vector3.RIGHT,.1)
 for i in moved.points.size():moved.points[i]=rotation*moved.points[i]+Vector3(37,1,-9)
 checks['rigid_pose_invariance']=States.compatible(g,clip,moved).accepted
 var changed: Dictionary=state.duplicate(true);changed.points[24]+=Vector3(.15,0,0)
 checks['wrong_body_shape_rejected']=States.compatible(g,clip,changed).reason=='body_shape'
 changed=state.duplicate(true);changed.lengths[0]+=.03
 checks['wrong_plastic_lengths_rejected']=States.compatible(g,clip,changed).reason=='plastic_lengths'
 changed=state.duplicate(true);changed.damage[12]=minf(1,changed.damage[12]+.05)
 checks['wrong_irreversible_damage_rejected']=not States.compatible(g,clip,changed).accepted
 changed=state.duplicate(true);changed.broken[0]=1 if changed.broken[0]==0 else 0
 checks['wrong_broken_state_rejected']=States.compatible(g,clip,changed).reason=='broken_links'
 changed=state.duplicate(true);changed.wheels[0].detached=not changed.wheels[0].detached
 checks['wheel_attachment_mismatch_rejected']=States.compatible(g,clip,changed).reason=='wheel_attachment'
 changed=state.duplicate(true);changed.wheels[0].lateral_rest+=.01
 checks['permanent_wheel_offset_mismatch_rejected']=States.compatible(g,clip,changed).reason=='permanent_wheel_alignment'
 changed=state.duplicate(true);changed.effects=fixture_effects(123)
 checks['effects_clocks_and_motion_do_not_invalidate_state']=States.compatible(g,clip,changed).accepted
 changed=state.duplicate(true);changed.effects=fixture_effects(0,1)
 checks['glass_irreversible_mask_mismatch_rejected']=States.compatible(g,clip,changed).reason=='irreversible_effects'
 changed=state.duplicate(true);changed.effects=fixture_effects(0,3,.22)
 checks['seat_plasticity_mismatch_rejected']=States.compatible(g,clip,changed).reason=='irreversible_effects'
 var selection: Dictionary=States.choose(g,clip.metadata.signature,[clip],state)
 checks['fixture_lookup_exposes_supported_next_stage']=States.next_supported(g,[clip],state).get('step',-1)==1
 checks['empty_fixture_bank_returns_explicit_fallback']=not States.next_supported(g,[],state).accepted
 checks['state_and_impact_choose_transition']=selection.accepted and selection.index==0 and selection.conditioned_step==1
 var far_speed: Dictionary=clip.metadata.signature.duplicate(true)
 far_speed.closing_speed_mps*=2;far_speed.incident_impulse_proxy_ns*=2
 checks['unsupported_severity_is_not_forced_to_only_transition']=not States.choose(g,far_speed,[clip],state).accepted
 var opposite: Dictionary=clip.metadata.signature.duplicate(true);opposite.normal=[1,0,0]
 checks['wrong_impact_rejected_despite_matching_state']=not States.choose(g,opposite,[clip],state).accepted
 changed=state.duplicate(true);changed.effects=fixture_effects(0,1)
 checks['unknown_damage_state_has_explicit_fallback']=not States.choose(g,clip.metadata.signature,[clip],changed).accepted
 var other=Vehicle.new();other.setup('res://vehicles/niva.json',false)
 other.solver.links[0].yield_n*=.5
 checks['different_material_profile_rejected']=States.compatible(other.solver,clip,state).reason=='material_profile'
 var detached_state: Dictionary=state.duplicate(true)
 restore_body(g,state);g.wheels.detach(g.wheels.wheels[0],'test_prior_release')
 detached_state=States.capture(g);detached_state.effects=fixture_effects()
 var detached_clip: Dictionary=clip.duplicate(true);detached_clip.frames[0]=detached_state;detached_clip.frames[-1]=detached_state
 States.stamp(detached_clip,detached_state,g,'unit_chain',2)
 changed=detached_state.duplicate(true);changed.points[g.wheels.wheels[0].node]+=Vector3(50,20,10)
 checks['detached_world_position_does_not_block_state']=States.compatible(g,detached_clip,changed).accepted
 checks['detached_indices_report_original_mass_nodes']=States.detached_wheel_indices(g)==PackedInt32Array([0]) and States.detached_nodes(g)==PackedInt32Array([34])
 var old_position: Vector3=g.points[34];var old_velocity: Vector3=g.velocities[34]
 Author.prepare(g,{'speed':60.0,'angle':20.0})
 checks['relaunch_keeps_detached_world_pose_and_velocity']=g.points[34]==old_position and g.velocities[34]==old_velocity and g.wheels.wheels[0].detached
 restore_body(g,state)
 States.irreversible_floor(g,detached_state)
 checks['irreversible_floor_prevents_reattachment']=g.wheels.wheels[0].detached and g.wheels.wheels[0].links.all(func(link):return link.broken)
 States.save_library([clip],'res://verification/conditioned_unit_bank')
 var roundtrip: Array=States.read_library('res://verification/conditioned_unit_bank')
 checks['catalog_disk_roundtrip']=roundtrip.size()==1 and States.compatible(g,roundtrip[0],state).accepted
 checks['no_full_solver_evaluated']=g.step_count==0
 checks['all_checks_executed']=checks.size()==27
 var passed: bool=checks.values().all(func(value):return value)
 FileAccess.open('res://verification/conditioned_transition_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'selected':selection},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('CONDITIONED_TRANSITIONS_VERIFIED ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
