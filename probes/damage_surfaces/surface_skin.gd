extends 'res://scripts/structural_skin.gd'
const Field=preload('res://probes/damage_surfaces/surface_field.gd')
const SURFACE_SHADER=preload('res://probes/damage_surfaces/surface_layers.gdshader')
var field: RefCounted
var appearance: int=2 # 0 original,1 current seven-section shader,2 proposed layers
var normal_layer:=true
var paint_layer:=true
var roughness_layer:=true
var section_folds:=true
var masks_debug:=false
var collision_direction:=Vector3.RIGHT
var upload_us:=0
var surface_materials: Array=[]
var rest_attribute_bytes:=0
func setup(graph: RefCounted,model_path: String='res://assets/Niva_2121_LOD0.glb') -> void:
 field=Field.new();field.setup(graph)
 super.setup(graph,model_path)
func _bind(node: MeshInstance3D) -> void:
 super._bind(node)
 if not records[-1].folding or str(node.name).ends_with('_1'):return
 var source: Mesh=node.mesh
 var mesh:=ArrayMesh.new()
 for surface in source.get_surface_count():
  var arrays: Array=source.surface_get_arrays(surface).duplicate(true)
  var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
  var rest_data:=PackedFloat32Array();var normal_data:=PackedFloat32Array()
  for i in positions.size():
   rest_data.append_array(PackedFloat32Array([positions[i].x,positions[i].y,positions[i].z,1]))
   normal_data.append_array(PackedFloat32Array([normals[i].x,normals[i].y,normals[i].z,0]))
  arrays[Mesh.ARRAY_CUSTOM0]=rest_data
  arrays[Mesh.ARRAY_CUSTOM1]=normal_data
  rest_attribute_bytes+=(rest_data.size()+normal_data.size())*4
  var flags: int=Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
  mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},flags)
  var material: Material=source.surface_get_material(surface)
  mesh.surface_set_material(surface,material)
  surface_materials.append(material)
 node.mesh=mesh
func set_mode(value: int) -> void:
 super.set_mode(value)
 for material in surface_materials:
  material.shader=SURFACE_SHADER if appearance!=1 else shader
  material.set_shader_parameter('damage_enabled',appearance!=0 and detail_enabled)
  material.set_shader_parameter('view_mode',1 if mode==1 else 2)
 apply_layers()
func apply_layers() -> void:
 for material in surface_materials:
  material.set_shader_parameter('normal_layer',normal_layer)
  material.set_shader_parameter('paint_layer',paint_layer)
  material.set_shader_parameter('roughness_layer',roughness_layer)
  material.set_shader_parameter('section_folds',section_folds)
  material.set_shader_parameter('masks_debug',masks_debug)
  material.set_shader_parameter('collision_direction',collision_direction)
func update_pose() -> void:
 super.update_pose()
 if field==null:return
 var began: int=Time.get_ticks_usec();field.update()
 var heights:=PackedFloat32Array();var widths:=PackedFloat32Array()
 for value in solver.config.station_top_y:heights.append(value)
 for value in solver.config.station_half_width:widths.append(value)
 for material in surface_materials:
  material.set_shader_parameter('node_damage',field.damage)
  material.set_shader_parameter('node_contact',field.contact)
  material.set_shader_parameter('node_compression',field.compression)
  material.set_shader_parameter('section_height',heights)
  material.set_shader_parameter('section_width',widths)
 upload_us+=Time.get_ticks_usec()-began
