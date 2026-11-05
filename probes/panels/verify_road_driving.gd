extends SceneTree
const Case=preload('res://probes/panels/driving_crash_case.gd')
const Drive=preload('res://probes/panels/drive_runtime.gd')
const Graph=preload('res://probes/panels/panel_graph.gd')
const Profile=preload('res://probes/panels/road_panel_profile.gd')
const Angular=preload('res://probes/panels/panel_angular_mount.gd')
const Terrain=preload('res://scripts/practice_terrain.gd')
var checks: Dictionary={}
var runs: Array=[]
var budgets: Array=[]
var angular_runs: Array=[]
var side_runs: Array=[]
func _initialize() -> void:call_deferred('_run')
func check(id: String,condition: bool) -> void:
 checks[id]=condition;print('ROAD_CHECK ',id,' ',condition)
func save_clip(name_: String,states: Array,metadata: Dictionary) -> void:
 var f:=FileAccess.open_compressed('res://probes/panels/data/'+name_+'.panelclip',FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD)
 f.store_var({'version':3,'hz':60,'frames':states,'metadata':metadata},false);f.close()
func road_profile(parts: Array) -> bool:
 return parts.all(func(p):return p.profile==Profile.ID and p.hinge_n==16000 and p.latch_n==8000 and p.weak_reference=='')
func crash(speed_: float,angle: float,opening: bool=false,rest: bool=false) -> void:
 var fixture:=Case.new();fixture.start(speed_,angle,opening,rest,opening)
 while not fixture.complete:fixture.step()
 var r: Dictionary=fixture.result();runs.append(r)
 var name_: String='road_%d_%s%d' %[int(speed_),'p' if angle>=0 else 'm',int(absf(angle))]
 if opening:name_='road_open_'+name_
 if rest:name_='road_throttle_from_rest'
 check(name_+'_actual_drive_contact',r.contact_time_s>0 and r.stats.full_structure_steps>0 and r.actual_contact_kmh>30)
 check(name_+'_same_road_profile_all_modes',r.history.all(func(s):return road_profile(s.parts)) and road_profile(r.final.parts))
 check(name_+'_finite_single_mass',r.finite and r.mass_error_kg<.001 and absf(r.stats.mass_kg-1210)<.001)
 check(name_+'_returns_reduced',fixture.drive.full_remaining<=0 and fixture.drive.graph.panels.panels.all(func(p):return not p.active or p.reduced))
 if not opening:
  check(name_+'_closed_doors_remain_seated_hinged',r.final.parts.slice(0,2).all(func(p):return not p.detached and p.closing.hinges==2 and p.closing.latch and p.closing.frame_seats==2))
  check(name_+'_uncontacted_other_panels_keep_mounts',r.final.parts.all(func(p):return p.contacts>0 or p.anchors.all(func(a):return not a.broken)))
  check(name_+'_visible_panel_deformation',r.final.parts[0].plastic_j+r.final.parts[1].plastic_j>10)
 else:
  var p: Dictionary=r.final.parts[1]
  var first: Array=fixture.drive.transitions[0].get('panel_handoff',[])
  check(name_+'_coarse_full_hinge_residual_under12mm',not first.is_empty() and first[0].anchor_residual_m[0]<.012 and first[0].anchor_residual_m[1]<.012)
  check(name_+'_open_panel_actual_local_strike',p.contacts>0 and p.local.lever_m>.35 and p.plastic_j>10)
  check(name_+'_uncontacted_panels_do_not_release',r.final.parts.all(func(part):return part.contacts>0 or part.anchors.all(func(a):return not a.broken)))
 if rest or speed_==120 and angle in [30.0,0.0] or opening:save_clip(name_,fixture.records,r)
 print('ROAD_CASE ',name_,' contact=',r.actual_contact_kmh,' normal=',r.actual_normal_contact_kmh,' parts=',r.final.parts.map(func(p):return [p.id,p.detached,p.closing,p.plastic_m]))
func benign_and_budget() -> void:
 for kind in ['closed','right_free','right_sag']:
  var d:=Drive.new();d.wall=false;d.start(kind);var p: Dictionary=d.graph.panels.find('door_right')
  var flags: Array=p.anchors.map(func(a):return a.broken);var plastic_before: float=p.get('angular_mount',{}).get('plastic_rad',0)
  var max_tilt:=0.0
  for step in 1200:
   d.controls(1 if step<360 else 0,1 if step>=360 and step<600 else 0,.6*sin(step*.02) if step<850 else 0);d.step()
   if kind=='right_sag':max_tilt=maxf(max_tilt,Angular.error_vector(Angular.axis_from_points(p),Angular.target(d.graph,p,AttachmentFrames(d))).length())
  var stats: Dictionary=d.stats();stats['case']=kind;stats['maximum_hinge_elastic_tilt_deg']=rad_to_deg(max_tilt);budgets.append(stats)
  check(kind+'_normal_drive_zero_full_or_cage',d.full_steps==0 and d.graph.panels.active_steps==0)
  check(kind+'_normal_drive_retains_mounts_mass',flags==p.anchors.map(func(a):return a.broken) and absf(d.graph.panels.total_mass()-1210)<.001)
  if kind=='right_sag':check('single_hinge_stiff_under_drive_gravity',max_tilt<deg_to_rad(16) and p.angular_mount.plastic_rad-plastic_before<deg_to_rad(4))
 var d:=Drive.new();d.wall=false;d.start('closed');d.graph.terrain=Terrain.new();d.graph.terrain.ramps.clear();d.graph.terrain.ramps.append({'name':'BENIGN','start':5.0,'length':16.0,'height':.25,'z':0.0,'width':10.0})
 d.compact.linear_velocity=Vector3(10,0,0);d.compact.flush()
 for wheel in d.graph.wheels.wheels:d.graph.velocities[wheel.node]=Vector3(10,0,0);wheel.spin_speed=-10/wheel.radius
 for step in 600:d.controls(0,0,0);d.step()
 check('benign_ramp_keeps_closed_panels_no_full_solver',d.full_steps==0 and d.graph.panels.active_steps==0 and d.graph.panels.panels.all(func(p):return p.anchors.all(func(a):return not a.broken)))
func AttachmentFrames(d: RefCounted) -> Array:return d.graph.panels.Attachment.rotations(d.graph)
func angular_cases() -> void:
 for moment in [0.0,1800.0,20000.0]:
  var d:=Drive.new();d.wall=false;d.start('right_sag');var p: Dictionary=d.graph.panels.find('door_right');var before: float=p.angular_mount.plastic_rad;var max_tilt:=0.0
  for step in 600:
   d.controls(0,1,0)
   if step>=60 and step<120 and not p.detached:p.reduced_data.omega+=Angular.inverse(p.reduced_data,Vector3.RIGHT*moment*d.h)
   d.step()
   if not p.detached:max_tilt=maxf(max_tilt,Angular.error_vector(Angular.axis_from_points(p),Angular.target(d.graph,p,AttachmentFrames(d))).length())
  var result: Dictionary={'applied_moment_nm':moment,'mount':p.angular_mount.duplicate(true),'detached':p.detached,'max_elastic_tilt_deg':rad_to_deg(max_tilt),'stats':d.stats(),'continuity':d.graph.panels.release_continuity};angular_runs.append(result)
  check('angular_%d_zero_full_cage_mass' %int(moment),d.full_steps==0 and d.graph.panels.active_steps==0 and absf(d.graph.panels.total_mass()-1210)<.001)
  if moment==0:check('one_hinge_no_floppy_ball_joint',max_tilt<deg_to_rad(16) and not p.detached)
  elif moment==1800:check('one_hinge_yields_permanently_but_retains',p.angular_mount.plastic_rad-before>deg_to_rad(5) and not p.detached and not p.anchors[1].broken)
  else:check('extreme_local_torsion_tears_remaining_mount_continuously',p.detached and p.angular_mount.get('torn',false) and d.graph.panels.release_continuity.all(func(e):return e.point_error_m<.000001 and e.velocity_error_mps<.000001 and e.linear_error_ns<.001 and e.angular_error_nms<.001))
  FileAccess.open('res://probes/panels/data/hinge_'+str(int(moment))+'.panelstate',FileAccess.WRITE).store_var(d.capture(),false)
func side_cases() -> void:
 for speed_ in [12.0,24.0]:
  var g:=Graph.new();g.setup();g.reset(0,Vector3.ZERO);g.panels.reset();Profile.apply(g.panels);g.config.fixed_step_s=1.0/960
  for link in g.links:link.damping_fraction=1-exp(-link.damping_ns_per_m*link.weight_sum/960)
  g.panels.obstacle={'center':Vector3(-.1,1.1,-2.3),'size':Vector3(.95,1.4,.14),'velocity':Vector3(0,0,speed_),'travel_axis':2,'stop':.05,'retracting':false,'hold_at_stop':true}
  var frames: Array=[g.capture()]
  for step in 960:g.step(1.0/960);if step%16==15:frames.append(g.capture())
  var p: Dictionary=g.panels.find('door_right')
  var result: Dictionary={'speed_mps':speed_,'right_anchors':p.anchors.map(func(a):return a.broken),'seats':p.closing_supports.map(func(a):return a.broken),'detached':p.detached,'evidence':p.impact_evidence.duplicate(true),'events':g.panels.events.duplicate(true),'mass_kg':g.panels.total_mass()};side_runs.append(result)
  check('side_%d_other_panels_do_not_fail' %int(speed_),g.panels.panels.filter(func(part):return part.id!='door_right').all(func(part):return part.anchors.all(func(a):return not a.broken)))
  if speed_==24:check('severe_local_side_intrusion_can_release',p.detached and p.impact_evidence.inward_alignment>.70 and p.impact_evidence.max_inward_m>.45 and p.anchors.all(func(a):return a.broken) and p.closing_supports.all(func(a):return a.broken))
  else:check('moderate_side_retains_stiff_remaining_hinge',not p.detached and p.anchors[0].broken and not p.anchors[1].broken)
  var file:=FileAccess.open_compressed('res://probes/panels/data/road_side_'+str(int(speed_))+'.panelclip',FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD);file.store_var({'version':3,'hz':60,'frames':frames,'metadata':result},false);file.close()
func _run() -> void:
 crash(0,0,false,true)
 for speed_ in [60.0,120.0]:
  for angle in [0.0,20.0,-20.0,30.0,-30.0]:crash(speed_,angle)
 crash(60,0,true);crash(120,-20,true)
 benign_and_budget();angular_cases();side_cases()
 var passed: bool=checks.values().all(func(v):return v)
 FileAccess.open('res://probes/panels/evidence/road_driving_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'driving_collisions':runs,'offimpact_cpu':budgets,'angular_cases':angular_runs,'side_cases':side_runs,'scope':'Actual DriveRuntime path, common road profile; local admissible fracture, stiff yielding single hinge, reciprocal same mass. Not real-vehicle crash calibration.'},'  '))
 print('ROAD_DRIVING_VERIFIED ',passed,' checks=',checks.size());quit(0 if passed else 1)
