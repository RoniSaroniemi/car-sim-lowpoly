extends 'res://probes/damage_surfaces/surface_skin.gd'
const STUDIO_SHADER=preload('res://probes/damage_studio/studio_layers.gdshader')
const PREVIOUS_SHADER=preload('res://probes/damage_studio/variants/v2/studio_layers.gdshader')
func studio_materials() -> void:
 for material in surface_materials:material.shader=STUDIO_SHADER
 apply_layers()

# Studio-only construction-time tessellation for actual cosmetic displacement.
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
