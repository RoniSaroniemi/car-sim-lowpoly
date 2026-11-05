extends RefCounted
## Only shorten an occluded camera ray; never change its requested yaw.
const MIN_DISTANCE=2.8
const MAX_DISTANCE=24.0
const MIN_PITCH=deg_to_rad(5)
const MAX_PITCH=deg_to_rad(80)
const CLEARANCE=.18
static func offset(yaw: float,pitch: float,distance: float) -> Vector3:
 return Vector3(cos(yaw)*cos(pitch),sin(pitch),sin(yaw)*cos(pitch))*distance
static func _box_entry(a: Vector3,b: Vector3,low: Vector3,high: Vector3) -> float:
 var ray:=b-a;var enter:=0.0;var leave:=1.0
 for axis in 3:
  if absf(ray[axis])<.000001:
   if a[axis]<low[axis] or a[axis]>high[axis]:return 1.0
  else:
   var first: float=(low[axis]-a[axis])/ray[axis];var last: float=(high[axis]-a[axis])/ray[axis]
   enter=maxf(enter,minf(first,last));leave=minf(leave,maxf(first,last))
   if enter>leave:return 1.0
 return enter if leave>=0 else 1.0
static func position(target: Vector3,wanted: Vector3,graph: RefCounted) -> Vector3:
 var ray:=wanted-target;var length_: float=ray.length()
 if length_<.001:return wanted
 var fraction:=1.0
 if graph.barrier_enabled:
  fraction=_box_entry(target,wanted,graph.barrier_min-Vector3.ONE*CLEARANCE,graph.barrier_max+Vector3.ONE*CLEARANCE)
 var provider: RefCounted=graph.static_contact_provider
 if provider!=null:
  # Sphere tracing the finite ring's signed distance is bounded to 32 queries.
  var travel:=0.0
  for iteration in 32:
   if travel>=length_*fraction:break
   var p: Vector3=target+ray*(travel/length_)
   if not provider.nearby(p,length_-travel):break
   var gap: float=float(provider.sample(p).distance)-CLEARANCE
   if gap<.005:fraction=minf(fraction,travel/length_);break
   travel+=maxf(gap,.005)
 return target+ray*maxf(.02,fraction-.08/length_) if fraction<1 else wanted
