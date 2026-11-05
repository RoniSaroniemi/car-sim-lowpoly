extends SceneTree
const Drive=preload('res://probes/panels/drive_runtime.gd')
const HeadOn=preload('res://probes/panels/headon_fixtures.gd')
const Fixture=preload('res://probes/panels/fixtures.gd')
const Graph=preload('res://probes/panels/panel_graph.gd')
const Reduced=preload('res://probes/panels/reduced_panels.gd')
const SkinView=preload('res://probes/panels/panel_skin.gd')
var checks: Dictionary={}
var runs: Array=[]
var headons: Array=[]
var sequence: Dictionary={}
func _initialize() -> void:call_deferred('_run')
func check(name_: String,value: bool) -> void:
 checks[name_]=value
 print('EXTENDED_CHECK ',name_,' ',value)
func plastic(p: Dictionary) -> Array:
 return p.edges.map(func(e):return e.length)
func flags(p: Dictionary) -> Array:
 return p.anchors.map(func(a):return a.broken)+p.get('closing_supports',[]).map(func(a):return a.broken)
func headon_checks() -> void:
 for kind in ['headon_60','headon_120']:
  var f:=HeadOn.new();f.start(kind)
  var before_h: float=f.graph.panels.find('door_left').hinge_strength_n
  var mass_error:=0.0;var positive:=true;var preclear:=true
  while not f.complete:
   f.step();mass_error=maxf(mass_error,absf(f.graph.panels.total_mass()-1210))
   positive=positive and Array(f.graph.masses).all(func(m):return m>0)
   if f.time<.09:preclear=preclear and f.graph.panels.active_steps==0
  var m: Dictionary=f.metrics();headons.append(m)
  check(kind+'_actual_static_wall_launch',absf(m.measured_contact_kmh-m.requested_speed_kmh)<.2 and f.graph.panels.obstacle.velocity==Vector3.ZERO)
  check(kind+'_mass_once_positive_finite',mass_error<.001 and positive and m.finite)
  check(kind+'_closed_clear_approach_no_cages',preclear)
  check(kind+'_panel_wake_from_mount_distortion',m.structural_panel_wakes>=2)
  check(kind+'_same_material_profile',before_h==16000 and f.graph.panels.find('door_left').latch_strength_n==8000)
  check(kind+'_closed_door_bends_with_frame_connections',m.all_panels[0].max_plastic_edge_change_m>.05 and m.all_panels[0].closing.frame_seats==2 and m.all_panels[0].closing.hinges==2 and not m.all_panels[0].detached)
  if kind=='headon_60':check('60_closed_primary_latches_retain',m.all_panels[0].latched and m.all_panels[1].latched)
  check(kind+'_body_crushes',m.body.front_shortening_m>.3)
  check(kind+'_energy_bounded',m.maximum_energy_j<m.initial_energy_j*1.01+500)
  var path: String='res://probes/panels/data/'+kind+'.panelclip'
  var file:=FileAccess.open_compressed(path,FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD);file.store_var({'version':2,'hz':120,'source_glb_sha256':FileAccess.get_sha256('res://assets/Niva_2121_LOD0.glb'),'metrics':m,'frames':f.frames},false);file.close()
  var clip: Dictionary=FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_ZSTD).get_var(false)
  var replay:=Graph.new();replay.setup();replay.reset(0,Vector3.ZERO);replay.panels.reset()
  var exact:=true
  for state in clip.frames:
   replay.restore(state);exact=exact and replay.points==state.points and absf(replay.panels.total_mass()-1210)<.001
   for i in 4:exact=exact and replay.panels.panels[i].points==state.panels.panels[i].points and flags(replay.panels.panels[i])==flags(state.panels.panels[i])
  check(kind+'_disk_replay_exact_zero_solves',exact and replay.step_count==0 and replay.panels.active_steps==0)
  # Freeze the actual surviving latched plastic door; no healing on condensation.
  var reduced:=Reduced.new();reduced.setup(f.graph)
  var p: Dictionary=f.graph.panels.find('door_left');var original: PackedVector3Array=p.points.duplicate();var lengths: Array=plastic(p);var work: float=p.plastic_work
  reduced.freeze(p);reduced.dock(p)
  var error:=0.0
  for i in 10:error=maxf(error,original[i].distance_to(p.points[i]))
  check(kind+'_frozen_plastic_shape_and_mass_preserved',not p.active and p.reduced_mode=='frozen_plastic' and error<.00001 and plastic(p)==lengths and p.plastic_work==work and absf(f.graph.panels.total_mass()-1210)<.001)
 check('120_more_body_and_panel_deformation_than60',headons[1].body.front_shortening_m>headons[0].body.front_shortening_m and headons[1].all_panels[0].plastic_work_j>headons[0].all_panels[0].plastic_work_j)
 FileAccess.open('res://probes/panels/evidence/headon_results.json',FileAccess.WRITE).store_string(JSON.stringify(headons,'  '))
func drive_checks() -> void:
 for kind in ['closed','right_free','right_sag']:
  var d:=Drive.new();d.wall=false;d.start(kind)
  var p: Dictionary=d.graph.panels.find('door_right');var lengths: Array=plastic(p);var damage_flags: Array=flags(p)
  var low:=INF;var high:=-INF;var late_low:=INF;var late_high:=-INF;var finite:=true;var mass_error:=0.0
  for i in 1200:
   d.controls(1 if i<420 else 0,1 if i>=420 and i<720 else 0,.6*sin(i*.013) if i<850 else 0);d.step()
   low=minf(low,p.angle);high=maxf(high,p.angle)
   if i>=120:late_low=minf(late_low,p.angle);late_high=maxf(late_high,p.angle)
   mass_error=maxf(mass_error,absf(d.graph.panels.total_mass()-1210))
   for point_ in p.points:finite=finite and point_.is_finite() and point_.length()<500
  var result: Dictionary=d.stats();result['angle_range_deg']=[rad_to_deg(low),rad_to_deg(high)];result['settled_angle_range_deg']=[rad_to_deg(late_low),rad_to_deg(late_high)];runs.append(result)
  check(kind+'_drive_zero_full_structure_or_cage_solves',d.full_steps==0 and d.graph.panels.active_steps==0 and d.coarse_steps==1200)
  check(kind+'_drive_finite_mass_once',finite and mass_error<.001)
  check(kind+'_plastic_and_failures_never_heal',lengths==plastic(p) and flags(p)==damage_flags)
  if kind=='closed':check('closed_all_panels_asleep_and_latched',d.graph.panels.panels.all(func(part):return not part.active and part.latched and part.reduced_mode=='asleep_closed') and d.reduced.reduced_steps==0)
  else:
   check(kind+'_measured_latch_and_frame_seats_failed',p.anchors[2].broken and p.closing_supports.all(func(s):return s.broken) and p.plastic_work>100)
   check(kind+'_moves_under_driving_inertia',high-low>.2)
   check(kind+'_damaged_controls_cannot_heal',not d.reduced.set_open('door_right',0))
   check(kind+'_mode_transfer_pose_velocity_continuous',d.reduced.transitions[0].pose_error_m<.000001 and d.reduced.transitions[0].velocity_error_mps<.000001 and d.reduced.transitions[0].linear_error_ns<.001 and d.reduced.transitions[0].angular_error_nms<.001)
   if kind=='right_free':check('right_free_both_hinges_retain_and_settle_at_stops',not p.anchors[0].broken and not p.anchors[1].broken and late_low>-.01 and late_high<deg_to_rad(101))
   else:check('right_sag_one_hinge_retains',p.anchors[0].broken and not p.anchors[1].broken and not p.detached)
  # Every reduced frame has frozen shape and ownership, and replays without stepping.
  var file:=FileAccess.open_compressed('res://probes/panels/data/drive_'+kind+'.panelclip',FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD);file.store_var({'version':2,'hz':60,'frames':d.frames},false);file.close()
  var loaded: Dictionary=FileAccess.open_compressed('res://probes/panels/data/drive_'+kind+'.panelclip',FileAccess.READ,FileAccess.COMPRESSION_ZSTD).get_var(false)
  var full_before: int=d.full_steps;var reduced_before: int=d.reduced.reduced_steps;var exact:=true
  for state in loaded.frames:
   d.restore(state);exact=exact and d.graph.points==state.graph.points and absf(d.graph.panels.total_mass()-1210)<.001
   for index in 4:exact=exact and d.graph.panels.panels[index].points==state.graph.panels.panels[index].points
  for index in range(loaded.frames.size()-1,-1,-17):
   var state: Dictionary=loaded.frames[index];d.restore(state)
   for part in 4:exact=exact and d.graph.panels.panels[part].points==state.graph.panels.panels[part].points
  check(kind+'_reduced_disk_replay_exact_zero_solves',exact and full_before==d.full_steps and reduced_before==d.reduced.reduced_steps)
func controls_checks() -> void:
 for id in ['door_left','door_right','bonnet','tailgate']:
  var d:=Drive.new();d.wall=false;d.start('closed');var p: Dictionary=d.graph.panels.find(id)
  check(id+'_initial_latch_topology',p.latched and d.graph.panels.closing_topology(p).hinges==2)
  d.reduced.set_open(id,60)
  var topology: Dictionary=d.graph.panels.closing_topology(p)
  check(id+'_open_disengages_closing_not_hinges',not topology.latch and topology.frame_seats==0 and topology.hinges==2)
  for i in 600:d.step()
  check(id+'_reduced_opens_and_stops',rad_to_deg(p.angle)>45 and rad_to_deg(p.angle)<85)
  d.reduced.set_open(id,0)
  check(id+'_close_does_not_instantly_snap_latch',not p.latched)
  for i in 1200:d.step()
  check(id+'_close_reengages_and_resleeps',not p.active and p.latched and p.reduced_mode=='asleep_closed' and d.graph.panels.closing_topology(p).frame_seats==(2 if p.side!=0 else 0))
  check(id+'_close_condensation_continuous',d.reduced.transitions.filter(func(e):return e.to=='asleep_closed').all(func(e):return e.pose_error_m<.00001) and d.graph.panels.activation_continuity.all(func(e):return e.linear_error<.02 and e.angular_error<.02))
  check(id+'_open_close_uses_no_full_solver',d.full_steps==0 and d.graph.panels.active_steps==0 and absf(d.graph.panels.total_mass()-1210)<.001)
func dynamics_checks() -> void:
 # Explicit topology fixture: severed hinges do not silently delete a healthy latch/rim.
 var held:=Graph.new();held.setup();held.reset(0,Vector3.ZERO);held.panels.reset()
 var held_door: Dictionary=held.panels.find('door_left');held.panels.configure_closing_seats(held_door);held.panels.activate(held_door)
 held_door.anchors[0].broken=true;held_door.anchors[1].broken=true
 for i in 24:held.step(1.0/480)
 check('broken_hinges_do_not_delete_remaining_closing_connections',not held_door.detached and held_door.latched and not held_door.anchors[2].broken and held_door.closing_supports.all(func(s):return not s.broken))
 var weak:=Fixture.new();weak.start('weak_closed')
 for p in weak.graph.panels.panels:weak.graph.panels.configure_closing_seats(p)
 while not weak.complete:weak.step()
 var weak_door: Dictionary=weak.graph.panels.find('door_left')
 check('weak_real_contact_keeps_latch_hinges_frame_seats',weak_door.contacts>0 and weak_door.latched and not weak_door.detached and weak_door.anchors.all(func(a):return not a.broken) and weak_door.closing_supports.all(func(s):return not s.broken))
 var angles: Array=[];var traces: Array=[]
 for variant in ['still','accelerate','coast','brake','turn']:
  var d:=Drive.new();d.wall=false;d.start('right_free')
  var trace: Array=[]
  for i in 600:
   var throttle: float=1 if variant!='still' and i<(48 if variant in ['coast','brake'] else 360) else 0
   d.controls(throttle,1 if variant=='brake' and i>=48 else 0,.7 if variant=='turn' and i>=250 else 0);d.step()
   trace.append(d.graph.panels.find('door_right').angle)
  traces.append(trace)
  angles.append(d.graph.panels.find('door_right').angle)
 var braking_difference:=0.0;var cornering_difference:=0.0
 for i in 600:
  braking_difference=maxf(braking_difference,absf(traces[2][i]-traces[3][i]))
  cornering_difference=maxf(cornering_difference,absf(traces[1][i]-traces[4][i]))
 check('braking_changes_free_door_response',braking_difference>.03)
 check('cornering_changes_free_door_response',cornering_difference>.03)
 sequence['inertial_max_angle_difference_deg']={'brake':rad_to_deg(braking_difference),'turn':rad_to_deg(cornering_difference)}
 sequence['inertial_order']=['still','accelerate','coast','brake','turn']
 sequence['inertial_angle_end_deg']=angles.map(func(a):return rad_to_deg(a))
 # Fresh wall impact wakes full cages, then all intact/damaged parts return reduced.
 var d:=Drive.new();d.start('right_free')
 d.graph.barrier_min=Vector3(3.2,0,-12);d.graph.barrier_max=Vector3(3.7,3.5,12)
 d.compact.linear_velocity=Vector3(8,0,0);d.compact.flush()
 for wheel in d.graph.wheels.wheels:d.graph.velocities[wheel.node]=Vector3(8,0,0);wheel.spin_speed=-8/wheel.radius
 var broken_before: Array=flags(d.graph.panels.find('door_right'));var transitions_before: int=d.reduced.transitions.size()
 for i in 360:d.controls(0,1,0);d.step()
 check('new_contact_wakes_full_deformation_then_reduces',d.full_steps>0 and d.graph.panels.active_steps>0 and d.full_remaining<=0 and d.reduced.transitions.size()>transitions_before and d.graph.panels.panels.all(func(p):return not p.active or p.reduced))
 check('new_contact_preserves_existing_failure_ownership',d.graph.panels.find('door_right').anchors[2].broken and absf(d.graph.panels.total_mass()-1210)<.001)
 sequence['new_impact']=d.stats()
 # Native skin's cached transforms continue to reproduce world-space cage points.
 var view:=Node3D.new();view.set_script(SkinView);view.panel_system=d.graph.panels;root.add_child(view);view.setup(d.graph);view.set_mode(2);view.show_frame=false;view.update_pose()
 var quality: Dictionary=view.panel_quality()
 check('reduced_panel_skin_matches_world_pose',quality.max_anchor_error_m<.0001 and quality.max_weight_error<.00001 and quality.glass_uses_panel_skeleton and quality.mesh_rebuilds_during_simulation==0)
 sequence['cached_skin']=quality;view.queue_free()
func detached_checks() -> void:
 var clip: Dictionary=FileAccess.open_compressed('res://probes/panels/data/open_severe.panelclip',FileAccess.READ,FileAccess.COMPRESSION_ZSTD).get_var(false)
 var d:=Drive.new();d.wall=false;d.start('closed');d.graph.restore(clip.frames[-1])
 d.compact.mass=0
 for i in d.compact.indices:d.compact.mass+=d.graph.masses[i]
 d.compact.capture_shape();d.graph.compact_active=true
 var p: Dictionary=d.graph.panels.find('door_left');var before: PackedVector3Array=p.points.duplicate();var velocities: PackedVector3Array=p.velocity.duplicate();var lengths: Array=plastic(p)
 d.reduced.freeze(p)
 check('detached_reduction_no_release_pop',p.points==before and p.velocity==velocities and p.reduced and p.detached)
 for i in 1200:d.controls(0,1,0);d.step()
 check('detached_has_proxy_floor_contacts_no_cages',d.reduced.contacts>0 and d.graph.panels.active_steps==0 and d.full_steps==0 and plastic(p)==lengths and p.anchors.all(func(a):return a.broken))
 check('detached_sleeps_when_quiet',p.reduced_data.sleep and p.reduced_mode=='detached_sleep')
 check('detached_mass_remains_once',absf(d.graph.panels.total_mass()-1210)<.001)
 sequence['detached']=d.stats()
func _run() -> void:
 headon_checks();drive_checks();controls_checks();dynamics_checks();detached_checks()
 var passed: bool=checks.values().all(func(v):return v)
 FileAccess.open('res://probes/panels/evidence/extended_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'headon':headons,'driving':runs,'sequence':sequence,'scope':'Actual static-wall car launches at960Hz; shared compact chassis driving at120Hz; frozen-shape rigid panels, reciprocal hinges and retained mass. Prototype parameters, not factory calibration.'},'  '))
 print('EXTENDED_PANELS_VERIFIED ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
