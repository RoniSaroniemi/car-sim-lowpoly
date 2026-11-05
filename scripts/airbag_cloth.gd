extends RefCounted
## One-way interior equivalent model. Parameters are illustrative game inputs.
var time:=0.0
var hub:=Vector3.ZERO
var torso:=Vector3(-.39,-.03,0)
var torso_radius:=.13
var points:=PackedVector3Array()
var previous:=PackedVector3Array()
var rest:=PackedVector3Array()
var pinned:=PackedByteArray()
var triangles:=PackedInt32Array()
var links: Array=[]
var deployment:=0.0
var triggered:=false
var trigger_time:=-1.0
var initial_volume:=0.0
var signed_rest_volume:=0.0
var maximum_anchor_error:=0.0
var minimum_torso_clearance:=INF
var total_cpu_us:=0
var steps:=0
var cloth_iterations:=7
var settings: Dictionary={}
var latitudes: Array=[0.0,.12,.45,.8,1.15,1.5,1.85,2.2,2.55,2.85,PI]
const SIDES=16

func setup(options: Dictionary={}) -> void:
 settings=options.duplicate(true)
 torso=Vector3(-.39,-.03,0)
 torso_radius=float(settings.get('torso_proxy_radius_m',.13))
 rest.clear();triangles.clear();links.clear()
 rest.append(Vector3.ZERO)
 for ring in range(1,latitudes.size()-1):
  var phi: float=latitudes[ring]
  for j in SIDES:
   var theta: float=TAU*j/SIDES
   rest.append(Vector3(float(settings.get('axial_radius_m',.20))*(cos(phi)-1),float(settings.get('radius_m',.22))*sin(phi)*cos(theta),float(settings.get('radius_m',.22))*sin(phi)*sin(theta)))
 rest.append(Vector3(-2*float(settings.get('axial_radius_m',.20)),0,0))
 for j in SIDES:
  triangles.append_array(PackedInt32Array([0,1+j,1+(j+1)%SIDES]))
 for ring in latitudes.size()-3:
  var first: int=1+ring*SIDES
  var next: int=first+SIDES
  for j in SIDES:
   var a: int=first+j;var b: int=next+j;var c: int=next+(j+1)%SIDES;var d: int=first+(j+1)%SIDES
   triangles.append_array(PackedInt32Array([a,b,c,a,c,d]))
 var last: int=rest.size()-1-SIDES
 for j in SIDES:triangles.append_array(PackedInt32Array([last+j,rest.size()-1,last+(j+1)%SIDES]))
 var edges: Dictionary={}
 for face in range(0,triangles.size(),3):
  for pair in [[triangles[face],triangles[face+1]],[triangles[face+1],triangles[face+2]],[triangles[face+2],triangles[face]]]:
   var a: int=mini(pair[0],pair[1]);var b: int=maxi(pair[0],pair[1]);var key: String='%d_%d'%[a,b]
   if not edges.has(key):edges[key]=true;links.append({'a':a,'b':b,'length':rest[a].distance_to(rest[b]),'stiffness':.88})
 # Coarse bending/tether distances retain a pillow shape without a target-position animation.
 for ring in range(0,latitudes.size()-4):
  for j in SIDES:
   var a: int=1+ring*SIDES+j;var b: int=a+2*SIDES
   links.append({'a':a,'b':b,'length':rest[a].distance_to(rest[b]),'stiffness':.15})
 points.resize(rest.size());previous.resize(rest.size());pinned.resize(rest.size())
 for i in pinned.size():pinned[i]=1 if i<=SIDES else 0
 signed_rest_volume=volume(rest)
 initial_volume=absf(signed_rest_volume)
 reset()

func reset() -> void:
 time=0
 deployment=0;triggered=false;trigger_time=-1
 maximum_anchor_error=0;minimum_torso_clearance=INF;total_cpu_us=0;steps=0
 for i in rest.size():points[i]=hub+rest[i]*.025;previous[i]=points[i]

func volume(positions: PackedVector3Array) -> float:
 var value:=0.0
 for i in range(0,triangles.size(),3):value+=positions[triangles[i]].dot(positions[triangles[i+1]].cross(positions[triangles[i+2]]))/6.0
 return value

func trigger() -> void:
 if triggered:return
 triggered=true;trigger_time=time

func step(dt: float,relative_acceleration: Vector3=Vector3.ZERO) -> void:
 var began: int=Time.get_ticks_usec()
 if triggered:
  deployment=clampf((time-trigger_time)/float(settings.get('deployment_seconds',.065)),0,1)
  var inflation: float=lerpf(.025,1.0,smoothstep(0,1,deployment))
  var accel: Vector3=relative_acceleration.limit_length(float(settings.get('maximum_acceleration_mps2',600)))
  for i in points.size():
   if pinned[i]:points[i]=hub+rest[i]*inflation;previous[i]=points[i];continue
   var current: Vector3=points[i]
   points[i]+=(points[i]-previous[i])*.985+accel*dt*dt
   previous[i]=current
  for iteration in cloth_iterations:
   for link in links:
    var a: int=link.a;var b: int=link.b
    var delta: Vector3=points[b]-points[a];var length: float=delta.length()
    if length<1e-9:continue
    var wa: float=0.0 if pinned[a] else 1.0;var wb: float=0.0 if pinned[b] else 1.0
    if wa+wb==0:continue
    var correction: Vector3=delta*((length-link.length*inflation)*link.stiffness/(length*(wa+wb)))
    points[a]+=correction*wa;points[b]-=correction*wb
   _volume_constraint(inflation)
   _collisions()
   for i in points.size():
    if pinned[i]:points[i]=hub+rest[i]*inflation
  for i in points.size():
   if pinned[i]:maximum_anchor_error=maxf(maximum_anchor_error,points[i].distance_to(hub+rest[i]*inflation))
   else:minimum_torso_clearance=minf(minimum_torso_clearance,points[i].distance_to(torso)-torso_radius)
 time+=dt;steps+=1;total_cpu_us+=Time.get_ticks_usec()-began

func _volume_constraint(inflation: float) -> void:
 var gradients:=PackedVector3Array();gradients.resize(points.size())
 var current_volume:=0.0
 for i in range(0,triangles.size(),3):
  var a: int=triangles[i];var b: int=triangles[i+1];var c: int=triangles[i+2]
  var pa: Vector3=points[a]-hub;var pb: Vector3=points[b]-hub;var pc: Vector3=points[c]-hub
  current_volume+=pa.dot(pb.cross(pc))/6.0
  gradients[a]+=pb.cross(pc)/6.0;gradients[b]+=pc.cross(pa)/6.0;gradients[c]+=pa.cross(pb)/6.0
 var denominator:=.000001
 for i in points.size():
  if not pinned[i]:denominator+=gradients[i].length_squared()
 var error: float=current_volume-signed_rest_volume*pow(inflation,3)
 var lambda: float=-error/denominator*.65
 for i in points.size():
  if not pinned[i]:points[i]+=(gradients[i]*lambda).limit_length(.025)

func _collisions() -> void:
 for i in points.size():
  if pinned[i]:continue
  points[i].x=minf(points[i].x,float(settings.get('dash_backstop_x_m',.12)))
  points[i].y=maxf(points[i].y,float(settings.get('lower_backstop_y_m',-.48)))
  var delta: Vector3=points[i]-torso
  if delta.length()<torso_radius+.008:points[i]=torso+delta.normalized()*(torso_radius+.008)

func capture() -> Dictionary:
 var velocity:=PackedVector3Array()
 if triggered:
  velocity.resize(points.size())
  for i in points.size():velocity[i]=(points[i]-previous[i])*240.0
 return {'elapsed':time,'deployment':deployment,'triggered':triggered,'trigger_time':trigger_time,'points':points.duplicate() if triggered else PackedVector3Array(),'velocities':velocity}

func restore(a: Dictionary,b: Dictionary,alpha: float) -> void:
 time=lerpf(a.get('elapsed',0),b.get('elapsed',0),alpha)
 triggered=bool(b.get('triggered',false)) if alpha>=1 else bool(a.get('triggered',false))
 trigger_time=float(a.get('trigger_time',-1))
 deployment=lerpf(a.get('deployment',0),b.get('deployment',0),alpha)
 var pa: PackedVector3Array=a.get('points',PackedVector3Array())
 var pb: PackedVector3Array=b.get('points',PackedVector3Array())
 if pa.size()==points.size() and pb.size()==points.size():
  for i in points.size():points[i]=pa[i].lerp(pb[i],alpha)
 elif pa.size()==points.size():points=pa.duplicate()
 elif pb.size()==points.size() and alpha>=1:points=pb.duplicate()
 else:
  for i in points.size():points[i]=hub+rest[i]*.025
 previous=points.duplicate()
 var va: PackedVector3Array=a.get('velocities',PackedVector3Array());var vb: PackedVector3Array=b.get('velocities',PackedVector3Array())
 if va.size()==points.size() and vb.size()==points.size():
  for i in points.size():previous[i]-=va[i].lerp(vb[i],alpha)/240.0
