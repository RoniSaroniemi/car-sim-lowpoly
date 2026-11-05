extends Node3D
const Geometry=preload('res://scripts/interior_geometry.gd')
var controller: RefCounted
var skin_view: Node3D
var seat_groups: Array=[]
var bag_view: MeshInstance3D
var bag_material: StandardMaterial3D
var original_node: MeshInstance3D
var original_mesh: Mesh
var split_triangles:=0
var original_triangles:=0
var last_revision:=-1

func setup(owner: RefCounted,view: Node3D,_model_root: Node3D) -> void:
 controller=owner;skin_view=view;name='InteriorSeatAndAirbagEffects'
 for record in view.records:
  var node: MeshInstance3D=record.node
  if node.name!='Niva_Interior_Static':continue
  original_node=node;original_mesh=node.mesh
  _extract_seats(node)
  break
 bag_view=MeshInstance3D.new();bag_view.name='OptionalSteeringAirbag'
 bag_material=StandardMaterial3D.new();bag_material.albedo_color=Color('#ddd4b6');bag_material.roughness=.96
 bag_material.cull_mode=BaseMaterial3D.CULL_DISABLED;bag_view.material_override=bag_material
 bag_view.extra_cull_margin=2;add_child(bag_view)

func _extract_seats(node: MeshInstance3D) -> void:
 var remaining:=ArrayMesh.new()
 var groups: Array=[]
 for i in 4:groups.append(ArrayMesh.new())
 for surface in original_mesh.get_surface_count():
  var source: Array=original_mesh.surface_get_arrays(surface)
  var result: Dictionary=Geometry.split_arrays(source)
  original_triangles+=int(result.source_triangles)
  var material: Material=original_mesh.surface_get_material(surface)
  var flag: int=original_mesh.surface_get_format(surface)&Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
  var kept: Array=result.arrays[0]
  if kept[Mesh.ARRAY_VERTEX]!=null:
   remaining.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,kept,[],{},flag)
   remaining.surface_set_material(remaining.get_surface_count()-1,material)
  for i in 4:
   var array: Array=result.arrays[i+1]
   if array[Mesh.ARRAY_VERTEX]==null:continue
   split_triangles+=int(result.triangle_counts[i+1])
   array[Mesh.ARRAY_BONES]=null;array[Mesh.ARRAY_WEIGHTS]=null
   groups[i].add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,array)
   groups[i].surface_set_material(groups[i].get_surface_count()-1,material)
 if split_triangles==0:return
 node.mesh=remaining
 for i in 4:
  if groups[i].get_surface_count()==0:continue
  var piece:=MeshInstance3D.new();piece.name=['DriverSeatBase','DriverSeatBack','PassengerSeatBase','PassengerSeatBack'][i]
  piece.mesh=groups[i];piece.extra_cull_margin=2;add_child(piece)
  seat_groups.append({'node':piece,'seat':i/2,'back':i%2==1})

func _process(_dt: float) -> void:
 if not is_instance_valid(skin_view):return
 visible=skin_view.mode!=0
 for record in seat_groups:
  var mount: Transform3D=controller.seat_mount(record.seat)
  if record.back:
   var p: Vector3=controller._vector(controller.config.seats[record.seat].pivot)
   var rotation:=Basis(Vector3.BACK,-controller.seats[record.seat].angle)
   record.node.transform=mount*Transform3D(rotation,p-rotation*p)
  else:record.node.transform=mount
 bag_view.visible=controller.airbag_enabled and controller.bag.triggered
 if not bag_view.visible:return
 bag_view.transform=controller.airbag_mount()
 var color:=Color('#ddd4b6') if skin_view.mode!=1 else Color('#959ca0')
 color.a=.14 if skin_view.mode==3 else 1
 bag_material.albedo_color=color
 bag_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA if skin_view.mode==3 else BaseMaterial3D.TRANSPARENCY_DISABLED
 if last_revision==controller.revision:return
 last_revision=controller.revision
 var vertices: PackedVector3Array=controller.bag.points.duplicate()
 var indices: PackedInt32Array=controller.bag.triangles
 var normals:=PackedVector3Array();normals.resize(vertices.size())
 for face in range(0,indices.size(),3):
  var a: int=indices[face];var b: int=indices[face+1];var c: int=indices[face+2]
  var n: Vector3=(vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
  normals[a]+=n;normals[b]+=n;normals[c]+=n
 for i in normals.size():normals[i]=normals[i].normalized()
 var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=indices
 var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);bag_view.mesh=mesh

func _exit_tree() -> void:
 # Restore original geometry if this adapter alone is removed/replaced.
 if is_instance_valid(original_node) and original_mesh!=null:original_node.mesh=original_mesh
