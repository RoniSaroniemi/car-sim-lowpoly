extends RefCounted
## Rest-space impact bins; these do not add physical collision bodies.
var counts:=Vector3i(5,3,3)
var low:=Vector3(-1.90,0,-1.0)
var size:=Vector3(3.85,1.90,2.0)

func zone(p: Vector3) -> int:
 var q: Vector3=(p-low)/size
 var x: int=clampi(floori(q.x*counts.x),0,counts.x-1)
 var y: int=clampi(floori(q.y*counts.y),0,counts.y-1)
 var z: int=clampi(floori(q.z*counts.z),0,counts.z-1)
 return (x*counts.y+y)*counts.z+z

func coordinates(id: int) -> Vector3i:
 return Vector3i(id/(counts.y*counts.z),(id/counts.z)%counts.y,id%counts.z)

func cell_center(id: int) -> Vector3:
 var c: Vector3i=coordinates(id)
 return low+(Vector3(c)+Vector3.ONE*.5)*size/Vector3(counts)

func time_to_contact(g: RefCounted,velocity: Vector3,horizon: float) -> float:
 var earliest:=INF
 if not g.barrier_enabled:return earliest
 for i in g.points.size():
  var radius: float=g.radii[i]
  var a: Vector3=g.barrier_min-Vector3.ONE*radius
  var b: Vector3=g.barrier_max+Vector3.ONE*radius
  var entry:=0.0
  var exit:=horizon
  var hit:=true
  for axis in 3:
   if absf(velocity[axis])<1e-7:
    if g.points[i][axis]<a[axis] or g.points[i][axis]>b[axis]:hit=false
   else:
    var t0: float=(a[axis]-g.points[i][axis])/velocity[axis]
    var t1: float=(b[axis]-g.points[i][axis])/velocity[axis]
    entry=maxf(entry,minf(t0,t1));exit=minf(exit,maxf(t0,t1))
   if entry>exit:hit=false
  if hit and exit>=0 and entry<=horizon:earliest=minf(earliest,maxf(0,entry))
 return earliest

func body_basis(g: RefCounted) -> Basis:
 var x: Vector3=g.station_center(6)-g.station_center(0)
 x.y=0;x=x.normalized()
 var z: Vector3=x.cross(Vector3.UP).normalized()
 return Basis(x,z.cross(x).normalized(),z)

func signature(g: RefCounted,velocity: Vector3) -> Dictionary:
 var candidates: Array=[]
 var total_weight:=0.0
 var normal:=Vector3.ZERO
 for i in g.points.size():
  var hit: Dictionary=g.barrier_distance(g.points[i])
  if float(hit.distance)-g.radii[i]>.025:continue
  if velocity.dot(hit.normal)>=-.1:continue
  candidates.append({'node':i,'normal':hit.normal,'weight':float(g.masses[i])})
  total_weight+=float(g.masses[i])
  normal+=hit.normal
 if candidates.is_empty():return {}
 normal=normal.normalized()
 var local_normal: Vector3=body_basis(g).transposed()*normal
 var speed: float=maxf(0,-velocity.dot(normal))
 var momentum: float=float(g.config.mass_kg)*speed
 var energy: float=.5*float(g.config.mass_kg)*speed*speed
 var weights:=PackedFloat32Array()
 weights.resize(counts.x*counts.y*counts.z)
 var hit_nodes: Array=[]
 for c in candidates:
  var id: int=zone(g.rest[c.node]-(body_basis(g).transposed()*c.normal)*g.radii[c.node])
  weights[id]+=c.weight/total_weight
  hit_nodes.append(c.node)
 var zones: Array=[]
 for id in weights.size():
  if weights[id]>0:
   zones.append({'id':id,'weight':weights[id],'incident_impulse_proxy_ns':momentum*weights[id],'incident_energy_proxy_j':energy*weights[id]})
 return {'zones':zones,'normal':[local_normal.x,local_normal.y,local_normal.z],'world_normal':[normal.x,normal.y,normal.z],'velocity':[velocity.x,velocity.y,velocity.z],'closing_speed_mps':speed,'incident_impulse_proxy_ns':momentum,'incident_energy_proxy_j':energy,'hit_nodes':hit_nodes,'grid':[counts.x,counts.y,counts.z]}

func match_signature(incoming: Dictionary,expected: Dictionary) -> Dictionary:
 if incoming.is_empty() or expected.is_empty():return {'accepted':false,'score':0.0,'reason':'No impact-zone event'}
 var a:=PackedFloat32Array();var b:=PackedFloat32Array()
 a.resize(45);b.resize(45)
 for item in incoming.zones:a[int(item.id)]=item.weight
 for item in expected.zones:b[int(item.id)]=item.weight
 var intersection:=0.0;var union:=0.0
 for i in 45:
  intersection+=minf(a[i],b[i]);union+=maxf(a[i],b[i])
 var overlap: float=intersection/maxf(.00001,union)
 var na:=Vector3(incoming.normal[0],incoming.normal[1],incoming.normal[2])
 var nb:=Vector3(expected.normal[0],expected.normal[1],expected.normal[2])
 var alignment: float=na.dot(nb)
 var ratio: float=float(incoming.incident_impulse_proxy_ns)/maxf(.0001,expected.incident_impulse_proxy_ns)
 var severity: float=exp(-absf(log(maxf(.0001,ratio))))
 var angle_error: float=rad_to_deg(acos(clampf(alignment,-1,1)))
 var score: float=.70*exp(-.5*pow(angle_error/15.0,2))+.20*overlap+.10*severity
 var accepted: bool=overlap>.1 and angle_error<18.01 and ratio>.85 and ratio<1.15 and score>.65
 return {'accepted':accepted,'score':score,'zone_overlap':overlap,'normal_alignment':alignment,'angle_error_deg':angle_error,'impulse_ratio':ratio,'reason':'Recorded case matched' if accepted else 'Outside the recorded case'}

func choose(incoming: Dictionary,library: Array) -> Dictionary:
 var best: Dictionary={'accepted':false,'score':0.0,'reason':'No compatible recorded impact','index':-1}
 var candidates: Array=[]
 for index in library.size():
  var result: Dictionary=match_signature(incoming,library[index].metadata.signature)
  result['id']=library[index].metadata.id;result['index']=index
  candidates.append(result.duplicate())
  if result.accepted and (not best.accepted or result.score>best.score):best=result.duplicate()
 best['candidates']=candidates
 return best
