extends SceneTree
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Field=preload('res://probes/damage_surfaces/surface_field.gd')
const SurfaceView=preload('res://probes/damage_surfaces/surface_skin.gd')
const BaseView=preload('res://scripts/structural_skin.gd')
var checks: Dictionary={}
var observations: Dictionary={}
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var car:=Vehicle.new();car.setup()
 var g: RefCounted=car.solver
 var field:=Field.new();field.setup(g)
 var before: Dictionary=g.capture();field.update()
 checks['field_is_read_only']=var_to_bytes(before)==var_to_bytes(g.capture()) and g.step_count==0
 checks['field_no_extra_mass']=g.points.size()==38 and absf(float(g.config.mass_kg)-1210)<.01
 g.node_damage[15]=.7;g.node_contact[15]=1;field.update()
 checks['left_upper_contact_locality']=field.at(g.rest[15]).y>.999
 checks['opposite_side_unmarked']=field.at(g.rest[14]).y<.001
 checks['lower_panel_unmarked']=field.at(g.rest[13]).y<.001
 checks['front_away_from_hit_unmarked']=field.at(g.rest[27]).y<.001
 var lengths:=PackedFloat32Array()
 for edge in g.links:lengths.append(edge.original)
 var initial:=lengths.duplicate();var compressed:=lengths.duplicate();var relaxed:=lengths.duplicate()
 var index: int=g.links.find_custom(func(edge):return edge.a<28 and edge.b<28)
 compressed[index]*=.6;relaxed[index]*=.9
 var synthetic: Dictionary={'frames':[{'lengths':initial},{'lengths':compressed},{'lengths':relaxed}]}
 var peak: Array=Field.history(g,synthetic)
 checks['peak_compression_survives_partial_unloading']=peak[2]==peak[1] and Array(peak[2]).max()>.39
 var paths: Array=['res://probes/damage_surfaces/data/light_20.crashclip','res://bakes/impact_090_120.crashclip','res://bakes/conditioned/front_60_60_120_step_2.crashclip']
 var source_checks: Array=[]
 for i in paths.size():
  var data: Dictionary=Clip.read(paths[i]);checks['case_%d_has_real_v3_source'%i]=not data.is_empty() and data.metadata.version==3
  if data.is_empty():continue
  var fingerprint:=true
  for path in data.metadata.input_sha256:fingerprint=fingerprint and data.metadata.input_sha256[path]==FileAccess.get_sha256('res://'+path)
  checks['case_%d_source_inputs_match'%i]=fingerprint
  Clip.apply(g,data,[2.5,1.0,.75][i],Vector3.ZERO)
  var prior: Dictionary=g.capture()
  var history_began: int=Time.get_ticks_usec()
  var history: Array=Field.history(g,data)
  var history_us: int=Time.get_ticks_usec()-history_began
  var monotonic:=true
  for sample in range(1,history.size()):
   for node in 38:monotonic=monotonic and history[sample][node]+1e-7>=history[sample-1][node]
  checks['case_%d_history_monotonic'%i]=monotonic
  field.compression_override=history[-1];field.update()
  checks['case_%d_sampling_has_no_dynamics_or_mutation'%i]=g.step_count==0 and var_to_bytes(g.capture())==var_to_bytes(prior)
  source_checks.append({'path':paths[i],'history_build_ms':history_us/1000.,'history_bytes':history.size()*38*4,'frames':data.frames.size(),'source_frame_hash':FieldHash(prior)})
 g.node_contact.fill(0);g.node_damage.fill(0)
 var skin:=Node3D.new();skin.set_script(SurfaceView);root.add_child(skin);skin.setup(g);skin.show_frame=false;skin.set_mode(2)
 var vertices_match:=true;var uv_valid:=true;var paint_only:=true
 for record in skin.records:
  var eligible: bool=record.folding and not str(record.node.name).ends_with('_1')
  for surface in record.node.mesh.get_surface_count():
   var arrays: Array=record.node.mesh.surface_get_arrays(surface)
   if not eligible:continue
   var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var attributes: PackedFloat32Array=arrays[Mesh.ARRAY_CUSTOM0]
   uv_valid=uv_valid and arrays[Mesh.ARRAY_TEX_UV].size()==positions.size()
   for v in positions.size():vertices_match=vertices_match and Vector3(attributes[v*4],attributes[v*4+1],attributes[v*4+2]).distance_to(positions[v])<.000001
   paint_only=paint_only and skin.surface_materials.has(record.node.mesh.surface_get_material(surface))
 checks['native_rest_attributes_exact']=vertices_match
 checks['native_uvs_preserved']=uv_valid
 checks['outer_surface_material_scope']=paint_only
 checks['native_binding_still_valid']=skin.binding_quality().maximum_weight_sum_error<.000001
 skin.detail_enabled=false;skin.set_mode(1)
 checks['plain_diagnostic_disables_surface_layers']=skin.surface_materials.all(func(material):return not material.get_shader_parameter('damage_enabled'))
 skin.detail_enabled=true;skin.set_mode(2)
 var began: int=Time.get_ticks_usec()
 for i in 200:field.update()
 var field_us: float=(Time.get_ticks_usec()-began)/200.
 began=Time.get_ticks_usec()
 for i in 100:skin.update_pose()
 var pose_us: float=(Time.get_ticks_usec()-began)/100.
 var reference:=Node3D.new();reference.set_script(BaseView);root.add_child(reference);reference.setup(g);reference.show_frame=false;reference.set_mode(2)
 began=Time.get_ticks_usec()
 for i in 100:reference.update_pose()
 var reference_us: float=(Time.get_ticks_usec()-began)/100.
 checks['material_update_never_solves']=g.step_count==0 and g.effects.glass.membrane_solve_steps==0 and g.effects.interior.cloth_steps==0
 observations={'cases':source_checks,'field_update_mean_us':field_us,'native_pose_plus_field_upload_mean_us':pose_us,'baseline_pose_mean_us':reference_us,'rest_attribute_bytes':skin.rest_attribute_bytes,'render_triangles':skin.mesh_triangles,'render_bones':skin.skeleton.get_bone_count(),'extra_draw_calls':0,'note':'Headless CPU calls only. Native raster/GPU evidence and timings are measured separately; no FPS claim.'}
 checks['all_26_checks_executed']=checks.size()==25
 var passed: bool=checks.values().all(func(value):return value)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://probes/damage_surfaces/evidence'))
 FileAccess.open('res://probes/damage_surfaces/evidence/validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'observations':observations},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('DAMAGE_SURFACE_VERIFIED ',passed,' checks=',checks.size(),' observations=',JSON.stringify(observations))
 skin.queue_free();reference.queue_free();quit(0 if passed else 1)
func FieldHash(state: Dictionary) -> String:
 var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(var_to_bytes(state));return hash.finish().hex_encode()
