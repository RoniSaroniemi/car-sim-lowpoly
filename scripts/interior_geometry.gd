extends RefCounted
## Deterministic extraction of the existing front-seat parts; no GLB rebuild.
## Input vertices must be in canonical vehicle rest coordinates (X forward,Y up).
static func _find(parents: PackedInt32Array,index: int) -> int:
 while parents[index]!=index:index=parents[index]
 return index

static func _seat_component(low: Vector3,high: Vector3) -> int:
 if low.x<-.50 or high.x>.24 or low.y<.59 or high.y>1.67:return 0
 for side in 2:
  var center_z: float=.39 if side==0 else -.39
  if low.z<center_z-.31 or high.z>center_z+.31:continue
  if high.y>.89:
   if low.x>-.14:return 0
   return 2+side*2 # back/headrest: driver2,passenger4
  return 1+side*2 # base/cushion/rail: driver1,passenger3
 return 0

static func split_arrays(source: Array) -> Dictionary:
 var vertices: PackedVector3Array=source[Mesh.ARRAY_VERTEX]
 var indices: PackedInt32Array=source[Mesh.ARRAY_INDEX]
 if indices.is_empty():
  indices=PackedInt32Array()
  for i in vertices.size():indices.append(i)
 var parents:=PackedInt32Array();parents.resize(vertices.size())
 var coincident: Dictionary={}
 for i in vertices.size():
  parents[i]=i
  var p: Vector3=vertices[i]
  var key: Vector3i=Vector3i(roundi(p.x*100000),roundi(p.y*100000),roundi(p.z*100000))
  if coincident.has(key):parents[_find(parents,i)]=_find(parents,int(coincident[key]))
  else:coincident[key]=i
 for face in range(0,indices.size(),3):
  var a: int=_find(parents,indices[face]);var b: int=_find(parents,indices[face+1]);var c: int=_find(parents,indices[face+2])
  parents[b]=a;parents[c]=a
 var bounds: Dictionary={}
 for i in vertices.size():
  var component: int=_find(parents,i)
  if not bounds.has(component):bounds[component]={'low':Vector3(INF,INF,INF),'high':Vector3(-INF,-INF,-INF)}
  bounds[component].low=bounds[component].low.min(vertices[i]);bounds[component].high=bounds[component].high.max(vertices[i])
 var tags: Dictionary={}
 for component in bounds:tags[component]=_seat_component(bounds[component].low,bounds[component].high)
 var groups: Array=[]
 for i in 5:groups.append(PackedInt32Array())
 for face in range(0,indices.size(),3):
  var group: int=tags[_find(parents,indices[face])]
  groups[group].append_array(PackedInt32Array([indices[face],indices[face+1],indices[face+2]]))
 var arrays: Array=[]
 for group in groups:arrays.append(_compact(source,group))
 var triangle_counts: Array=[]
 for group in groups:triangle_counts.append(group.size()/3)
 return {'arrays':arrays,'triangle_counts':triangle_counts,'source_triangles':indices.size()/3,'components':bounds.size()}

static func _compact(source: Array,indices: PackedInt32Array) -> Array:
 var out: Array=[];out.resize(Mesh.ARRAY_MAX)
 if indices.is_empty():return out
 var lookup: Dictionary={};var old_ids: Array=[];var new_indices:=PackedInt32Array()
 for index in indices:
  if not lookup.has(index):lookup[index]=old_ids.size();old_ids.append(index)
  new_indices.append(lookup[index])
 var count: int=source[Mesh.ARRAY_VERTEX].size()
 for kind in Mesh.ARRAY_MAX:
  if kind==Mesh.ARRAY_INDEX:out[kind]=new_indices;continue
  if source[kind]==null:continue
  var values: Variant=source[kind].duplicate();values.resize(0)
  var stride: int=source[kind].size()/count
  for index in old_ids:
   for j in stride:values.append(source[kind][index*stride+j])
  out[kind]=values
 return out
