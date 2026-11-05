extends RefCounted
## Matches structural_skin.gd's eight-weight station binding in car rest space.
## No solver ownership or mutable graph references are stored here.
static func binding(graph: RefCounted,p: Vector3) -> Dictionary:
 var station:=0
 for i in 6:
  if p.x>=float(graph.config.station_x[i]):station=i
 var x0: float=graph.config.station_x[station]
 var x1: float=graph.config.station_x[station+1]
 var t: float=clampf((p.x-x0)/maxf(.0001,x1-x0),0,1)
 var ids:=PackedInt32Array();var weights:=PackedFloat32Array()
 for q in 2:
  var s: int=station+q
  var top: float=graph.config.station_top_y[s]
  var y: float=clampf((p.y-.58)/maxf(.001,top-.58),0,1)
  var width: float=graph.config.station_half_width[s]
  var z: float=clampf((p.z+width)/(2*width),0,1)
  for j in 4:
   ids.append(s*4+j)
   weights.append((t if q else 1-t)*(y if j>=2 else 1-y)*(z if j%2 else 1-z))
 return {'ids':ids,'weights':weights}
static func _station(graph: RefCounted,s: int,original: bool) -> Basis:
 var positions: PackedVector3Array=graph.rest if original else graph.points
 var left: int=maxi(0,s-1);var right: int=mini(6,s+1)
 var a: Vector3=(positions[left*4]+positions[left*4+1]+positions[left*4+2]+positions[left*4+3])*.25
 var b: Vector3=(positions[right*4]+positions[right*4+1]+positions[right*4+2]+positions[right*4+3])*.25
 var x: Vector3=(b-a).normalized()
 var z: Vector3=(positions[s*4+1]+positions[s*4+3]-positions[s*4]-positions[s*4+2]).normalized()
 z=(z-x*x.dot(z)).normalized()
 if x.length()<.01 or z.length()<.01:return Basis.IDENTITY
 var y: Vector3=z.cross(x).normalized()
 return Basis(x,y,x.cross(y).normalized())
static func rotations(graph: RefCounted) -> Array:
 var result: Array=[]
 for s in 7:result.append(_station(graph,s,false)*_station(graph,s,true).inverse())
 return result
static func mapped(graph: RefCounted,p: Vector3,bind: Dictionary,frames: Array) -> Vector3:
 var result:=Vector3.ZERO
 for j in bind.ids.size():
  var index: int=bind.ids[j]
  result+=(graph.points[index]+frames[index/4]*(p-graph.rest[index]))*bind.weights[j]
 return result
static func point(graph: RefCounted,rest_point: Vector3) -> Vector3:
 return mapped(graph,rest_point,binding(graph,rest_point),rotations(graph))
static func frame_with_rotations(graph: RefCounted,rest_origin: Vector3,frames: Array) -> Transform3D:
 var origin: Vector3=mapped(graph,rest_origin,binding(graph,rest_origin),frames)
 var x: Vector3=mapped(graph,rest_origin+Vector3(.04,0,0),binding(graph,rest_origin+Vector3(.04,0,0)),frames)-origin
 var z: Vector3=mapped(graph,rest_origin+Vector3(0,0,.04),binding(graph,rest_origin+Vector3(0,0,.04)),frames)-origin
 x=x.normalized();z=(z-x*x.dot(z)).normalized()
 if x.length()<.01 or z.length()<.01:return Transform3D(Basis.IDENTITY,origin)
 var y: Vector3=z.cross(x).normalized()
 return Transform3D(Basis(x,y,x.cross(y).normalized()),origin)
static func frame(graph: RefCounted,rest_origin: Vector3) -> Transform3D:
 return frame_with_rotations(graph,rest_origin,rotations(graph))
