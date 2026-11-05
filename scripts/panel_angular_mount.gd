extends RefCounted
## A surviving hinge resists tilt, yields its rest axis, and can tear under sustained torque.
const Attachment=preload('res://scripts/car_attachment.gd')
static func axis_from_points(p: Dictionary) -> Vector3:
 return (p.points[2]-p.points[0]).normalized()*(1 if p.side!=0 else -1)
static func single(p: Dictionary) -> bool:
 return not p.detached and int(not p.anchors[0].broken)+int(not p.anchors[1].broken)==1 and p.has('angular_mount')
static func target(g: RefCounted,p: Dictionary,frames: Array) -> Vector3:
 return (Attachment.frame_with_rotations(g,p.pivot,frames).basis*p.angular_mount.rest_axis).normalized()
static func error_vector(actual: Vector3,wanted: Vector3) -> Vector3:
 var cross_: Vector3=actual.cross(wanted);var length: float=cross_.length()
 if length<1e-8:return Vector3.ZERO
 return cross_/length*atan2(length,clampf(actual.dot(wanted),-1,1))
static func normals(axis: Vector3) -> Array:
 var a: Vector3=axis.cross(Vector3.RIGHT if absf(axis.x)<.8 else Vector3.UP).normalized()
 return [a,axis.cross(a).normalized()]
static func cage(system: RefCounted,p: Dictionary,frames: Array) -> void:
 if not single(p):return
 var g: RefCounted=system.graph.get_ref();var h: float=system.dt
 var v: Vector3=p.points[2]-p.points[0]
 if v.length_squared()<.04:return
 var wanted: Vector3=target(g,p,frames);var error: Vector3=error_vector(axis_from_points(p),wanted)
 var b0: Dictionary=p.bindings[0];var b2: Dictionary=p.bindings[2]
 var t0: Vector3=Attachment.mapped(g,p.rest[0],b0,frames);var t2: Vector3=Attachment.mapped(g,p.rest[2],b2,frames)
 var span: Vector3=t2-t0
 if span.length_squared()<.04:return
 var m: Dictionary=p.angular_mount
 var component:=0
 for n in normals(wanted):
  var grad: Vector3=n.cross(v)/v.length_squared();var body_grad: Vector3=n.cross(span)/span.length_squared()
  var body: Dictionary={}
  for pair in [[b0,1.0],[b2,-1.0]]:
   var b: Dictionary=pair[0]
   for k in b.ids.size():body[b.ids[k]]=body.get(b.ids[k],Vector3.ZERO)+body_grad*b.weights[k]*float(pair[1])
  var weight: float=(20/p.mass)*grad.length_squared()
  for node in body:weight+=g.inverse_masses[node]*body[node].length_squared()
  var alpha: float=1/(m.stiffness_nm_rad*h*h)
  var dl: float=(error.dot(n)-alpha*m.lambda[component])/(weight+alpha)
  m.lambda[component]+=dl
  p.points[2]+=grad*dl*(10/p.mass);p.points[0]-=grad*dl*(10/p.mass)
  for node in body:g.points[node]+=body[node]*dl*g.inverse_masses[node]
  m.step_peak_nm=maxf(m.step_peak_nm,absf(m.lambda[component])/(h*h));component+=1
 m.peak_nm=maxf(m.peak_nm,m.step_peak_nm)
static func inverse(d: Dictionary,v: Vector3) -> Vector3:
 var b:=Basis(d.rotation)
 return b*(d.inverse_inertia*(b.transposed()*v))
static func reduced(owner: RefCounted,p: Dictionary,frames: Array,h: float) -> void:
 if not single(p):return
 var g: RefCounted=owner.graph;var d: Dictionary=p.reduced_data;var m: Dictionary=p.angular_mount
 if not d.has('hinge_axis_local'):d.hinge_axis_local=Basis(d.rotation).inverse()*axis_from_points(p)
 var actual: Vector3=(Basis(d.rotation)*d.hinge_axis_local).normalized()
 var wanted: Vector3=target(g,p,frames);var error: Vector3=error_vector(actual,wanted)
 var relative: Vector3=d.omega-(owner.compact.angular_velocity if owner.compact!=null else Vector3.ZERO)
 m.step_peak_nm=0
 for n in normals(wanted):
  var weight: float=n.dot(inverse(d,n))+(n.dot(owner.compact.inverse_inertia(n)) if owner.compact!=null else 0)
  var j: float=(m.stiffness_nm_rad*error.dot(n)*h-m.damping_nms_rad*relative.dot(n)*h)/(1+weight*m.damping_nms_rad*h+weight*m.stiffness_nm_rad*h*h)
  d.omega+=inverse(d,n*j)
  if owner.compact!=null:owner.compact.angular_velocity-=owner.compact.inverse_inertia(n*j)
  m.step_peak_nm=maxf(m.step_peak_nm,absf(j)/h)
 m.peak_nm=maxf(m.peak_nm,m.step_peak_nm)
 finish(owner.system,p,actual,wanted,frames,h)
static func finish(system: RefCounted,p: Dictionary,actual: Vector3,wanted: Vector3,frames: Array,h: float) -> void:
 if not single(p):return
 var m: Dictionary=p.angular_mount;var error: Vector3=error_vector(actual,wanted)
 var g: RefCounted=system.graph.get_ref()
 if m.step_peak_nm>m.yield_nm and error.length()>m.yield_nm/m.stiffness_nm_rad:
  var delta: float=minf(error.length()-m.yield_nm/m.stiffness_nm_rad,3*h)
  delta=minf(delta,maxf(0,m.max_plastic_rad-m.plastic_rad))
  if delta>0:
   var frame: Transform3D=Attachment.frame_with_rotations(g,p.pivot,frames)
   var local_axis: Vector3=frame.basis.inverse()*(-error.normalized())
   m.rest_axis=(Quaternion(local_axis.normalized(),delta)*m.rest_axis).normalized()
   m.plastic_rad+=delta;m.plastic_work_j+=m.yield_nm*delta
   if not m.yielded:
    m.yielded=true;system.events.append({'id':system.events.size(),'time':system.clock,'panel':p.id,'kind':'remaining_hinge_angular_yield','torque_nm':m.step_peak_nm})
 # Local plastic angular strain is itself a destroyed-mount load path. Ordinary
 # gravity/braking cannot pass both this large torque and permanent bend gate.
 var overload: bool=m.step_peak_nm>m.break_nm and m.plastic_rad>deg_to_rad(18) and error.length()>.25
 m.overload_s=maxf(0,m.overload_s+h*(1 if overload else -2))
 if m.overload_s>.060:
  var index: int=0 if not p.anchors[0].broken else 1
  p.anchors[index].broken=true;m['torn']=true
  system.events.append({'id':system.events.size(),'time':system.clock,'panel':p.id,'kind':'remaining_hinge_torsion_tear','torque_nm':m.step_peak_nm,'plastic_rad':m.plastic_rad})
