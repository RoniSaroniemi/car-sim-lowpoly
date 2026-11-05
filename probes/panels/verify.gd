extends SceneTree
const Fixture=preload('res://probes/panels/fixtures.gd')
const Graph=preload('res://probes/panels/panel_graph.gd')
const Base=preload('res://scripts/structure_solver.gd')
const SkinView=preload('res://probes/panels/panel_skin.gd')
var checks: Dictionary={}
var runs: Array=[]
var captured: Dictionary={}
var control_result: Dictionary={}
func _initialize() -> void:call_deferred('_run')

func case_checks(name_: String) -> void:
 var fixture:=Fixture.new();fixture.start(name_)
 var max_mass_error:=0.0;var positive:=true
 while not fixture.complete:
  fixture.step();max_mass_error=maxf(max_mass_error,absf(fixture.graph.panels.total_mass()-1210))
  positive=positive and Array(fixture.graph.masses).all(func(m):return m>0)
 var m: Dictionary=fixture.metrics();runs.append(m)
 checks[name_+'_finite']=m.finite
 checks[name_+'_mass_once_positive']=max_mass_error<.001 and positive
 checks[name_+'_samples_complete']=fixture.frames.size()==301 and fixture.graph.step_count==1200
 var speed: float=20 if name_.ends_with('severe') else 6 if name_!='weak_closed' else 1.1
 checks[name_+'_energy_bounded']=m.maximum_energy_j<m.initial_energy_j+.5*25*speed*speed*2+300
 checks[name_+'_activation_conserves_momentum']=m.panel_stats.activation_continuity.all(func(event):return event.linear_error<.001 and event.angular_error<.001)
 if name_=='controls':checks['intact_closed_zero_panel_solves']=m.panel_stats.active_steps==0 and m.contacts==0 and m.latched
 if name_=='weak_closed':checks['weak_contact_retains_mounts_latch']=m.contacts>0 and m.failed_hinges==0 and not m.latch_broken and not m.detached
 if name_=='missed_open':checks['missed_open_contact_does_not_damage']=m.contacts==0 and m.failed_hinges==0 and m.panel_plastic_work_j<.001
 if name_=='closed_medium':
  checks['closed_hit_breaks_latch_leaves_one_hinge']=m.latch_broken and m.failed_hinges==1 and not m.detached
  checks['closed_panel_really_deforms']=m.max_plastic_edge_change_m>.04 and m.panel_plastic_work_j>100
  checks['damaged_closed_command_cannot_heal']=not fixture.graph.panels.set_open('door_left',0) and fixture.graph.panels.find('door_left').anchors[2].broken
 if name_=='open_medium':checks['open_contact_deforms_and_retains_hinges']=m.contacts>0 and m.max_plastic_edge_change_m>.015 and m.failed_hinges==0 and not m.detached
 if name_=='closed_severe':checks['closed_severity_not_forced_detachment']=m.latch_broken and m.contacts>0 and not m.detached
 if name_=='open_severe':
  checks['severe_open_contact_detaches']=m.detached and m.failed_hinges==2 and m.contacts>0
  checks['detachment_pose_velocity_momentum_continuous']=m.panel_stats.release_continuity.size()==1 and m.panel_stats.release_continuity.all(func(event):return event.point_error_m<.000001 and event.velocity_error_mps<.000001 and event.linear_error_ns<.001 and event.angular_error_nms<.001)
  checks['detached_panel_has_no_live_body_mounts']=fixture.graph.panels.find('door_left').anchors.all(func(a):return a.broken)
  checks['detached_control_does_not_reattach']=not fixture.graph.panels.set_open('door_left',0)
  captured={'fixture':fixture,'frames':fixture.frames.duplicate(true)}
 print('PANEL_VERIFICATION_CASE ',name_,' ',JSON.stringify(m))

func controls_checks() -> void:
 var g:=Graph.new();g.setup();g.reset(0,Vector3.ZERO);g.panels.reset()
 for id in ['door_left','door_right','bonnet','tailgate']:g.panels.set_open(id,60)
 var peaks: Dictionary={}
 for step in 1200:
  g.step(1.0/480)
  for p in g.panels.panels:peaks[p.id]=maxf(float(peaks.get(p.id,0)),absf(rad_to_deg(p.angle)))
 for p in g.panels.panels:
  checks[p.id+'_opens_under_control']=rad_to_deg(p.angle)>45 and rad_to_deg(p.angle)<85
  checks[p.id+'_control_retains_mounts']=not p.detached and p.anchors.all(func(a):return not a.broken) and p.plastic_work<.1
  checks[p.id+'_reasonable_angle_stops']=float(peaks[p.id])<102
 control_result['open']=g.panels.capture()
 for id in ['door_left','door_right','bonnet','tailgate']:g.panels.set_open(id,0)
 for step in 1680:g.step(1.0/480)
 for p in g.panels.panels:
  checks[p.id+'_can_close_without_healing']=absf(rad_to_deg(p.angle))<5 and p.latched and not p.detached
 control_result['closed']=g.panels.capture()
 checks['all_open_closed_mass_once']=absf(g.panels.total_mass()-1210)<.001 and Array(g.masses).all(func(m):return m>0)
 checks['all_control_transfers_preserve_momentum']=g.panels.activation_continuity.all(func(e):return e.linear_error<.001 and e.angular_error<.001)

func idle_checks() -> void:
 var base:=Base.new();base.setup();base.reset(0,Vector3.ZERO);base.config.enforce_symmetry=false;base.barrier_enabled=false
 var panel:=Graph.new();panel.setup();panel.reset(0,Vector3.ZERO);panel.panels.reset()
 var error:=0.0
 for step in 120:
  base.step(1.0/480);panel.step(1.0/480)
  for i in base.points.size():error=maxf(error,base.points[i].distance_to(panel.points[i]))
 checks['sleeping_panels_preserve_body_baseline']=error<.000001
 checks['sleeping_panels_have_no_separate_mass']=absf(float(panel.config.mass_kg)-1210)<.001 and not panel.panels.panels.any(func(p):return p.active)
 var began: int=Time.get_ticks_usec()
 for step in 1000:panel.panels.prepare_step(1.0/120);panel.panels.solve();panel.panels.finish_step()
 control_result['idle_panel_overhead_us']=float(Time.get_ticks_usec()-began)/1000
 checks['closed_panel_path_no_cage_solve']=panel.panels.active_steps==0

func replay_checks() -> void:
 checks['severe_case_available_for_replay']=captured.has('fixture')
 if not captured.has('fixture'):return
 var frames: Array=captured.frames
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://probes/panels/data'))
 var path: String='res://probes/panels/data/open_severe.panelclip'
 var file:=FileAccess.open_compressed(path,FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD)
 file.store_var({'version':1,'source_glb_sha256':FileAccess.get_sha256('res://assets/Niva_2121_LOD0.glb'),'frames':frames});file.close()
 var loaded: Dictionary=FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_ZSTD).get_var(false)
 var replay:=Graph.new();replay.setup();replay.reset(0,Vector3.ZERO);replay.panels.reset()
 var maximum_error:=0.0;var flags:=true;var mass:=true
 for frame in loaded.frames:
  replay.restore(frame)
  for i in replay.points.size():maximum_error=maxf(maximum_error,replay.points[i].distance_to(frame.points[i]))
  for index in replay.panels.panels.size():
   var actual: Dictionary=replay.panels.panels[index];var expected: Dictionary=frame.panels.panels[index]
   for node in 10:maximum_error=maxf(maximum_error,actual.points[node].distance_to(expected.points[node]))
   flags=flags and actual.detached==expected.detached and actual.latched==expected.latched and actual.anchors.map(func(a):return a.broken)==expected.anchors.map(func(a):return a.broken)
  mass=mass and absf(replay.panels.total_mass()-1210)<.001
 checks['replay_body_and_panel_poses_exact']=maximum_error<.000001
 checks['replay_topology_latch_hinges_exact']=flags
 checks['replay_mass_and_zero_solver_steps']=mass and replay.step_count==0 and replay.panels.active_steps==0
 control_result['clip_bytes']=FileAccess.get_file_as_bytes(path).size()
 # A second real strike on the opposite door must not reset a previous release.
 var g: RefCounted=captured.fixture.graph
 var free_before: PackedVector3Array=g.panels.find('door_left').points.duplicate()
 g.panels.obstacle={'center':Vector3(-.1,1,-2.3),'size':Vector3(.62,.65,.14),'velocity':Vector3(0,0,6),'travel_axis':2,'stop':-.62,'retracting':false}
 checks['second_hit_setup_does_not_teleport_free_panel']=free_before==g.panels.find('door_left').points
 var was_detached:=true
 for step in 480:
  g.step(1.0/480);was_detached=was_detached and g.panels.find('door_left').detached and absf(g.panels.total_mass()-1210)<.001
 checks['second_hit_retains_prior_free_panel']=was_detached and g.panels.find('door_right').contacts>0
 var view:=Node3D.new();view.set_script(SkinView);view.panel_system=g.panels;root.add_child(view);view.setup(g);view.show_frame=false;view.set_mode(2);view.update_pose()
 var quality: Dictionary=view.panel_quality();control_result['skin']=quality
 checks['source_glass_and_trim_follow_panel_skeleton']=quality.glass_uses_panel_skeleton and quality.panel_bones==40
 checks['native_cage_skin_binding_valid']=quality.max_anchor_error_m<.00001 and quality.max_weight_error<.00001
 checks['no_runtime_mesh_rebuild']=quality.mesh_rebuilds_during_simulation==0
 view.queue_free()

func _run() -> void:
 for name_ in Fixture.CASES:case_checks(name_)
 checks['all_cases_complete']=runs.size()==7
 controls_checks();idle_checks();replay_checks()
 var passed: bool=checks.values().all(func(value):return value)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://probes/panels/evidence'))
 FileAccess.open('res://probes/panels/evidence/validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':runs,'controls_and_budget':control_result,'scope':'Operable source panels, own mass extracted from chassis once; local cage/hinge/latch simulation. Kinematic controlled strikers supply external work. No factory fracture calibration.'},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('ARTICULATED_PANELS_VERIFIED ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
