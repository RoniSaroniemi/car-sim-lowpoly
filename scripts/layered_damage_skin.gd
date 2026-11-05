extends 'res://scripts/structural_skin.gd'
## Shared live/baked cosmetic renderer. VehicleSurface owns all persistent state.
const LAYERS=preload('res://scripts/damage_layers.gdshader')
var surface_materials: Array=[]
var rest_attribute_bytes:=0
var surface: RefCounted
var last_surface_revision: int=-1

func setup(graph: RefCounted,model_path: String='res://assets/Niva_2121_LOD0.glb') -> void:
 if graph.effects!=null:surface=graph.effects.surface
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
  material.shader=LAYERS if mode!=3 and surface!=null and surface.enabled else (ghost_shader if mode==3 else shader)
  material.set_shader_parameter('damage_enabled',mode==2 and detail_enabled and surface!=null and surface.enabled)
  material.set_shader_parameter('view_mode',1 if mode==1 else 2)
 last_surface_revision=-1
 _upload_surface()

func update_pose() -> void:
 super.update_pose()
 _upload_surface()

func _upload_surface() -> void:
 if surface==null or last_surface_revision==surface.revision:return
 var centers:=PackedVector3Array();var radii:=PackedVector3Array();var directions:=PackedVector3Array();var strengths:=PackedFloat32Array()
 centers.resize(8);radii.resize(8);directions.resize(8);strengths.resize(8);radii.fill(Vector3.ONE)
 for index in surface.marks.size():
  var mark: Dictionary=surface.marks[index]
  centers[index]=mark.center;radii[index]=mark.radii;directions[index]=mark.direction;strengths[index]=mark.strength
 var heights:=PackedFloat32Array();var widths:=PackedFloat32Array()
 for value in solver.config.station_top_y:heights.append(value)
 for value in solver.config.station_half_width:widths.append(value)
 for material in surface_materials:
  for key in surface.parameters:
   var value: Variant=surface.parameters[key]
   if key.ends_with('_color'):value=Color(str(value)).srgb_to_linear()
   material.set_shader_parameter(key,value)
  material.set_shader_parameter('impact_center',Vector3.ZERO)
  material.set_shader_parameter('mark_count',surface.marks.size())
  material.set_shader_parameter('mark_centers',centers);material.set_shader_parameter('mark_radii',radii)
  material.set_shader_parameter('mark_directions',directions);material.set_shader_parameter('mark_strengths',strengths)
  material.set_shader_parameter('node_damage',surface.damage);material.set_shader_parameter('node_contact',surface.contact);material.set_shader_parameter('node_compression',surface.compression)
  material.set_shader_parameter('section_height',heights);material.set_shader_parameter('section_width',widths)
 last_surface_revision=surface.revision

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
   if not eligible or lengths[longest]<0.005625 or depth>=7:
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
