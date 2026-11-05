extends 'res://scripts/structural_skin.gd'
var panel_system: RefCounted
var panel_rigs: Dictionary={}
var source_triangles:=0
var panel_triangles:=0
var panel_weight_error:=0.0
var mesh_rebuilds:=0

func panel_id(name_: String) -> String:
 for id in ['door_left','door_right','bonnet','tailgate']:
  if name_.begins_with('Panel_'+id+'_'):return id
 if name_=='Glass_Door_Left':return 'door_left'
 if name_=='Glass_Door_Right':return 'door_right'
 if name_=='Glass_Rear':return 'tailgate'
 return ''

func _bind(node: MeshInstance3D) -> void:
 var id: String=panel_id(str(node.name))
 if id=='':super._bind(node);return
 _bind_panel(node,id)

func uv_for(p: Dictionary,point_: Vector3) -> Vector2:
 var u: float=clampf((.54-point_.x)/1.02,0,1) if p.side!=0 else (clampf((1.615-point_.x)/1.03,0,1) if p.id=='bonnet' else clampf((1.78-point_.y)/.8,0,1))
 var v: float=clampf((point_.y-.565)/(lerpf(1.22,1.72,minf(1,u*2))-.565),0,1) if p.side!=0 else clampf((point_.z+.79)/1.58,0,1) if p.id=='bonnet' else clampf((point_.z+.66)/1.32,0,1)
 return Vector2(u,v)

func node_frame(points: PackedVector3Array,index: int) -> Basis:
 index=4 if index==9 else index
 var u: int=index/3;var v: int=index%3
 var x: Vector3=(points[mini(2,u+1)*3+v]-points[maxi(0,u-1)*3+v]).normalized()
 var y: Vector3=(points[u*3+mini(2,v+1)]-points[u*3+maxi(0,v-1)]).normalized()
 y=(y-x*x.dot(y)).normalized()
 if x.length()<.5 or y.length()<.5:return Basis.IDENTITY
 var z: Vector3=x.cross(y).normalized()
 return Basis(x,z.cross(x).normalized(),z)

func _bind_panel(node: MeshInstance3D,id: String) -> void:
 var p: Dictionary=panel_system.find(id)
 if not panel_rigs.has(id):
  var rig:=Skeleton3D.new();rig.name='Deformable_'+id;add_child(rig)
  var frames: Array=[]
  for i in 10:
   rig.add_bone('Cage_'+str(i));rig.set_bone_rest(i,Transform3D(Basis.IDENTITY,p.rest[i]));frames.append(node_frame(p.rest,i))
  panel_rigs[id]={'skeleton':rig,'skin':rig.create_skin_from_rest_transforms(),'frames':frames,'meshes':[]}
 var rig: Dictionary=panel_rigs[id]
 var bind: Transform3D=global_transform.affine_inverse()*node.global_transform
 var source: Mesh=node.mesh;var mesh:=ArrayMesh.new()
 for surface in source.get_surface_count():
  var arrays: Array=source.surface_get_arrays(surface).duplicate(true)
  var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
  var tangents: PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
  for i in positions.size():
   positions[i]=bind*positions[i];normals[i]=(bind.basis*normals[i]).normalized()
   if not tangents.is_empty():
    var t: Vector3=(bind.basis*Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2])).normalized()
    tangents[i*4]=t.x;tangents[i*4+1]=t.y;tangents[i*4+2]=t.z
  arrays[Mesh.ARRAY_VERTEX]=positions;arrays[Mesh.ARRAY_NORMAL]=normals
  if not tangents.is_empty():arrays[Mesh.ARRAY_TANGENT]=tangents
  var original_indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
  source_triangles+=original_indices.size()/3 if not original_indices.is_empty() else positions.size()/3
  if not str(node.name).begins_with('Glass_'):arrays=_refine(arrays)
  positions=arrays[Mesh.ARRAY_VERTEX]
  var bones:=PackedInt32Array();var weights:=PackedFloat32Array()
  for point_ in positions:
   var uv: Vector2=uv_for(p,point_)*2
   var u: int=mini(1,floori(uv.x));var v: int=mini(1,floori(uv.y));var a: float=uv.x-u;var b: float=uv.y-v
   bones.append_array(PackedInt32Array([u*3+v,u*3+v+1,(u+1)*3+v,(u+1)*3+v+1]))
   var w:=PackedFloat32Array([(1-a)*(1-b),(1-a)*b,a*(1-b),a*b]);weights.append_array(w)
   panel_weight_error=maxf(panel_weight_error,absf(w[0]+w[1]+w[2]+w[3]-1))
  arrays[Mesh.ARRAY_BONES]=bones;arrays[Mesh.ARRAY_WEIGHTS]=weights
  mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  var material: Material=source.surface_get_material(surface)
  if not str(node.name).begins_with('Glass_'):
   material=_damage_material(material,arrays[Mesh.ARRAY_COLOR]!=null,false)
  mesh.surface_set_material(surface,material)
  var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
  panel_triangles+=indices.size()/3 if not indices.is_empty() else positions.size()/3
 node.reparent(body,false);node.transform=Transform3D.IDENTITY;node.mesh=mesh;node.skin=rig.skin;node.skeleton=node.get_path_to(rig.skeleton);node.extra_cull_margin=24
 rig.meshes.append(node)

func update_pose() -> void:
 super.update_pose()
 if panel_system==null:return
 panel_system.synchronize_inactive()
 for id in panel_rigs:
  var p: Dictionary=panel_system.find(id);var rig: Dictionary=panel_rigs[id]
  for i in 10:
   rig.skeleton.set_bone_pose_position(i,p.points[i])
   rig.skeleton.set_bone_pose_rotation(i,(node_frame(p.points,i)*rig.frames[i].inverse()).get_rotation_quaternion())
  rig.skeleton.force_update_all_bone_transforms()
  for mesh in rig.meshes:mesh.visible=mode!=0

func panel_quality() -> Dictionary:
 var error:=0.0
 for id in panel_rigs:
  var p: Dictionary=panel_system.find(id);var rig: Dictionary=panel_rigs[id]
  for i in 10:error=maxf(error,rig.skeleton.get_bone_global_pose(i).origin.distance_to(p.points[i]))
 return {'max_anchor_error_m':error,'max_weight_error':panel_weight_error,'panel_triangles':panel_triangles,'source_panel_triangles':source_triangles,'panel_bones':panel_rigs.size()*10,'mesh_rebuilds_during_simulation':mesh_rebuilds,'glass_uses_panel_skeleton':panel_rigs.door_left.meshes.any(func(mesh):return str(mesh.name)=='Glass_Door_Left')}
