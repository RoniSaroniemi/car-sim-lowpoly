extends RefCounted
## Four finite-width rigid assemblies; hub tilt and bearing spin are separate.
## Translation/mass lives in the structural graph, never in a second rigid body.
class Wheel:
 var links: Array=[]
 var body_nodes: Array=[]
 var steering_angle:=0.0
 var alignment:=Vector3.BACK
 var joint_lambda:=0.0
 var joint_peak:=0.0
 var joint_overload:=0.0
 var joint_broken:=false
 var joint_stiffness:=24000.0
 var joint_yield:=2500.0
 var joint_break:=9500.0
 var node: int
 var radius: float
 var rim_radius: float
 var half_width: float
 var max_compression: float
 var compliance: float
 var inertia_tilt: float
 var inertia_spin: float
 var rotation:=Quaternion.IDENTITY
 var previous_rotation:=Quaternion.IDENTITY
 var angular_velocity:=Vector3.ZERO
 var spin:=0.0
 var spin_speed:=0.0
 var tire_compression:=0.0
 var peak_compression:=0.0
 var detached:=false
 var capsules: Array=[]
 var contact_lambdas:=PackedFloat64Array([0,0])
 var contacts: Array[Dictionary]=[]
 var body_lambdas:=PackedFloat64Array()
 var body_impulse:=0.0
 var maximum_body_impulse:=0.0
 var contact_events:=0
 var rest_center:=Vector3.ZERO

var graph: WeakRef
var wheels: Array[Wheel]=[]
var by_node: Dictionary={}
var body_contact_enabled:=true
var friction_coefficient:=.65

func setup(owner: RefCounted) -> void:
 graph=weakref(owner)
 for raw in owner.config.wheel_assemblies:
  var w:=Wheel.new()
  w.node=raw.node
  w.body_nodes=raw.axle_body_nodes
  w.joint_stiffness=raw.knuckle_stiffness_nm_per_rad
  w.joint_yield=raw.knuckle_yield_nm
  w.joint_break=raw.knuckle_break_nm
  w.radius=raw.radius_m
  w.rim_radius=raw.rim_radius_m
  w.half_width=raw.half_width_m
  w.max_compression=raw.max_tire_compression_m
  w.compliance=1.0/float(raw.contact_stiffness_n_per_m)
  var mass: float=owner.masses[w.node]
  w.inertia_spin=.5*mass*(w.radius*w.radius+w.rim_radius*w.rim_radius)
  w.inertia_tilt=.25*mass*(w.radius*w.radius+w.rim_radius*w.rim_radius)+mass*w.half_width*w.half_width/3.0
  w.capsules=raw.body_capsules
  w.body_lambdas.resize(w.capsules.size())
  w.rest_center=owner.rest[w.node]
  by_node[w.node]=wheels.size()
  wheels.append(w)

func reset(speed: float) -> void:
 for w in wheels:
  w.steering_angle=0
  w.alignment=Vector3.BACK
  w.joint_lambda=0
  w.joint_peak=0
  w.joint_overload=0
  w.joint_broken=false
  w.rotation=Quaternion.IDENTITY
  w.previous_rotation=w.rotation
  w.angular_velocity=Vector3.ZERO
  w.spin=0
  w.spin_speed=-speed/w.radius
  w.tire_compression=0
  w.peak_compression=0
  w.detached=false
  w.body_impulse=0
  w.maximum_body_impulse=0
  w.contact_events=0
  w.body_lambdas.fill(0)
  w.contact_lambdas.fill(0)
  w.contacts.clear()

func predict(dt: float) -> void:
 for w in wheels:
  w.previous_rotation=w.rotation
  w.joint_lambda=0
  w.joint_peak=0
  _rotate(w,w.angular_velocity*dt)
  w.spin=wrapf(w.spin+w.spin_speed*dt,-PI,PI)
  w.tire_compression=0
  w.contacts.clear()
  w.contact_lambdas.fill(0)
  w.body_lambdas.fill(0)

func _rotate(w: Wheel,delta: Vector3) -> void:
 var angle: float=delta.length()
 if angle>1e-10:
  w.rotation=(Quaternion(delta/angle,minf(angle,.20))*w.rotation).normalized()

func inverse_inertia(w: Wheel,torque: Vector3,include_spin: bool=false) -> Vector3:
 var basis:=Basis(w.rotation)
 var local: Vector3=basis.transposed()*torque
 local.x/=w.inertia_tilt
 local.y/=w.inertia_tilt
 local.z=local.z/w.inertia_spin if include_spin else 0.0
 return basis*local

func anchor(index: int,local: Vector3) -> Vector3:
 return Basis(wheels[index].rotation)*local

func rotational_weight(index: int,r: Vector3,n: Vector3) -> float:
 var t: Vector3=r.cross(n)
 return t.dot(inverse_inertia(wheels[index],t))

func correct_rotation(index: int,r: Vector3,n: Vector3,impulse: float) -> void:
 var w: Wheel=wheels[index]
 _rotate(w,inverse_inertia(w,r.cross(n))*impulse)

func anchor_velocity(index: int,r: Vector3) -> Vector3:
 return wheels[index].angular_velocity.cross(r)

func damp_rotation(index: int,r: Vector3,impulse: Vector3) -> void:
 var w: Wheel=wheels[index]
 w.angular_velocity+=inverse_inertia(w,r.cross(impulse))

func support(w: Wheel,direction: Vector3) -> Vector3:
 # Convex rounded tire: radial disk plus elliptical shoulder. Continuous near
 # zero camber, unlike the discontinuous support corner of a sharp cylinder.
 var axle: Vector3=Basis(w.rotation).z
 var axial: float=direction.dot(axle)
 var radial: Vector3=direction-axle*axial
 var radial_length: float=radial.length()
 var shoulder: float=w.radius-w.rim_radius
 var denom: float=sqrt(shoulder*shoulder*radial_length*radial_length+w.half_width*w.half_width*axial*axial)
 var p: Vector3=radial.normalized()*w.rim_radius if radial_length>1e-8 else Vector3.ZERO
 if denom>1e-8:
  p+=(radial*shoulder*shoulder+axle*(axial*w.half_width*w.half_width))/denom
 return p

func constrain_knuckles(dt: float) -> void:
 var g: RefCounted=graph.get_ref()
 for w in wheels:
  if w.joint_broken:continue
  var a: int=w.body_nodes[0]
  var b: int=w.body_nodes[1]
  var span: Vector3=g.points[b]-g.points[a]
  var length: float=span.length()
  if length<.05:continue
  var z: Vector3=span/length
  var y: Vector3=(g.points[w.body_nodes[2]]+g.points[w.body_nodes[3]]-g.points[a]-g.points[b])*.5
  y=(y-z*y.dot(z)).normalized()
  var frame: Basis=Basis(y.cross(z),y,z)*Basis(Vector3.UP,-w.steering_angle)
  var desired: Vector3=frame*w.alignment
  var axle: Vector3=Basis(w.rotation).z
  var cross_axis: Vector3=axle.cross(desired)
  var sine: float=cross_axis.length()
  if sine<1e-7:continue
  var n: Vector3=cross_axis/sine
  var angle: float=atan2(sine,clampf(axle.dot(desired),-1,1))
  var ga: Vector3=-n.cross(z)/length
  var gb: Vector3=-ga
  var weight: float=n.dot(inverse_inertia(w,n))+ga.length_squared()*g.inverse_masses[a]+gb.length_squared()*g.inverse_masses[b]
  var alpha: float=1.0/(w.joint_stiffness*dt*dt)
  var dl: float=(-angle-alpha*w.joint_lambda)/(weight+alpha)
  var trial: float=w.joint_lambda+dl
  var torque: float=absf(trial)/(dt*dt)
  w.joint_peak=maxf(w.joint_peak,torque)
  if torque>w.joint_yield:
   var plastic: float=maxf(0,angle-w.joint_yield/w.joint_stiffness)
   if plastic>0:
    w.alignment=(frame.transposed()*(Quaternion(n,-plastic)*desired)).normalized()
    angle-=plastic
    g.plastic_work+=plastic*w.joint_yield
    dl=(-angle-alpha*w.joint_lambda)/(weight+alpha)
  w.joint_lambda+=dl
  _rotate(w,inverse_inertia(w,-n)*dl)
  g.points[a]+=ga*(g.inverse_masses[a]*dl)
  g.points[b]+=gb*(g.inverse_masses[b]*dl)

func contacts(dt: float) -> void:
 var g: RefCounted=graph.get_ref()
 for index in wheels.size():
  var w: Wheel=wheels[index]
  var floor_offset: Vector3=support(w,Vector3.DOWN)
  _world_contact(index,Vector3.UP,g.points[w.node].y+floor_offset.y,floor_offset,0,dt)
  if g.barrier_enabled and g.points[w.node].x>=g.barrier_min.x-w.radius:
   var hit: Dictionary=g.barrier_distance(g.points[w.node])
   var offset: Vector3=support(w,-hit.normal)
   _world_contact(index,hit.normal,float(hit.distance)+hit.normal.dot(offset),offset,1,dt)
  if body_contact_enabled:
   for c in w.capsules.size():
    _body_contact(index,c,dt)

func _world_contact(index: int,n: Vector3,c: float,r: Vector3,slot: int,dt: float) -> void:
 var w: Wheel=wheels[index]
 var g: RefCounted=graph.get_ref()
 if c>=0 and w.contact_lambdas[slot]<=0:return
 var weight: float=g.inverse_masses[w.node]+rotational_weight(index,r,n)
 var alpha: float=w.compliance/(dt*dt)
 var old: float=w.contact_lambdas[slot]
 var impulse: float=maxf(0,old+(-c-alpha*old)/(weight+alpha))-old
 w.contact_lambdas[slot]+=impulse
 g.points[w.node]+=n*(g.inverse_masses[w.node]*impulse)
 correct_rotation(index,r,n,impulse)
 # Once the tire's allowed compression is exhausted, the hard rim carries load.
 var remaining: float=c+weight*impulse+w.max_compression
 if remaining<0:
  var hard: float=-remaining/weight
  g.points[w.node]+=n*(g.inverse_masses[w.node]*hard)
  correct_rotation(index,r,n,hard)
  w.contact_lambdas[slot]+=hard
 w.tire_compression=maxf(w.tire_compression,minf(w.max_compression,maxf(0,-c-weight*impulse)))
 w.peak_compression=maxf(w.peak_compression,w.tire_compression)
 if slot==0:g.contact_floor[w.node]=1
 else:
  g.contact_wall[w.node]=1
  g.mark_impact(w.node)
 # Replace this slot on each iteration; friction runs once after all positions.
 var record: Dictionary={'slot':slot,'normal':n,'offset':r}
 var found:=false
 for j in w.contacts.size():
  if w.contacts[j].slot==slot:
   w.contacts[j]=record
   found=true
 if not found:w.contacts.append(record)

func _body_contact(index: int,capsule: int,dt: float) -> void:
 var w: Wheel=wheels[index]
 var g: RefCounted=graph.get_ref()
 var cap: Dictionary=w.capsules[capsule]
 var a: int=cap.a
 var b: int=cap.b
 var ab: Vector3=g.points[b]-g.points[a]
 var t: float=clampf((g.points[w.node]-g.points[a]).dot(ab)/maxf(1e-8,ab.length_squared()),0,1)
 var delta: Vector3=g.points[w.node]-g.points[a].lerp(g.points[b],t)
 var distance: float=delta.length()
 if distance<1e-8 or distance>w.radius+float(cap.radius_m)+.01:return
 var n: Vector3=delta/distance
 var r: Vector3=support(w,-n)
 var c: float=distance+n.dot(r)-float(cap.radius_m)
 var old: float=w.body_lambdas[capsule]
 if c>=0 and old<=0:return
 var wa: float=1-t
 var wb: float=t
 var weight: float=g.inverse_masses[w.node]+rotational_weight(index,r,n)+wa*wa*g.inverse_masses[a]+wb*wb*g.inverse_masses[b]
 var alpha: float=w.compliance/(dt*dt)
 var impulse: float=maxf(0,old+(-c-alpha*old)/(weight+alpha))-old
 var remaining: float=c+weight*impulse+w.max_compression
 if remaining<0:impulse+=-remaining/weight
 w.body_lambdas[capsule]+=impulse
 g.points[w.node]+=n*(g.inverse_masses[w.node]*impulse)
 correct_rotation(index,r,n,impulse)
 g.points[a]-=n*(g.inverse_masses[a]*wa*impulse)
 g.points[b]-=n*(g.inverse_masses[b]*wb*impulse)
 if impulse>0:
  w.body_impulse+=impulse/dt
  w.maximum_body_impulse=maxf(w.maximum_body_impulse,impulse/dt)
  w.contact_events+=1
  g.node_contact[a]=maxf(g.node_contact[a],.3)
  g.node_contact[b]=maxf(g.node_contact[b],.3)

func finish_step(dt: float) -> void:
 var g: RefCounted=graph.get_ref()
 for index in wheels.size():
  var w: Wheel=wheels[index]
  var delta: Quaternion=(w.rotation*w.previous_rotation.inverse()).normalized()
  if delta.w<0:delta=Quaternion(-delta.x,-delta.y,-delta.z,-delta.w)
  # atan2 preserves the sign and precision of very small rotations.
  # Quaternion.get_axis()/get_angle() loses this near identity in float32.
  var imaginary:=Vector3(delta.x,delta.y,delta.z)
  var sine: float=imaginary.length()
  w.angular_velocity=imaginary*(2.0*atan2(sine,delta.w)/(dt*sine)) if sine>1e-10 else Vector3.ZERO
  var axle: Vector3=Basis(w.rotation).z
  w.angular_velocity-=axle*w.angular_velocity.dot(axle)
  for contact in w.contacts:
   var n: Vector3=contact.normal
   var r: Vector3=contact.offset
   var omega: Vector3=w.angular_velocity+axle*w.spin_speed
   var velocity: Vector3=g.velocities[w.node]+omega.cross(r)
   var vn: float=velocity.dot(n)
   var weight: float=g.inverse_masses[w.node]+rotational_weight(index,r,n)
   var normal_impulse: float=maxf(0,-vn/weight)
   _velocity_impulse(w,r,n*normal_impulse)
   velocity=g.velocities[w.node]+(w.angular_velocity+axle*w.spin_speed).cross(r)
   var tangent: Vector3=velocity-n*velocity.dot(n)
   var length: float=tangent.length()
   if length>1e-8:
    var direction: Vector3=tangent/length
    var torque: Vector3=r.cross(direction)
    var friction_weight: float=g.inverse_masses[w.node]+torque.dot(inverse_inertia(w,torque,true))
    var normal_budget: float=w.contact_lambdas[contact.slot]/dt+normal_impulse
    var friction: float=minf(length/friction_weight,friction_coefficient*normal_budget)
    _velocity_impulse(w,r,-direction*friction)
   if int(contact.slot)==1:g.last_impulse+=normal_impulse+w.contact_lambdas[1]/dt
  # Low bearing/rolling loss; no isotropic fake sliding friction on the hub.
  w.spin_speed*=exp(-.012*dt)
  var active:=0
  for l in w.links:
   if not l.broken:active+=1
  var overloaded: bool=w.joint_peak>w.joint_break or w.alignment.dot(Vector3.BACK)<cos(deg_to_rad(45))
  w.joint_overload=maxf(0,w.joint_overload+(dt if overloaded else -2*dt))
  if active==0 or w.joint_overload>.012:w.joint_broken=true
  w.detached=active==0

func _velocity_impulse(w: Wheel,r: Vector3,impulse: Vector3) -> void:
 var g: RefCounted=graph.get_ref()
 g.velocities[w.node]+=impulse*g.inverse_masses[w.node]
 var torque: Vector3=r.cross(impulse)
 w.angular_velocity+=inverse_inertia(w,torque)
 w.spin_speed+=torque.dot(Basis(w.rotation).z)/w.inertia_spin

func kinetic_energy() -> float:
 var energy:=0.0
 for w in wheels:
  energy+=.5*w.inertia_tilt*w.angular_velocity.length_squared()+.5*w.inertia_spin*w.spin_speed*w.spin_speed
 return energy

func render_basis(index: int) -> Basis:
 var w: Wheel=wheels[index]
 return Basis(w.rotation)*Basis(Vector3.BACK,w.spin)

func capture() -> Array:
 var states: Array=[]
 for w in wheels:
  states.append({'steering_angle':w.steering_angle,'alignment':w.alignment,'joint_broken':w.joint_broken,'rotation':w.rotation,'angular_velocity':w.angular_velocity,'spin':w.spin,'spin_speed':w.spin_speed,'compression':w.tire_compression,'peak_compression':w.peak_compression,'detached':w.detached,'body_impulse':w.body_impulse,'body_events':w.contact_events})
 return states

func restore(states: Array) -> void:
 for i in wheels.size():
  var w: Wheel=wheels[i]
  var s: Dictionary=states[i]
  w.steering_angle=s.steering_angle
  w.alignment=s.alignment
  w.joint_broken=s.joint_broken
  w.rotation=s.rotation
  w.angular_velocity=s.angular_velocity
  w.spin=s.spin
  w.spin_speed=s.spin_speed
  w.tire_compression=s.compression
  w.peak_compression=s.peak_compression
  w.detached=s.detached
  w.body_impulse=s.body_impulse
  w.contact_events=s.body_events

func metrics() -> Array:
 var g: RefCounted=graph.get_ref()
 var result: Array=[]
 for w in wheels:
  var body_axis: Vector3=(g.points[w.body_nodes[1]]-g.points[w.body_nodes[0]]).normalized()
  result.append({'node':w.node,'name':g.config.nodes[w.node].name,'detached':w.detached,'knuckle_broken':w.joint_broken,'permanent_alignment_deg':rad_to_deg(acos(clampf(w.alignment.dot(Vector3.BACK),-1,1))),'hub_tilt_deg':rad_to_deg(acos(clampf(Basis(w.rotation).z.dot(body_axis),-1,1))),'spin_rad_s':w.spin_speed,'peak_tire_compression_m':w.peak_compression,'wheel_body_constraint_impulse_ns':w.body_impulse,'body_contact_events':w.contact_events,'angular_finite':w.rotation.is_finite() and w.angular_velocity.is_finite() and is_finite(w.spin_speed)})
 return result
