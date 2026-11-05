extends SceneTree
const Cases=preload('res://scripts/multiaxis_crash_cases.gd')
const Recorder=preload('res://scripts/multiaxis_crash_recorder.gd')
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Player=preload('res://scripts/baked_crash_player.gd')
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred('_run')
func check(ok: bool,message: String) -> void:
 if not ok:push_error(message);failures+=1
 checks+=1
func _run() -> void:
 check(Cases.directions().size()==18 and Cases.specifications().size()==36,'18 directions / 36 cases')
 var paths: Array=[]
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with('--clips='):
   for path in argument.trim_prefix('--clips=').split(','):paths.append(path)
 for spec in Cases.directions():
  var q: Array=spec.rotation_xyzw;var b:=Basis(Quaternion(q[0],q[1],q[2],q[3]));var d: Array=spec.incoming_car_direction
  check((b*Vector3(d[0],d[1],d[2])).distance_to(Vector3.DOWN)<1e-5,'Direction rotated to down '+spec.key)
  var recorder:=Recorder.new();recorder.start(spec.key,60,4)
  check(absf(Recorder.minimum_gap(recorder.vehicle.solver)-1)<1e-5,'One metre clearance '+spec.key)
  check(recorder.vehicle.solver.panels.panels.all(func(p):return p.latched and not p.active and not p.detached),'Closed latched starting panels '+spec.key)
  check(absf(recorder.vehicle.solver.owned_mass_kg()-1210)<.001,'One mass ledger '+spec.key)
  check(Recorder.time_to_contact(recorder.vehicle.solver,1)<.061,'Finite bounded contact '+spec.key)
 for path in paths:_verify_clip(path)
 print('MULTIAXIS_AUTHORING_RESULT checks=',checks,' failures=',failures,' clips=',paths.size());quit(1 if failures else 0)
func _verify_clip(path: String) -> void:
 var data: Dictionary=Clip.read(path)
 check(not data.is_empty(),'Clip exists '+path)
 check(data.metadata.family=='multiaxis_floor' and data.metadata.physics_hz==1920,'Family and high authoring precision')
 check(data.frames.size()==301 and data.metadata.panels_schema==1,'301 full panel frames')
 check(Clip.input_compatibility(data).compatible,'Physical fingerprints match')
 check(absf(data.metadata.signature.closing_speed_mps-data.metadata.speed_kmh/3.6)<1e-5,'Normalized contact speed')
 check(absf(data.metadata.first_physical_floor_gap_m)<.0003,'Exact earliest physical contact')
 check(data.metadata.maximum_mass_error_kg<.00001,'Mass invariant during authoring')
 var sources: Array=data.metadata.signature.first_contacts.map(func(p):return p.source)
 if data.metadata.direction_key=='underside':check('wheel' in sources and data.metadata.first_body_floor_gap_m>.05,'Honest wheel-first underside')
 for frame in data.frames:
  check(frame.has('panels') and frame.panels.panels.size()==4 and frame.has('mass_nodes') and frame.effects.has('glass') and frame.effects.has('interior') and frame.effects.has('surface'),'All physical/effects layers recorded')
  for point in frame.points:check(point.is_finite(),'Finite recorded body')
 var owner:=Vehicle.new();owner.setup('res://vehicles/niva.json',false)
 var g: RefCounted=owner.solver
 var target:=Vector3(31,4,-8);var rotation:=Basis.from_euler(Vector3(.24,.79,-.18))
 g.effects.begin_playback(data.frames[0].effects)
 Clip.apply(g,data,0,target,rotation)
 var identity:=g.get_instance_id()
 var player:=Player.new()
 player.attach_live(owner,[data],data.metadata.signature,{'accepted':true,'index':0,'id':data.metadata.id})
 while player.state=='REPLAY':player.advance(1.0/120)
 check(player.state=='COMPLETE' and g.get_instance_id()==identity,'In-place replay completes')
 check(player.replay_rotation.x.distance_to(rotation.x)<.0001 and player.replay_rotation.y.distance_to(rotation.y)<.0001,'Full pitch/yaw/roll registration')
 var last: Dictionary=data.frames[-1]
 for i in g.points.size():check(g.points[i].distance_to(rotation*last.points[i]+target)<.001,'Transformed final body')
 var expected: Dictionary=Clip.PanelState.transformed(last.panels,rotation,target)
 for p in expected.panels:
  var actual: Dictionary=g.panels.find(p.id)
  check(actual.detached==p.detached and actual.latched==p.latched,'Panel mount state preserved')
  for k in p.points.size():check(actual.points[k].distance_to(p.points[k])<.001,'Full3D panel cage preserved')
 for id in last.effects.glass.panes:
  var a: Dictionary=g.effects.glass.capture().panes[id];var b: Dictionary=last.effects.glass.panes[id]
  check(a.stage==b.stage and a.mask==b.mask and a.broken==b.broken and a.released==b.released,'Glass breakage state preserved '+id)
 check(absf(g.owned_mass_kg()-1210)<.00001,'Replay mass invariant')
 check(g.step_count==0 and owner.full_steps==0 and player.full_steps==0 and g.panels.active_steps==0 and g.effects.glass.membrane_solve_steps==0 and g.effects.interior.cloth_steps==0,'Strict zero body/cage/glass membrane/airbag solves')
 print('MULTIAXIS_REPLAY_PASS ',data.metadata.id,' zero_full_steps=',g.step_count,' zero_panel_steps=',g.panels.active_steps,' zero_membrane_steps=',g.effects.glass.membrane_solve_steps,' zero_cloth_steps=',g.effects.interior.cloth_steps,' mass=',g.owned_mass_kg(),' authored_wall_ms=',data.metadata.total_wall_ms)
