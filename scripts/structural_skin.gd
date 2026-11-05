extends Node3D
var solver: RefCounted
var skeleton: Skeleton3D
var skin: Skin
var body: Node3D
var records: Array[Dictionary]=[]
var materials: Array[ShaderMaterial]=[]
var frame_lines: MeshInstance3D
var node_instances: MultiMeshInstance3D
var engine_visual: MeshInstance3D
var wheel_visuals: Array[Node3D]=[]
var bone_frames: Array[Basis]=[]
var engine_rest_frame: Basis
var engine_rest_center: Vector3
var mode := 0
var show_frame := true
var detail_enabled := true
var build_ms := 0.0
var max_weight_error:=0.0
var mesh_triangles := 0
var max_upload_us := 0
var shader: Shader
var ghost_shader: Shader
var last_material_damage := PackedFloat32Array()
var bone_rest := PackedVector3Array()

func setup(graph: RefCounted,model_path: String='res://assets/Niva_2121_LOD0.glb') -> void:
 var began: int=Time.get_ticks_usec()
 solver=graph
 shader=load('res://scripts/damage_surface.gdshader')
 ghost_shader=Shader.new()
 ghost_shader.code=shader.code.replace('// GHOST_ALPHA','ALPHA = 0.14;')
 skeleton=Skeleton3D.new()
 skeleton.name='DeformableBodyStructure'
 add_child(skeleton)
 bone_rest=solver.rest.duplicate()
 engine_rest_center=_engine_center(true)
 bone_rest.append(engine_rest_center)
 for i in bone_rest.size():
  skeleton.add_bone('Structure_'+str(i))
  skeleton.set_bone_rest(i,Transform3D(Basis.IDENTITY,bone_rest[i]))
 skin=skeleton.create_skin_from_rest_transforms()
 for s in 7:
  bone_frames.append(_station_frame(s,true))
 engine_rest_frame=_engine_frame(true)
 body=load(model_path).instantiate()
 add_child(body)
 var nodes: Array[Node]=body.find_children('*','MeshInstance3D',true,false)
 for node in nodes:
  _bind(node as MeshInstance3D)
 for node in body.find_children('*','AnimationPlayer',true,false):
  node.queue_free()
 _make_frame()
 update_pose()
 set_mode(0)
 build_ms=(Time.get_ticks_usec()-began)/1000.0
 if solver.effects!=null:solver.effects.bind_visual(self,body)
 print('STRUCTURE_SKIN_READY triangles=',mesh_triangles,' build_ms=',build_ms)

func _station_frame(s: int,original: bool=false) -> Basis:
 var positions: PackedVector3Array=solver.rest if original else solver.points
 var prev: int=maxi(0,s-1)
 var next: int=mini(6,s+1)
 var a: Vector3=(positions[prev*4]+positions[prev*4+1]+positions[prev*4+2]+positions[prev*4+3])*0.25
 var b: Vector3=(positions[next*4]+positions[next*4+1]+positions[next*4+2]+positions[next*4+3])*0.25
 var x: Vector3=(b-a).normalized()
 var z: Vector3=((positions[s*4+1]+positions[s*4+3])-(positions[s*4]+positions[s*4+2])).normalized()
 z=(z-x*x.dot(z)).normalized()
 if x.length()<0.01 or z.length()<0.01:
  return Basis.IDENTITY
 var y: Vector3=z.cross(x).normalized()
 z=x.cross(y).normalized()
 return Basis(x,y,z)

func _engine_center(original: bool=false) -> Vector3:
 var positions: PackedVector3Array=solver.rest if original else solver.points
 var p:=Vector3.ZERO
 for i in solver.config.engine_nodes:
  p+=positions[i]
 return p/4.0

func _engine_frame(original: bool=false) -> Basis:
 var positions: PackedVector3Array=solver.rest if original else solver.points
 var indices: Array=solver.config.engine_nodes
 var x: Vector3=(positions[indices[1]]-positions[indices[0]]).normalized()
 var z: Vector3=(positions[indices[2]]-positions[indices[0]]).normalized()
 z=(z-x*z.dot(x)).normalized()
 var y: Vector3=z.cross(x).normalized()
 return Basis(x,y,x.cross(y).normalized())

func _bone_weights(p: Vector3,wheel: int,engine: bool) -> Array:
 if wheel>=0:
  return [[wheel,0,0,0,0,0,0,0],[1.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]]
 if engine:
  return [[bone_rest.size()-1,0,0,0,0,0,0,0],[1.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]]
 var s:=0
 for i in 6:
  if p.x>=float(solver.config.station_x[i]):
   s=i
 var x0: float=solver.config.station_x[s]
 var x1: float=solver.config.station_x[s+1]
 var t: float=clampf((p.x-x0)/(x1-x0),0,1)
 var ids: Array=[]
 var weights: Array=[]
 for q in 2:
  var station: int=s+q
  var ty: float=clampf((p.y-0.58)/(float(solver.config.station_top_y[station])-0.58),0,1)
  var width: float=solver.config.station_half_width[station]
  var tz: float=clampf((p.z+width)/(2*width),0,1)
  for j in 4:
   ids.append(station*4+j)
   var high: bool=j>=2
   var positive: bool=j%2==1
   weights.append((t if q==1 else 1-t)*(ty if high else 1-ty)*(tz if positive else 1-tz))
 return [ids,weights]

func _bind(node: MeshInstance3D) -> void:
 var bind: Transform3D=global_transform.affine_inverse()*node.global_transform
 var source: Mesh=node.mesh
 var wheel: int=-1
 if str(node.name).begins_with('Wheel_'):
  var is_front: bool='Front' in str(node.name)
  var positive: bool='Left' in str(node.name)
  # Source naming uses Left for positive-Z. Preserve existing asset mapping.
  wheel=solver.config.wheel_nodes[(2 if is_front else 0)+(1 if positive else 0)]
 var mesh:=ArrayMesh.new()
 var original_materials: Array=[]
 var created: Array=[]
 for surface in source.get_surface_count():
  var arrays: Array=source.surface_get_arrays(surface)
  arrays=arrays.duplicate(true)
  var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
  var tangents: PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
  for i in vertices.size():
   vertices[i]=bind*vertices[i]
   normals[i]=(bind.basis*normals[i]).normalized()
   if not tangents.is_empty():
    var tangent: Vector3=(bind.basis*Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2])).normalized()
    tangents[i*4]=tangent.x
    tangents[i*4+1]=tangent.y
    tangents[i*4+2]=tangent.z
  arrays[Mesh.ARRAY_VERTEX]=vertices
  arrays[Mesh.ARRAY_NORMAL]=normals
  if not tangents.is_empty():arrays[Mesh.ARRAY_TANGENT]=tangents
  var folding: bool=(node.name=='Niva_Body_Static' or str(node.name).begins_with('Panel_')) and wheel<0
  if folding:
   arrays=_refine(arrays)
  vertices=arrays[Mesh.ARRAY_VERTEX]
  var bones:=PackedInt32Array()
  var weights:=PackedFloat32Array()
  var uv2:=PackedVector2Array()
  var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
  var had_colors: bool=not colors.is_empty()
  if not had_colors:
   colors.resize(vertices.size())
   colors.fill(Color.WHITE)
  for i in vertices.size():
   var p: Vector3=vertices[i]
   var engine: bool=node.name=='Niva_Interior_Static' and p.x>0.70 and p.x<1.32 and p.y>0.73 and p.y<1.09 and absf(p.z)<0.39
   var bw: Array=_bone_weights(p,wheel,engine)
   var weight_sum:=0.0
   for weight in bw[1]:weight_sum+=weight
   max_weight_error=maxf(max_weight_error,absf(weight_sum-1.0))
   for j in 8:
    bones.append(bw[0][j])
    weights.append(bw[1][j])
   uv2.append(Vector2(p.x,p.z))
   var mask:=0.0
   if folding:
    mask=smoothstep(0.86,1.08,p.y)
    mask*=0.75 if p.y>1.5 else 1.0
   colors[i].a=mask
  arrays[Mesh.ARRAY_BONES]=bones
  arrays[Mesh.ARRAY_WEIGHTS]=weights
  arrays[Mesh.ARRAY_TEX_UV2]=uv2
  arrays[Mesh.ARRAY_COLOR]=colors
  mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
  var original: Material=source.surface_get_material(surface)
  original_materials.append(original)
  var material: Material
  if str(node.name).begins_with('Glass_'):
   material=original
  else:
   material=_damage_material(original,had_colors,folding)
  mesh.surface_set_material(surface,material)
  created.append(material)
  var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
  mesh_triangles+=indices.size()/3 if not indices.is_empty() else vertices.size()/3
 node.reparent(body,false)
 node.transform=Transform3D.IDENTITY
 node.mesh=mesh
 node.skin=skin
 node.skeleton=node.get_path_to(skeleton)
 node.extra_cull_margin=24
 records.append({'node':node,'original_materials':original_materials,'materials':created,'folding':str(node.name).begins_with('Panel_') or node.name=='Niva_Body_Static'})

func _damage_material(source: Material,has_colors: bool,folding: bool) -> ShaderMaterial:
 var material:=ShaderMaterial.new()
 material.shader=shader
 if source is StandardMaterial3D:
  material.set_shader_parameter('tint',source.albedo_color)
  material.set_shader_parameter('albedo_map',source.albedo_texture)
  material.set_shader_parameter('has_albedo',source.albedo_texture!=null)
  material.set_shader_parameter('normal_map',source.normal_texture)
  material.set_shader_parameter('has_normal',source.normal_enabled and source.normal_texture!=null)
  material.set_shader_parameter('roughness_map',source.roughness_texture)
  material.set_shader_parameter('has_roughness',source.roughness_texture!=null)
  material.set_shader_parameter('roughness_value',source.roughness)
  material.set_shader_parameter('metallic_value',source.metallic)
 material.set_shader_parameter('vertex_tint',has_colors)
 material.set_shader_parameter('damage_enabled',folding)
 materials.append(material)
 return material

func _refine(arrays: Array) -> Array:
 # Targeted longest-edge subdivision at load time, preserving UVs and topology.
 var vp: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
 var np: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
 var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
 var cp: PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
 var tp: PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
 var idx: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
 if idx.is_empty():
  for i in vp.size():idx.append(i)
 var out:=PackedInt32Array()
 var cache: Dictionary={}
 for triangle in idx.size()/3:
  var stack: Array=[[idx[triangle*3],idx[triangle*3+1],idx[triangle*3+2],0]]
  while not stack.is_empty():
   var t: Array=stack.pop_back()
   var a: int=t[0];var b: int=t[1];var c: int=t[2];var depth: int=t[3]
   var centre: Vector3=(vp[a]+vp[b]+vp[c])/3
   var eligible: bool=centre.y>0.82 and centre.x>-1.55
   var lengths: Array=[vp[a].distance_squared_to(vp[b]),vp[b].distance_squared_to(vp[c]),vp[c].distance_squared_to(vp[a])]
   var longest: int=0
   if lengths[1]>lengths[longest]:longest=1
   if lengths[2]>lengths[longest]:longest=2
   if not eligible or lengths[longest]<0.0196 or depth>=5:
    out.append_array(PackedInt32Array([a,b,c]))
    continue
   var edges: Array=[[a,b,c],[b,c,a],[c,a,b]]
   var e: Array=edges[longest]
   var u: int=e[0];var v: int=e[1];var w: int=e[2]
   var key: String=str(mini(u,v))+'_'+str(maxi(u,v))
   var midpoint: int
   if cache.has(key):
    midpoint=cache[key]
   else:
    midpoint=vp.size()
    cache[key]=midpoint
    vp.append((vp[u]+vp[v])*0.5)
    np.append((np[u]+np[v]).normalized())
    if not uv.is_empty():uv.append((uv[u]+uv[v])*0.5)
    if not cp.is_empty():cp.append(cp[u].lerp(cp[v],0.5))
    if not tp.is_empty():
     var tan: Vector3=(Vector3(tp[u*4],tp[u*4+1],tp[u*4+2])+Vector3(tp[v*4],tp[v*4+1],tp[v*4+2])).normalized()
     tp.append_array(PackedFloat32Array([tan.x,tan.y,tan.z,tp[u*4+3]]))
   stack.append([u,midpoint,w,depth+1])
   stack.append([midpoint,v,w,depth+1])
 arrays[Mesh.ARRAY_VERTEX]=vp
 arrays[Mesh.ARRAY_NORMAL]=np
 arrays[Mesh.ARRAY_INDEX]=out
 if not uv.is_empty():arrays[Mesh.ARRAY_TEX_UV]=uv
 if not cp.is_empty():arrays[Mesh.ARRAY_COLOR]=cp
 if not tp.is_empty():arrays[Mesh.ARRAY_TANGENT]=tp
 return arrays

func _make_frame() -> void:
 frame_lines=MeshInstance3D.new()
 frame_lines.name='SimulatedStructuralMembers'
 var material:=StandardMaterial3D.new()
 material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 material.vertex_color_use_as_albedo=true
 frame_lines.material_override=material
 add_child(frame_lines)
 node_instances=MultiMeshInstance3D.new()
 var multi:=MultiMesh.new()
 multi.transform_format=MultiMesh.TRANSFORM_3D
 multi.use_colors=true
 var sphere:=SphereMesh.new()
 sphere.radius=0.042
 sphere.height=0.084
 sphere.radial_segments=8
 sphere.rings=4
 multi.mesh=sphere
 multi.instance_count=solver.points.size()
 node_instances.multimesh=multi
 node_instances.material_override=material
 add_child(node_instances)
 for w in solver.wheels.wheels:
  var assembly:=Node3D.new()
  add_child(assembly)
  wheel_visuals.append(assembly)
  for is_hub in [false,true]:
   var visual:=MeshInstance3D.new()
   var cylinder:=CylinderMesh.new()
   cylinder.top_radius=w.rim_radius if is_hub else w.radius
   cylinder.bottom_radius=cylinder.top_radius
   cylinder.height=w.half_width*2+(.008 if is_hub else 0)
   cylinder.radial_segments=20
   visual.mesh=cylinder
   visual.rotation.x=PI/2
   var mat:=StandardMaterial3D.new()
   mat.albedo_color=Color('#a4b0b0') if is_hub else Color('#22282a')
   mat.roughness=.8
   visual.material_override=mat
   assembly.add_child(visual)
 engine_visual=MeshInstance3D.new()
 var box:=BoxMesh.new()
 box.size=Vector3(.57,.29,.44)
 engine_visual.mesh=box
 var blue:=StandardMaterial3D.new()
 blue.albedo_color=Color('#5e9fbe')
 blue.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 engine_visual.material_override=blue
 add_child(engine_visual)

func update_pose() -> void:
 var began: int=Time.get_ticks_usec()
 var frames: Array[Basis]=[]
 for s in 7:
  frames.append(_station_frame(s)*bone_frames[s].inverse())
 for i in solver.points.size():
  var rotation:=Basis.IDENTITY
  if i<28:
   rotation=frames[i/4]
  elif i<30:
   rotation=frames[3]
  elif solver.wheels.by_node.has(i):
   rotation=solver.wheels.render_basis(solver.wheels.by_node[i])
  else:
   rotation=_engine_frame()*engine_rest_frame.inverse()
  skeleton.set_bone_pose_position(i,solver.points[i])
  skeleton.set_bone_pose_rotation(i,rotation.get_rotation_quaternion())
 var engine_basis: Basis=_engine_frame()*engine_rest_frame.inverse()
 skeleton.set_bone_pose_position(bone_rest.size()-1,_engine_center())
 skeleton.set_bone_pose_rotation(bone_rest.size()-1,engine_basis.get_rotation_quaternion())
 skeleton.force_update_all_bone_transforms()
 var damage:=PackedFloat32Array()
 var contact:=PackedFloat32Array()
 for s in 7:
  var left: int=maxi(0,s-1)
  var right: int=mini(6,s+1)
  var original_span: float=(solver.rest[right*4]-solver.rest[left*4]).length()
  var current_span: float=(solver.station_center(right)-solver.station_center(left)).length()
  var compression: float=maxf(0,1.0-current_span/maxf(.01,original_span))
  damage.append(clampf(compression*1.4,0,1))
  var value:=0.0
  for j in 4:value=maxf(value,solver.node_contact[s*4+j])
  contact.append(value)
 for m in materials:
  m.set_shader_parameter('plastic_sections',damage)
  m.set_shader_parameter('contact_sections',contact)
 if show_frame or mode==0 or mode==3:
  _update_frame()
 for i in wheel_visuals.size():
  var w=solver.wheels.wheels[i]
  wheel_visuals[i].position=solver.points[w.node]
  wheel_visuals[i].basis=solver.wheels.render_basis(i)
 engine_visual.position=_engine_center()
 engine_visual.basis=engine_basis
 max_upload_us=maxi(max_upload_us,Time.get_ticks_usec()-began)

func _update_frame() -> void:
 var mesh:=ImmediateMesh.new()
 mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
 for l in solver.links:
  if l.broken:continue
  if l.kind in ['front_brace','cabin_brace','bend']:
   continue
  if l.kind=='ring' and (l.a%2 != l.b%2) and ((l.a%4>=2)!=(l.b%4>=2)):
   continue
  if l.kind=='pillar' and mini(l.a,l.b) in [8,9]:
   continue
  var a: Vector3=solver.points[l.a]
  if l.wheel_index>=0:a+=solver.wheels.anchor(l.wheel_index,l.wheel_anchor)
  var b: Vector3=solver.points[l.b]
  var n: Vector3=(b-a).normalized()
  var tangent: Vector3=n.cross(Vector3.UP).normalized()
  if tangent.length()<0.1:tangent=n.cross(Vector3.RIGHT).normalized()
  var bitangent: Vector3=n.cross(tangent).normalized()
  var r:=0.026 if l.kind!='engine_rigid' else 0.018
  var color:=Color('#6bbeb0')
  if l.kind in ['front_rail','upper_front']:color=Color('#dda35b')
  elif l.kind=='engine_rigid' or l.kind=='engine_mount':color=Color('#659ec5')
  elif l.kind in ['suspension','steering_link','upper_arm']:color=Color('#bdca79')
  color=color.lerp(Color('#db493c'),clampf(float(l.damage),0,1))
  for k in 4:
   var p: Vector3=tangent*cos(k*TAU/4)*r+bitangent*sin(k*TAU/4)*r
   var q: Vector3=tangent*cos((k+1)*TAU/4)*r+bitangent*sin((k+1)*TAU/4)*r
   for v in [a+p,b+p,a+q,b+p,b+q,a+q]:
    mesh.surface_set_color(color)
    mesh.surface_add_vertex(v)
 mesh.surface_end()
 frame_lines.mesh=mesh
 for i in solver.points.size():
  node_instances.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,solver.points[i]))
  node_instances.multimesh.set_instance_color(i,Color('#7dcac0').lerp(Color('#e3573d'),solver.node_damage[i]))

func set_mode(value: int) -> void:
 mode=value
 body.visible=mode!=0
 for record in records:
  var node: MeshInstance3D=record.node
  node.visible=mode!=0
  for material in record.materials:
   if material is ShaderMaterial:
    material.shader=ghost_shader if mode==3 else shader
    material.set_shader_parameter('view_mode',1 if mode==1 else 2)
    material.set_shader_parameter('damage_enabled',detail_enabled and record.folding)
 frame_lines.visible=show_frame or mode==0 or mode==3
 node_instances.visible=frame_lines.visible
 engine_visual.visible=frame_lines.visible
 for wheel_visual in wheel_visuals:wheel_visual.visible=mode==0 or mode==3
 update_pose()

func binding_quality() -> Dictionary:
 var error:=0.0
 for i in solver.points.size():
  error=maxf(error,skeleton.get_bone_global_pose(i).origin.distance_to(solver.points[i]))
 var wheel_error:=0.0
 for i in solver.wheels.wheels.size():
  var w=solver.wheels.wheels[i]
  var actual: Basis=skeleton.get_bone_global_pose(w.node).basis
  var expected: Basis=solver.wheels.render_basis(i)
  wheel_error=maxf(wheel_error,maxf(actual.x.distance_to(expected.x),maxf(actual.y.distance_to(expected.y),actual.z.distance_to(expected.z))))
 return {'maximum_wheel_basis_error':wheel_error,'maximum_bone_anchor_error_m':error,'maximum_weight_sum_error':max_weight_error,'physical_nodes':solver.points.size(),'render_bones':skeleton.get_bone_count(),'rigid_engine_bone':bone_rest.size()-1}
