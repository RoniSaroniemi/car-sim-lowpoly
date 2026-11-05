extends SceneTree
const Graph=preload('res://scripts/structure_solver.gd')
const Glass=preload('res://scripts/vehicle_glass.gd')
const Attachment=preload('res://scripts/car_attachment.gd')
var checks: Dictionary={}
var observed: Dictionary={}
var sections:=0
func _initialize() -> void:call_deferred('_run')
func graph_new() -> RefCounted:
 var graph:=Graph.new();graph.setup();graph.reset(0,Vector3.ZERO);graph.barrier_enabled=false
 return graph
func controller(graph: RefCounted) -> RefCounted:
 var glass:=Glass.new();glass.setup(graph);return glass
func advance(glass: RefCounted,count: int) -> void:
 for i in count:glass.step_live(1.0/120);glass.step_debris(1.0/120)
func max_pose_error(a: PackedVector3Array,b: PackedVector3Array) -> float:
 if a.size()!=b.size():return INF
 var error:=0.0
 for i in a.size():error=maxf(error,a[i].distance_to(b[i]))
 return error
func boundary_error(glass: RefCounted) -> float:
 var frames: Array=Attachment.rotations(glass.graph.get_ref());var error:=0.0
 for pane in glass.panes.values():
  if pane.membrane==null:continue
  var targets: PackedVector3Array=glass._node_world(pane,frames)
  for i in targets.size():
   if pane.membrane.anchored[i]:error=maxf(error,targets[i].distance_to(pane.membrane.points[i]))
 return error
func configuration_checks() -> void:
 var graph:=graph_new();var glass:=controller(graph)
 checks['six_actual_panes']=glass.panes.size()==6
 checks['one_laminate_five_tempered']=glass.panes.values().filter(func(p):return p.raw.material=='laminated').size()==1
 var uv_ok:=true
 for p in glass.profile.panes:
  for uv in p.uv:uv_ok=uv_ok and uv[0]>=-.00001 and uv[0]<=1.00001 and uv[1]>=-.00001 and uv[1]<=1.00001
 checks['dedicated_pane_uvs_in_bounds']=uv_ok
 var rotation:=Basis(Vector3.UP,1.2);var offset:=Vector3(9,2,-6)
 for i in graph.points.size():graph.points[i]=rotation*graph.rest[i]+offset
 glass.synchronize();advance(glass,12)
 checks['rigid_teleport_does_not_break_glass']=glass.panes.values().all(func(p):return p.stage==0) and glass.membrane_solve_steps==0
 checks['pure_attachment_mapping']=Attachment.point(graph,Vector3(.4,1.5,.2)).distance_to(rotation*Vector3(.4,1.5,.2)+offset)<.00001
 checks['all_sources_fingerprinted']=glass.input_fingerprints().size()>=7
 sections+=1
func live_and_replay_checks() -> void:
 var graph:=graph_new();var glass:=controller(graph)
 var original: PackedVector3Array=graph.points.duplicate();var original_v: PackedVector3Array=graph.velocities.duplicate()
 glass.hit_window('windscreen',2,true)
 var frames: Array=[glass.capture()]
 for i in 180:glass.step_live(1.0/120);glass.step_debris(1.0/120);frames.append(glass.capture())
 var wind: Dictionary=glass.capture().panes.windscreen
 checks['live_laminate_has_117_nodes']=wind.nodes.size()==117 and glass.membrane_solve_steps==180
 checks['localized_puncture_tears_bonds']=Array(wind.broken).count(1)>0 and Array(wind.mask).count(0)>0
 checks['permanent_frame_mounts']=boundary_error(glass)<.00001
 checks['glass_does_not_move_car_mass']=graph.points==original and graph.velocities==original_v and graph.config.mass_kg==1210
 var playback:=controller(graph);playback.begin_playback(frames[0])
 var error:=0.0;var topology:=true
 for state in frames:
  playback.restore_interpolated(state,state,0)
  var actual: Dictionary=playback.capture().panes.windscreen
  error=maxf(error,max_pose_error(actual.nodes,state.panes.windscreen.nodes))
  topology=topology and actual.broken==state.panes.windscreen.broken and actual.mask==state.panes.windscreen.mask
 checks['recorded_glass_nodes_match']=error<.00001
 checks['recorded_glass_topology_matches']=topology
 checks['baked_glass_never_solves_membrane']=playback.membrane_solve_steps==0
 var before: Dictionary=playback.capture().panes.windscreen
 playback.resume_live()
 var pane: Dictionary=playback.panes.windscreen
 var transforms: Array=Attachment.rotations(graph);var transform: Transform3D=playback._frame(pane,transforms)
 var local:=PackedVector3Array()
 for point in pane.membrane.points:local.append(transform.affine_inverse()*point)
 checks['resume_recreates_retained_sheet_pose']=max_pose_error(local,before.nodes)<.00001
 checks['resume_keeps_broken_bonds']=pane.membrane.bonds.map(func(b):return 1 if b.broken else 0)==Array(before.broken)
 playback.step_live(1.0/120)
 checks['resume_advances_membrane_without_healing']=playback.membrane_solve_steps>0 and playback.panes.windscreen.stage>=before.stage
 observed['roundtrip_max_node_error_m']=error;observed['frame_mount_error_m']=boundary_error(glass)
 sections+=1
func event_and_collision_checks() -> void:
 var graph:=graph_new();var glass:=controller(graph)
 glass.step_live(1.0/120);var intact: Dictionary=glass.capture()
 glass.hit_window('door_left',1.3);var broken: Dictionary=glass.capture()
 checks['tempered_release_is_bounded']=glass.debris.size()>0 and glass.debris.size()<=Glass.DEBRIS_CAP
 var in_flight: int=glass.debris.size()
 glass.begin_playback(broken)
 checks['conditioned_begin_preserves_debris']=glass.debris.size()==in_flight
 glass.restore_interpolated(broken,broken,0)
 checks['conditioned_begin_does_not_reemit_old_event']=glass.debris.size()==in_flight
 glass.reset();glass.begin_playback(intact);glass.restore_interpolated(broken,broken,0)
 var count: int=glass.debris.size()
 glass.restore_interpolated(broken,broken,0)
 checks['forward_release_emits_once']=count>0 and glass.debris.size()==count
 glass.restore_interpolated(intact,intact,0)
 checks['backward_seek_clears_transients']=glass.debris.is_empty()
 glass.restore_interpolated(broken,broken,0)
 checks['forward_after_seek_emits_once']=glass.debris.size()==count
 for i in 480:glass.step_debris(1.0/120)
 checks['debris_expires_with_floor_collision']=glass.debris.is_empty() and glass.collision_count>0
 graph.barrier_enabled=true;graph.barrier_min=Vector3(0,0,-1);graph.barrier_max=Vector3(.02,3,1)
 glass.debris=[{'position':Vector3(-.5,1,0),'velocity':Vector3(180,0,0),'rotation':Vector3.ZERO,'spin':Vector3.ZERO,'size':.01,'life':2.0}]
 glass.step_debris(1.0/120)
 checks['fast_debris_cannot_tunnel_thin_box']=glass.debris[0].position.x<0 and glass.debris[0].velocity.x<0
 glass.reset();checks['repair_clears_debris_and_damage']=glass.debris.is_empty() and glass.panes.values().all(func(p):return p.stage==0)
 sections+=1
func galilean_checks() -> void:
 var a_graph:=graph_new();var b_graph:=graph_new();var speed:=Vector3(17,0,0)
 for i in b_graph.velocities.size():b_graph.velocities[i]=speed
 var a:=controller(a_graph);var b:=controller(b_graph)
 a.hit_window('windscreen',1.65,true);b.hit_window('windscreen',1.65,true)
 var max_error:=0.0
 for step in 90:
  for i in b_graph.points.size():b_graph.points[i]+=speed/120
  a.step_live(1.0/120);b.step_live(1.0/120)
  max_error=maxf(max_error,max_pose_error(a.capture().panes.windscreen.nodes,b.capture().panes.windscreen.nodes))
 var state_a: Dictionary=a.capture().panes.windscreen;var state_b: Dictionary=b.capture().panes.windscreen
 checks['uniform_car_velocity_preserves_cloth_deformation']=max_error<.002
 checks['uniform_car_velocity_preserves_tears']=state_a.broken==state_b.broken
 var before: Dictionary=b.capture().panes.windscreen
 var rotation:=Basis(Vector3.UP,.8);var shift:=Vector3(-25,0,10);var relaunched:=Vector3(30,0,-8)
 for i in b_graph.points.size():b_graph.points[i]=rotation*b_graph.points[i]+shift;b_graph.velocities[i]=relaunched
 b.synchronize()
 var pane: Dictionary=b.panes.windscreen;var transform: Transform3D=b._frame(pane,Attachment.rotations(b_graph));var positions:=PackedVector3Array();var relative:=PackedVector3Array();var mounts: PackedVector3Array=b._mount_velocities(pane)
 for i in pane.membrane.points.size():positions.append(transform.affine_inverse()*pane.membrane.points[i]);relative.append(transform.basis.inverse()*(pane.membrane.velocity[i]-mounts[i]))
 checks['relaunch_preserves_attachment_local_pose']=max_pose_error(positions,before.nodes)<.0001
 checks['relaunch_preserves_relative_cloth_velocity']=max_pose_error(relative,before.velocities)<.001
 checks['relaunch_does_not_heal_tears']=pane.membrane.bonds.map(func(bond):return 1 if bond.broken else 0)==Array(before.broken)
 observed['uniform_velocity_max_pose_error_m']=max_error;observed['relaunch_pose_error_m']=max_pose_error(positions,before.nodes);observed['relaunch_relative_velocity_error_mps']=max_pose_error(relative,before.velocities)
 sections+=1
func retention_checks() -> void:
 var graph:=graph_new();var glass:=controller(graph)
 glass.hit_window('windscreen',1.8,false);advance(glass,120)
 var wind: Dictionary=glass.capture().panes.windscreen
 checks['strong_blunt_laminate_retains_sheet']=Array(wind.mask).count(0)==0 and Array(wind.released).count(1)==0
 checks['strong_blunt_laminate_keeps_frame']=boundary_error(glass)<.00001
 observed['laminate_pinned_nodes']=Array(glass.panes.windscreen.membrane.anchored).count(1)
 glass.reset();glass.hit_window('door_left',.5)
 checks['modest_tempered_hit_does_not_empty_pane']=Array(glass.panes.door_left.mask).count(0)==0 and glass.debris.is_empty()
 glass.hit_window('door_left',1.3)
 checks['high_tempered_hit_fragments_with_remnants']=Array(glass.panes.door_left.mask).count(0)>350 and Array(glass.panes.door_left.mask).count(1)>0

 sections+=1
func resumed_release_checks() -> void:
 var graph:=graph_new();var glass:=controller(graph)
 glass.hit_window('windscreen',.6,false);advance(glass,12)
 var m: RefCounted=glass.panes.windscreen.membrane
 var center: int=4*(MembraneNX()+1)+6
 for index in m.adjacency[center]:m.bonds[index].broken=true
 advance(glass,8)
 var state: Dictionary=glass.capture()
 checks['released_patch_snapshot_has_event']=state.panes.windscreen.events.size()==1
 glass.begin_playback(state);glass.resume_live()
 m=glass.panes.windscreen.membrane
 for index in m.adjacency[center+1]:m.bonds[index].broken=true
 advance(glass,8)
 var events: Array=glass.capture().panes.windscreen.events
 checks['resumed_patch_event_ids_remain_unique']=events.size()==2 and events[0].id!=events[1].id and glass.emitted.size()==2
 sections+=1
func MembraneNX() -> int:return 12
func crash_authoring_checks() -> void:
 var graph:=graph_new();graph.barrier_enabled=true;graph.reset(120,Vector3(-9,0,0));var glass:=controller(graph)
 var max_boundary:=0.0
 for i in 960:
  graph.step(1.0/480);glass.step_live(1.0/480)
  if glass.live_accumulator<1e-8:max_boundary=maxf(max_boundary,boundary_error(glass))
 var wind: Dictionary=glass.capture().panes.windscreen
 checks['frontal_authoring_cracks_laminate']=wind.stage>=1
 checks['frontal_authoring_keeps_laminate_mounts']=max_boundary<.0001
 checks['frontal_authoring_retains_most_laminate']=Array(wind.mask).count(0)<wind.mask.size()*.3
 observed['frontal_peak_pulse_mps']=glass.peak_laminate_pulse;observed['frontal_stage']=wind.stage;observed['frontal_open_cells']=Array(wind.mask).count(0);observed['frontal_boundary_error_m']=max_boundary
 sections+=1
func debris_velocity_checks() -> void:
 var worst_mean:=0.0;var replay_error:=0.0
 for direction in [-1,1]:
  var g:=graph_new();var speed:=Vector3(30*direction,0,0)
  for i in g.velocities.size():g.velocities[i]=speed
  var fx:=controller(g);var intact: Dictionary=fx.capture()
  fx.hit_window('door_left',1.3);var state: Dictionary=fx.capture();var live: Array=fx.debris.duplicate(true)
  var mean:=Vector3.ZERO
  for shard in live:mean+=shard.velocity
  mean/=live.size();worst_mean=maxf(worst_mean,mean.distance_to(speed))
  checks['debris_inherits_%sX_motion'%('positive_' if direction>0 else 'negative_')]=mean.dot(speed.normalized())>29
  fx.reset();fx.begin_playback(intact);fx.restore_interpolated(state,state,0)
  for i in live.size():replay_error=maxf(replay_error,live[i].velocity.distance_to(fx.debris[i].velocity))
  # Rebase the same event onto a vehicle going in the opposite direction.
  for i in g.velocities.size():g.velocities[i]=-speed
  fx.reset();fx.begin_playback(intact);fx.restore_interpolated(state,state,0)
  mean=Vector3.ZERO
  for shard in fx.debris:mean+=shard.velocity
  mean/=fx.debris.size()
  checks['baked_debris_rebases_%sX_motion'%('negative_' if direction>0 else 'positive_')]=mean.dot((-speed).normalized())>29
 checks['live_and_baked_release_velocity_identical']=replay_error<.0001
 var g:=graph_new()
 for i in g.velocities.size():g.velocities[i]=Vector3(33,0,0)
 var fx:=controller(g)
 for i in g.velocities.size():g.velocities[i]=Vector3.ZERO
 fx.hit_window('door_left',1.3)
 var mean:=Vector3.ZERO
 for shard in fx.debris:mean+=shard.velocity
 mean/=fx.debris.size()
 checks['brake_impact_retains_precontact_pane_velocity']=mean.x>32
 g.barrier_enabled=true;g.barrier_min=Vector3(0,0,-1);g.barrier_max=Vector3(.02,3,1)
 fx.debris=[{'position':Vector3(.01,1,0),'velocity':Vector3(33,0,0),'rotation':Vector3.ZERO,'spin':Vector3.ZERO,'size':.01,'life':2.0}]
 fx.step_debris(1.0/120)
 checks['born_inside_barrier_exits_without_false_reversal']=fx.debris[0].velocity.x>32 and fx.debris[0].position.x>.02
 g.barrier_enabled=false
 fx.debris=[{'position':Vector3(-.5,1.3,0),'velocity':Vector3(8,0,0),'rotation':Vector3.ZERO,'spin':Vector3.ZERO,'size':.01,'life':2.0}]
 for i in 12:fx.step_debris(1.0/120)
 checks['debris_can_cross_cabin_without_body_aabb']=fx.debris[0].velocity.x>7.9 and fx.debris[0].position.x>.29
 observed['release_mean_inheritance_error_mps']=worst_mean;observed['live_baked_release_velocity_error_mps']=replay_error
 sections+=1
func _run() -> void:
 configuration_checks();live_and_replay_checks();event_and_collision_checks();galilean_checks();retention_checks();resumed_release_checks();crash_authoring_checks();debris_velocity_checks()
 checks['all_test_sections_completed']=sections==8
 checks['expected_check_count']=checks.size()==48
 var passed: bool=checks.values().all(func(v):return v)
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 var result: Dictionary={'passed':passed,'checks':checks,'observed':observed,'scope':'Production six-pane controller, mounted-sheet and irreversible state lifecycle. Cosmetic debris; no added graph mass.'}
 FileAccess.open('res://verification/vehicle_glass_validation.json',FileAccess.WRITE).store_string(JSON.stringify(result,'\t'))
 print('VEHICLE_GLASS_VERIFIED ',JSON.stringify(result));quit(0 if passed else 1)
