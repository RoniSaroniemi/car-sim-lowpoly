extends SceneTree
var checks: Dictionary={}
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var studio: Control=load('res://probes/damage_studio/studio.tscn').instantiate();root.add_child(studio)
 checks['oblique_impact_stays_on_contact_side']=studio.views[4].impact_center.z>.4 and studio.views[4].impact_center.x>1.
 checks['roof_impact_uses_roof_contact']=studio.views[8].impact_center.y>1.5 and studio.views[8].impact_center.z<0.
 checks['light_displacement_stays_restrained']=studio.views[0].impact_strength==0. and studio.views[1].impact_strength<.1 and studio.views[4].impact_strength>.5
 checks['studio_has_displacement_vertices']=studio.views[0].skin.mesh_triangles>39673
 checks['nine_real_frozen_cases']=studio.views.size()==9 and studio.stats.size()==9
 var poses: Array=[];var fields: Array=[];var cameras: Array=[]
 for view in studio.views:
  poses.append(var_to_bytes(view.car.solver.capture()));fields.append(view.skin.field.updates);cameras.append(view.camera.transform)
 for index in 9:
  var event:=InputEventKey.new();event.pressed=true;event.physical_keycode=KEY_1+index;studio._unhandled_key_input(event)
  checks['key_focus_%d'%[index+1]]=studio.selected==index and studio.focus.visible and studio.focus.texture==studio.views[index].viewport.get_texture()
 studio.select_case(-1)
 checks['board_camera_registration_stable']=true
 for index in 9:checks['board_camera_registration_stable']=checks['board_camera_registration_stable'] and cameras[index]==studio.views[index].camera.transform
 studio.preset['paint_loss']=.37;studio.apply_materials()
 checks['shared_parameters_reach_all_nine']=studio.views.all(func(view):return view.skin.surface_materials.all(func(mat):return is_equal_approx(mat.get_shader_parameter('paint_loss'),.37)))
 studio.layers['masks_debug']=true;studio.layers['section_folds']=false;studio.apply_materials()
 checks['mask_toggle_survives_upload']=studio.views.all(func(view):return view.skin.surface_materials.all(func(mat):return mat.get_shader_parameter('masks_debug')))
 checks['fold_toggle_survives_upload']=studio.views.all(func(view):return view.skin.surface_materials.all(func(mat):return not mat.get_shader_parameter('section_folds')))
 studio.layers['masks_debug']=false;studio.layers['section_folds']=true
 studio.previous_variant=true;studio.apply_materials()
 checks['previous_variant_available']=studio.views.all(func(view):return view.skin.surface_materials.all(func(mat):return mat.shader==view.skin.PREVIOUS_SHADER))
 studio.previous_variant=false
 studio.plain=true;studio.apply_materials()
 checks['plain_disables_damage']=studio.views.all(func(view):return view.skin.surface_materials.all(func(mat):return not mat.get_shader_parameter('damage_enabled') and mat.get_shader_parameter('view_mode')==1))
 studio.plain=false;studio.appearance=1;studio.apply_materials()
 checks['baseline_uses_original_shader']=studio.views.all(func(view):return view.skin.surface_materials.all(func(mat):return mat.shader==view.skin.shader))
 studio.appearance=2;studio.apply_materials()
 studio.preset_name.text='_check_roundtrip';studio.save_preset();studio.preset['paint_loss']=1.9;studio.load_preset()
 checks['non_body_surfaces_keep_damage_disabled']=studio.views.all(func(view):return view.skin.records.all(func(record):return record.folding or record.materials.all(func(mat):return not mat is ShaderMaterial or not mat.get_shader_parameter('damage_enabled'))))
 checks['named_preset_roundtrip']=is_equal_approx(studio.preset.paint_loss,.37)
 DirAccess.remove_absolute(ProjectSettings.globalize_path(studio.HOME+'presets/_check_roundtrip.json'))
 checks['updates_do_not_resample_or_solve']=true
 for index in 9:
  var view: Dictionary=studio.views[index];var graph: RefCounted=view.car.solver
  checks['updates_do_not_resample_or_solve']=checks['updates_do_not_resample_or_solve'] and poses[index]==var_to_bytes(graph.capture()) and fields[index]==view.skin.field.updates and graph.step_count==0 and graph.effects.glass.membrane_solve_steps==0 and graph.effects.interior.cloth_steps==0
 var passed: bool=checks.values().all(func(value):return value)
 FileAccess.open(studio.HOME+'captures/checks.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks},'\t'))
 print('STUDIO_CHECKS ',JSON.stringify(checks));quit(0 if passed else 1)
