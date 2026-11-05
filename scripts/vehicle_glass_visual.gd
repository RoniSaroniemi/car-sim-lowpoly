extends Node3D
const Attachment=preload('res://scripts/car_attachment.gd')
const GLASS_SHADER=preload('res://scripts/vehicle_glass.gdshader')
var owner_ref: WeakRef
var skin_ref: WeakRef
var records: Dictionary={}
var zero_offsets:=PackedVector3Array()
func setup(controller: RefCounted,skin_view: Node3D,model_root: Node3D) -> void:
 owner_ref=weakref(controller);skin_ref=weakref(skin_view)
 zero_offsets.resize(117);zero_offsets.fill(Vector3.ZERO)
 for id in controller.panes:
  var pane: Dictionary=controller.panes[id]
  var found: Array=model_root.find_children(pane.raw.mesh_name,'MeshInstance3D',true,false)
  if found.is_empty():continue
  var node: MeshInstance3D=found[0]
  var mesh:=ArrayMesh.new()
  var raw: Dictionary=pane.raw
  var origin:=Vector3(raw.origin[0],raw.origin[1],raw.origin[2]);var u:=Vector3(raw.u_axis[0],raw.u_axis[1],raw.u_axis[2]);var v:=Vector3(raw.v_axis[0],raw.v_axis[1],raw.v_axis[2])
  for surface in node.mesh.get_surface_count():
   var arrays: Array=node.mesh.surface_get_arrays(surface).duplicate(true)
   var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var uv:=PackedVector2Array()
   for p in positions:
    var local: Vector3=p-origin
    uv.append(Vector2((local.dot(u)-float(raw.uv_bounds[0]))/float(raw.width_m),(local.dot(v)-float(raw.uv_bounds[2]))/float(raw.height_m)))
   arrays[Mesh.ARRAY_TEX_UV]=uv
   mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
  node.mesh=mesh;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  var material:=ShaderMaterial.new();material.shader=GLASS_SHADER
  var image:=Image.create(40,13,false,Image.FORMAT_R8);image.fill(Color.WHITE)
  var texture:=ImageTexture.create_from_image(image)
  material.set_shader_parameter('cell_mask',texture);material.set_shader_parameter('membrane_offsets',zero_offsets)
  material.set_shader_parameter('aspect',float(raw.width_m)/float(raw.height_m))
  var edge_image:=Image.create(64,32,false,Image.FORMAT_R8)
  for y in 32:
   for x in 64:
    var distance: float=controller._edge_distance(pane,Vector2((x+.5)/64.0,(y+.5)/32.0))
    var weight: float=smoothstep(.04,.14,distance)
    edge_image.set_pixel(x,y,Color(weight,weight,weight))
  material.set_shader_parameter('frame_weight',ImageTexture.create_from_image(edge_image))
  node.material_override=material
  records[id]={'node':node,'material':material,'texture':texture,'image':image,'revision':-1}
 var particles:=MultiMeshInstance3D.new();particles.name='GlassFragments'
 var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D
 var triangle:=ArrayMesh.new();var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-1,-.7,0),Vector3(.8,-.4,0),Vector3(.1,1,0)])
 arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK]);triangle.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 multi.mesh=triangle;multi.instance_count=192;multi.visible_instance_count=0;particles.multimesh=multi
 var mat:=StandardMaterial3D.new();mat.albedo_color=Color('#a8c8cf');mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.cull_mode=BaseMaterial3D.CULL_DISABLED;particles.material_override=mat
 add_child(particles);particles.top_level=true
func _process(_dt: float) -> void:update_visual()
func update_visual() -> void:
 var controller: RefCounted=owner_ref.get_ref();var skin: Node3D=skin_ref.get_ref()
 if controller==null or skin==null:return
 var graph: RefCounted=controller.graph.get_ref()
 if graph==null:return
 var frames: Array=Attachment.rotations(graph)
 for id in records:
  var pane: Dictionary=controller.panes[id];var record: Dictionary=records[id]
  var material: ShaderMaterial=record.material
  material.set_shader_parameter('crack',pane.crack);material.set_shader_parameter('seed',float(pane.seed));material.set_shader_parameter('hit_uv',pane.hit_uv)
  material.set_shader_parameter('ghost',1.0 if skin.mode==3 else 0.0)
  if record.revision!=pane.mask_revision:
   for i in pane.mask.size():record.image.set_pixel(i%40,i/40,Color.WHITE if pane.mask[i] else Color.BLACK)
   record.texture.update(record.image);record.revision=pane.mask_revision
  var active: bool=pane.nodes_local.size()==117
  material.set_shader_parameter('membrane_active',active)
  if active:
   var transform: Transform3D=controller._frame(pane,frames)
   var offsets:=PackedVector3Array()
   for i in pane.nodes_local.size():
    var base: Vector3=Attachment.mapped(graph,pane.node_rest[i],pane.node_bind[i],frames)
    # GLES3 skinning precedes the user vertex shader: VERTEX is already in
    # graph/model space. Applying an inverse bone rotation here detached panes.
    offsets.append(transform*pane.nodes_local[i]-base)
   material.set_shader_parameter('membrane_offsets',offsets)
 var particles: MultiMeshInstance3D=get_node('GlassFragments')
 particles.visible=skin.mode!=0
 var multi: MultiMesh=particles.multimesh;multi.visible_instance_count=controller.debris.size()
 for i in controller.debris.size():
  var piece: Dictionary=controller.debris[i]
  multi.set_instance_transform(i,Transform3D(Basis.from_euler(piece.rotation).scaled(Vector3.ONE*piece.size),piece.position))
