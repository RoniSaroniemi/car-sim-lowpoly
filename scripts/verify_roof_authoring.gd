extends SceneTree
const Recorder=preload('res://scripts/roof_crash_recorder.gd')
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
var checks: Dictionary={}
var runs: Array=[]
func _initialize() -> void:call_deferred('_run')
func utility_checks() -> void:
 var vehicle:=Vehicle.new();vehicle.setup('res://vehicles/niva.json',false)
 var g: RefCounted=vehicle.solver
 for i in g.points.size():
  g.points[i].y=10;g.velocities[i]=Vector3.ZERO
 for wheel in g.wheels.wheels:g.points[wheel.node].y=wheel.radius;g.velocities[wheel.node]=Vector3.DOWN*10
 checks['tires_do_not_arm_roof_contact']=not is_finite(Recorder.body_floor_time_to_contact(g,.01))
 var frame:=Basis(Vector3.UP,.4)*Basis(Vector3.BACK,.25)*Basis(Vector3.RIGHT,PI+.3)
 for i in g.points.size():g.points[i]=frame*g.rest[i]+Vector3(10,4,-2)
 var measured: Basis=Recorder.full_chassis_basis(g)
 checks['basis_preserves_full_roll_pitch_yaw']=measured.x.dot(frame.x)>.99999 and measured.y.dot(frame.y)>.99999 and measured.z.dot(frame.z)>.99999 and measured.determinant()>.99999
func record_case(name_: String,quality: int) -> void:
 var recorder:=Recorder.new();recorder.start(name_,35,quality)
 var guard:=0
 while not recorder.completed and guard<20000:recorder.step();guard+=1
 var key: String=name_+'_'+str(quality)
 checks[key+'_completes']=recorder.completed
 if not recorder.completed:return
 var data: Dictionary=recorder.result;var g: RefCounted=recorder.vehicle.solver
 checks[key+'_301_frames']=data.frames.size()==301
 checks[key+'_version_family_profile']=data.metadata.version==3 and data.metadata.family=='roof_floor' and data.metadata.material_profile=='niva_multiaxis_v1'
 checks[key+'_actual_physics_hz']=data.metadata.physics_hz==480*quality
 checks[key+'_exact_first_body_boundary']=absf(recorder.first_contact_gap_m)<.00001
 checks[key+'_requested_normal_impact_speed']=absf(float(recorder.signature.closing_speed_mps)*3.6-35)<.0001
 checks[key+'_full_solver_owns_mass_once']=g.step_count==recorder.full_steps and absf(float(g.config.mass_kg)-1210)<.001 and g.points.size()==38
 checks[key+'_normal_is_full_car_frame']=Vector3(recorder.signature.normal[0],recorder.signature.normal[1],recorder.signature.normal[2]).length()>.9999
 checks[key+'_nonwheel_hit_nodes']=not recorder.signature.hit_nodes.is_empty() and recorder.signature.hit_nodes.all(func(i):return not g.wheels.by_node.has(int(i)))
 checks[key+'_effects_in_all_frames']=data.frames.all(func(frame):return frame.has('effects') and frame.effects.has('glass') and frame.effects.has('interior'))
 checks[key+'_effect_inputs_fingerprinted']=data.metadata.input_sha256.has('vehicles/niva_glass.json') and data.metadata.input_sha256.has('vehicles/niva_interior.json')
 var valid:=true
 for path in data.metadata.input_sha256:valid=valid and data.metadata.input_sha256[path]==FileAccess.get_sha256('res://'+path)
 checks[key+'_input_fingerprints_match']=valid
 var path: String='res://verification/'+key+'_roof_roundtrip.crashclip'
 Clip.save(data,path)
 var loaded: Dictionary=Clip.read(path)
 var origin:=Vector3(data.metadata.origin[0],data.metadata.origin[1],data.metadata.origin[2])
 var max_error:=0.0;var discrete_match:=true
 for i in data.frames.size():
  Clip.apply(g,loaded,float(i)/120,origin)
  for j in g.points.size():max_error=maxf(max_error,g.points[j].distance_to(data.frames[i].points[j]+origin))
  var actual: Dictionary=g.capture()
  discrete_match=discrete_match and actual.broken==data.frames[i].broken
  if actual.has('effects'):
   for pane_id in data.frames[i].effects.glass.panes:
    var expected: Dictionary=data.frames[i].effects.glass.panes[pane_id]
    var got: Dictionary=actual.effects.glass.panes[pane_id]
    discrete_match=discrete_match and got.mask==expected.mask and got.stage==expected.stage
 checks[key+'_disk_replay_positions_match']=max_error<.00001
 checks[key+'_disk_replay_damage_effects_match']=discrete_match
 checks[key+'_replay_does_not_solve']=g.step_count==recorder.full_steps
 if name_=='roof_flat':checks[key+'_inverted_normal_y']=float(recorder.signature.normal[1])<-.999
 else:checks[key+'_corner_normal_has_pitch_roll']=absf(float(recorder.signature.normal[0]))+absf(float(recorder.signature.normal[2]))>.1
 runs.append({'case':name_,'quality':quality,'metadata':data.metadata,'maximum_replay_position_error_m':max_error,'frames':data.frames.size(),'bytes':FileAccess.get_file_as_bytes(path).size(),'glass_statistics':g.effects.glass.statistics(),'interior_capture':g.effects.interior.capture()})
 print('ROOF_AUTHORING_CASE ',key,' frames=',data.frames.size(),' gap=',recorder.first_contact_gap_m,' normal=',JSON.stringify(recorder.signature.normal),' cpu_ms=',recorder.cpu_us/1000.0)
func _run() -> void:
 utility_checks()
 var quality: int=4 if '--high-quality' in OS.get_cmdline_user_args() else 1
 for scenario in Recorder.CASES:record_case(scenario,quality)
 checks['all_cases_completed']=runs.size()==2
 var passed: bool=checks.values().all(func(value):return value)
 FileAccess.open('res://verification/roof_authoring_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':runs,'scope':'Ephemeral verification records only. Final roof bank must be authored after effects/runtime source freeze.'},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('ROOF_AUTHORING_VERIFIED ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
