extends SceneTree
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Driving=preload('res://scripts/driving_vehicle.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Surface=preload('res://scripts/vehicle_surface.gd')
const SkinView=preload('res://scripts/damage_skin.gd')
var checks: Dictionary={}
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var car:=Vehicle.new();car.setup();var g: RefCounted=car.solver
 var surface: RefCounted=g.effects.surface
 var legacy: Dictionary=Clip.read('res://bakes/impact_030_60.crashclip')
 checks['legacy_provenance_compatible']=Clip.input_compatibility(legacy).compatible
 var physical:=var_to_bytes(g.points);Clip.prepare_surfaces(g,legacy)
 checks['precompute_does_not_touch_graph']=physical==var_to_bytes(g.points) and surface.marks.is_empty()
 Clip.apply(g,legacy,1.,Vector3(13,2,-7),Basis(Vector3.UP,.7))
 var state: Dictionary=surface.capture();var poses:=var_to_bytes(g.points)
 checks['legacy_restores_damage_and_footprints']=not state.marks.is_empty() and Array(state.compression).max()>.1
 for time_ in [.1,2.,0.,.75,1.]:Clip.apply(g,legacy,time_,Vector3(13,2,-7),Basis(Vector3.UP,.7))
 checks['arbitrary_seeking_deterministic']=var_to_bytes(state)==var_to_bytes(surface.capture()) and poses==var_to_bytes(g.points)
 Clip.apply(g,legacy,0.,Vector3.ZERO)
 checks['seek_before_impact_clears_future_marks']=surface.marks.is_empty()
 Clip.apply(g,legacy,1.,Vector3.ZERO)
 var frame: Dictionary=g.capture()
 var recorded: Dictionary={'metadata':{'id':'surface_roundtrip','duration_s':1.,'sample_hz':1.,'signature':{'normal':[-1,0,0]},'input_sha256':{}},'frames':[frame,frame.duplicate(true)]}
 Clip.save(recorded,'res://verification/surface_roundtrip.crashclip',false)
 var disk: Dictionary=Clip.read('res://verification/surface_roundtrip.crashclip')
 checks['new_clip_has_versioned_surface']=disk.metadata.surface_schema==1 and disk.frames[0].effects.surface.version==1 and disk.metadata.surface_input_sha256.has('vehicles/niva_surface.json')
 checks['derived_cache_not_saved']=not disk.has('_surface_track')
 var expected: Dictionary=surface.capture();surface.reset();Clip.apply(g,disk,0.,Vector3.ZERO)
 var invalid: Dictionary=disk.duplicate(true);invalid.erase('_surface_track');invalid.frames[0].effects.surface.version=999
 checks['future_surface_schema_rejected']=not Clip.prepare_surfaces(g,invalid)
 var invalid_fields: Dictionary=disk.duplicate(true);invalid_fields.erase('_surface_track');invalid_fields.frames[0].effects.surface.compression=PackedFloat32Array([0.])
 checks['malformed_surface_state_rejected']=not Clip.prepare_surfaces(g,invalid_fields)
 checks['new_surface_state_exact_disk_roundtrip']=var_to_bytes(surface.capture())==var_to_bytes(expected)
 var before:=var_to_bytes(surface.capture());g.effects.resume_live()
 checks['resume_live_keeps_material_state']=surface.damage==expected.damage and surface.marks==expected.marks and surface.active_mark==''
 var skin:=Node3D.new();skin.set_script(SkinView);root.add_child(skin);skin.setup(g);skin.show_frame=false;skin.set_mode(2)
 checks['native_binding_preserved']=skin.binding_quality().maximum_weight_sum_error<.00001 and skin.skeleton.get_bone_count()==39
 var attrs:=true
 for record in skin.records:
  if not record.folding or str(record.node.name).ends_with('_1'):continue
  for index in record.node.mesh.get_surface_count():
   var a: Array=record.node.mesh.surface_get_arrays(index)
   for v in a[Mesh.ARRAY_VERTEX].size():
    var data: PackedFloat32Array=a[Mesh.ARRAY_CUSTOM0]
    attrs=attrs and Vector3(data[v*4],data[v*4+1],data[v*4+2]).distance_to(a[Mesh.ARRAY_VERTEX][v])<.00001
 checks['full_3d_rest_attributes']=attrs
 var mesh: Mesh=skin.records[0].node.mesh
 for iteration in 20:skin.update_pose()
 checks['no_update_time_topology_rebuild']=skin.records[0].node.mesh==mesh
 skin.detail_enabled=false;skin.set_mode(1)
 checks['plain_geometry_disables_displacement']=skin.surface_materials.all(func(mat):return not mat.get_shader_parameter('damage_enabled'))
 checks['non_body_materials_keep_ownership']=skin.records.all(func(record):return record.folding or record.materials.all(func(mat):return not mat is ShaderMaterial or not mat.get_shader_parameter('damage_enabled')))
 checks['sampling_and_rendering_never_solve']=g.step_count==0 and g.effects.glass.membrane_solve_steps==0 and g.effects.interior.cloth_steps==0
 # Overflow grows support around an existing fixed centre, retaining every old
 # sampled mask influence instead of dropping earlier impact marks.
 surface.reset()
 for i in 8:surface._merge_mark({'id':str(i),'center':Vector3(i*.2,1.,0),'radii':Vector3.ONE*.6,'strength':.5,'direction':Vector3.RIGHT})
 var old_marks: Array=surface.marks.duplicate(true)
 surface._merge_mark({'id':'overflow','center':Vector3(1.8,1.,0),'radii':Vector3.ONE*.6,'strength':1.,'direction':Vector3.RIGHT})
 var retains: bool=surface.marks.size()==8
 for old in old_marks:
  var current: Dictionary=surface.marks.filter(func(mark):return mark.id==old.id)[0]
  retains=retains and current.center==old.center and current.radii.x>=old.radii.x and current.radii.y>=old.radii.y and current.radii.z>=old.radii.z and current.strength>=old.strength
 checks['bounded_overflow_does_not_drop_prior_damage']=retains
 # Real driving -> three clips -> driving -> repair, without effects solvers.
 var driver:=Driving.new();driver.setup();driver.solver.barrier_min=Vector3(40,0,-8);driver.solver.barrier_max=Vector3(41,3,8);driver.start_baked_sequence()
 var old_nodes:=PackedFloat32Array();old_nodes.resize(38);var persists:=true;var snapshots: Array=[]
 for step in 1800:
  driver.advance(1./120.)
  var fx: RefCounted=driver.solver.effects.surface
  for node in 38:persists=persists and fx.damage[node]+.00001>=old_nodes[node]
  old_nodes=fx.damage.duplicate()
  if driver.last_bake.get('completed',false) and snapshots.size()<driver.baked_count:snapshots.append(fx.capture())
  if driver.baked_count==3 and driver.last_bake.get('completed',false):break
 # Multiple hits can grow the same bounded footprint. Check preservation and
 # progression of the actual damage instead of requiring one mark per hit.
 var footprint_retained: bool=snapshots.size()==3
 var footprint_progresses:=true
 for i in range(1,snapshots.size()):
  var changed:=false
  for old in snapshots[i-1].marks:
   var matches: Array=snapshots[i].marks.filter(func(mark):return mark.id==old.id)
   if matches.is_empty():footprint_retained=false;continue
   var current: Dictionary=matches[0]
   footprint_retained=footprint_retained and current.center==old.center and current.radii.x>=old.radii.x and current.radii.y>=old.radii.y and current.radii.z>=old.radii.z and current.strength>=old.strength
   changed=changed or current.radii.distance_to(old.radii)>.00001 or current.strength>old.strength+.00001
  footprint_progresses=footprint_progresses and (changed or snapshots[i].marks.size()>snapshots[i-1].marks.size())
 checks['conditioned_sequence_keeps_surface_damage']=persists and driver.baked_count==3 and footprint_retained and footprint_progresses and not driver.solver.effects.surface.marks.is_empty()
 var retained: Dictionary=driver.solver.effects.surface.capture()
 for step in 120:driver.advance(1./120.)
 checks['resumed_driving_keeps_surface_exact']=var_to_bytes(retained)==var_to_bytes(driver.solver.effects.surface.capture())
 checks['sequence_keeps_zero_full_or_effect_solves']=driver.full_steps==0 and driver.solver.step_count==0 and driver.solver.effects.glass.membrane_solve_steps==0 and driver.solver.effects.interior.cloth_steps==0
 driver.reset();checks['repair_clears_all_layers']=driver.solver.effects.surface.marks.is_empty() and Array(driver.solver.effects.surface.damage).max()==0. and Array(driver.solver.effects.surface.compression).max()==0.
 # Compatibility is an exact receipt, not a blanket source-file exemption.
 var corrupt: Dictionary=legacy.duplicate(true);corrupt.metadata.input_sha256['scripts/vehicle_effects.gd']='unrecognized'
 checks['unrecognized_adapter_revision_rejected']=not Clip.input_compatibility(corrupt).compatible
 corrupt=legacy.duplicate(true);corrupt.metadata.input_sha256['structure.json']='changed'
 checks['physical_source_changes_rejected']=not Clip.input_compatibility(corrupt).compatible
 var passed: bool=checks.values().all(func(value):return value)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification'))
 FileAccess.open('res://verification/vehicle_surface_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'render_triangles':skin.mesh_triangles,'rest_attribute_bytes':skin.rest_attribute_bytes,'scope':'Native skin/lifecycle/legacy and new clip replay/real driving sequence; shader appearance separately rendered.'},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('VEHICLE_SURFACE_VERIFIED ',passed,' checks=',checks.size())
 skin.queue_free();quit(0 if passed else 1)
