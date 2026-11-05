extends RefCounted
## Four finite-width rigid assemblies; hub tilt and bearing spin are separate.
## Translation/mass lives in the structural graph, never in a second rigid body.
class Wheel:
 var links: Array=[]
 var body_nodes: Array=[]
 var steering_angle:=0.0
 var alignment:=Vector3.BACK
 var joint_impulse:=Vector3.ZERO
 var rigid_mount:=true
 var lateral_rest:=0.0
 var initial_lateral_rest:=0.0
 var lateral_lambda:=0.0
 var lateral_peak:=0.0
 var lateral_yield:=18000.0
 var lateral_break:=90000.0
 var lateral_overload:=0.0
 var mount_break_delay:=.035
 var detach_alignment:=deg_to_rad(65)
 var detach_offset:=.20
 var detach_reason: String=''
 var joint_peak:=0.0
 var joint_overload:=0.0
 var joint_broken:=false
 var joint_stiffness:=24000.0
 var joint_yield:=6500.0
 var joint_break:=18000.0
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
  w.rigid_mount=raw.get('rigid_mount_until_yield',true)
  w.lateral_yield=raw.get('lateral_yield_n',18000.0)
  w.lateral_break=raw.get('lateral_break_n',90000.0)
  w.mount_break_delay=raw.get('mount_break_delay_s',.035)
  w.detach_alignment=deg_to_rad(raw.get('detach_alignment_deg',65.0))
  w.detach_offset=raw.get('detach_lateral_offset_m',.20)
  w.body_nodes=raw.axle_body_nodes
  var a: int=w.body_nodes[0]
  var b: int=w.body_nodes[1]
  var axis: Vector3=(owner.rest[b]-owner.rest[a]).normalized()
  var centre: Vector3=(owner.rest[a]+owner.rest[b])*.5
  var origin: int=b if (owner.rest[w.node]-centre).dot(axis)>0 else a
  w.initial_lateral_rest=(owner.rest[w.node]-owner.rest[origin]).dot(axis)
  w.lateral_rest=w.initial_lateral_rest
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
  w.joint_impulse=Vector3.ZERO
  w.lateral_lambda=0
  w.lateral_peak=0
  w.joint_peak=0
  w.joint_overload=0
  w.lateral_overload=0
  w.lateral_rest=w.initial_lateral_rest
  w.detach_reason=''
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
 for index in wheels.size():predict_one(index,dt)

func predict_one(index: int,dt: float) -> void:
 var w: Wheel=wheels[index]
 w.previous_rotation=w.rotation
 w.joint_impulse=Vector3.ZERO
 w.lateral_lambda=0
 w.lateral_peak=0
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

func _limited_increment(previous: Vector3,axis: Vector3,requested: float,limit: float) -> float:
 # Keep the accumulated angular impulse inside the yield ball. The axis can
 # reverse between sweeps, so a scalar unsigned-angle multiplier is insufficient.
 var along: float=previous.dot(axis)
 var perpendicular_squared: float=maxf(0,previous.length_squared()-along*along)
 var available: float=sqrt(maxf(0,limit*limit-perpendicular_squared))
 return clampf(requested,-along-available,-along+available)

func _mount_origin(w: Wheel) -> int:
 return w.body_nodes[1] if w.initial_lateral_rest>0 else w.body_nodes[0]

func lateral_error(w: Wheel) -> float:
 var g: RefCounted=graph.get_ref()
 var axis: Vector3=(g.point(w.body_nodes[1])-g.point(w.body_nodes[0])).normalized()
 return (g.point(w.node)-g.point(_mount_origin(w))).dot(axis)-w.lateral_rest

func constrain_lateral_mounts(dt: float) -> void:
 var g: RefCounted=graph.get_ref()
 for w in wheels:
  if w.detached:continue
  var a: int=w.body_nodes[0]
  var b: int=w.body_nodes[1]
  var span: Vector3=g.point(b)-g.point(a)
  var length: float=span.length()
  if length<.05:continue
  var z: Vector3=span/length
  var origin: int=_mount_origin(w)
  var arm: Vector3=g.point(w.node)-g.point(origin)
  var coordinate: float=arm.dot(z)
  var transverse: Vector3=(arm-z*coordinate)/length
  # These derivatives also react against rotation of the deforming body axis.
  var ga: Vector3=-transverse-(z if origin==a else Vector3.ZERO)
  var gb: Vector3=transverse-(z if origin==b else Vector3.ZERO)
  var weight: float=g.inverse_masses[w.node]+g.constraint_weight(a,b,ga,gb)
  var c: float=coordinate-w.lateral_rest
  var requested: float=-c/weight
  var trial: float=w.lateral_lambda+requested
  w.lateral_peak=maxf(w.lateral_peak,absf(trial)/(dt*dt))
  if g.compact_active and w.lateral_peak>w.lateral_yield*.8:g.compact.wake_reason='lateral_load'
  var capped: float=clampf(trial,-w.lateral_yield*dt*dt,w.lateral_yield*dt*dt)
  var dl: float=capped-w.lateral_lambda
  if absf(trial)>w.lateral_yield*dt*dt:
   # Move the permanent mount target only by the unresolved plastic displacement.
   var new_rest: float=coordinate+weight*dl
   g.plastic_work+=w.lateral_yield*absf(new_rest-w.lateral_rest)
   w.lateral_rest=new_rest
  w.lateral_lambda=capped
  g.points[w.node]+=z*(g.inverse_masses[w.node]*dl)
  g.correct_constraint(a,b,ga,gb,dl)

func constrain_knuckles(dt: float) -> void:
 var g: RefCounted=graph.get_ref()
 for w in wheels:
  if w.detached or w.joint_broken:continue
  var a: int=w.body_nodes[0]
  var b: int=w.body_nodes[1]
  var span: Vector3=g.point(b)-g.point(a)
  var length: float=span.length()
  if length<.05:continue
  var z: Vector3=span/length
  var y: Vector3=(g.point(w.body_nodes[2])+g.point(w.body_nodes[3])-g.point(a)-g.point(b))*.5
  y=(y-z*y.dot(z)).normalized()
  var frame: Basis=Basis(y.cross(z),y,z)*Basis(Vector3.UP,w.steering_angle)
  var desired: Vector3=frame*w.alignment
  var axle: Vector3=Basis(w.rotation).z
  var cross_axis: Vector3=axle.cross(desired)
  var sine: float=cross_axis.length()
  if sine<1e-7:continue
  var n: Vector3=cross_axis/sine
  var angle: float=atan2(sine,clampf(axle.dot(desired),-1,1))
  var ga: Vector3=n.cross(z)/length
  var gb: Vector3=-ga
  var weight: float=n.dot(inverse_inertia(w,n))+g.constraint_weight(a,b,ga,gb)
  var alpha: float=0.0 if w.rigid_mount else 1.0/(w.joint_stiffness*dt*dt)
  var along: float=w.joint_impulse.dot(n)
  var requested: float=(angle-alpha*along)/(weight+alpha)
  var trial: Vector3=w.joint_impulse+n*requested
  var torque: float=trial.length()/(dt*dt)
  w.joint_peak=maxf(w.joint_peak,torque)
  if g.compact_active and torque>w.joint_yield*.8:g.compact.wake_reason='angular_load'
  var impulse: float=_limited_increment(w.joint_impulse,n,requested,w.joint_yield*dt*dt)
  if torque>w.joint_yield:
   var plastic: float=maxf(0,angle-weight*impulse-alpha*(along+impulse))
   if plastic>0:
    w.alignment=(frame.transposed()*(Quaternion(n,-plastic)*desired)).normalized()
    g.plastic_work+=plastic*w.joint_yield
  w.joint_impulse+=n*impulse
  _rotate(w,inverse_inertia(w,n)*impulse)
  g.correct_constraint(a,b,ga,gb,impulse)

func detach(w: Wheel,reason: String) -> void:
 # A mount failure releases every constraint. No teleport, velocity rewrite,
 # mass handoff or residual angular/lateral tether is introduced here.
 if w.detached:return
 w.detached=true
 w.joint_broken=true
 w.detach_reason=reason
 w.joint_impulse=Vector3.ZERO
 w.lateral_lambda=0
 for l in w.links:
  l.broken=true
  l.lambda=0
  l.damage=1.0

func contacts(dt: float) -> void:
 for index in wheels.size():contacts_one(index,dt)

func contacts_one(index: int,dt: float,include_body: bool=true) -> void:
 var g: RefCounted=graph.get_ref()
 var w: Wheel=wheels[index]
 var surface: Vector4=g.floor_sample(g.point(w.node))
 var floor_normal:=Vector3(surface.x,surface.y,surface.z)
 var floor_offset: Vector3=support(w,-floor_normal)
 var floor_distance: float=(g.point(w.node).y-surface.w)*surface.y+floor_normal.dot(floor_offset)
 _world_contact(index,floor_normal,floor_distance,floor_offset,0,dt)
 if g.barrier_enabled and g.point(w.node).x>=g.barrier_min.x-w.radius:
  var hit: Dictionary=g.barrier_distance(g.point(w.node))
  var offset: Vector3=support(w,-hit.normal)
  _world_contact(index,hit.normal,float(hit.distance)+hit.normal.dot(offset),offset,1,dt)
 if body_contact_enabled and include_body:
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
 var ab: Vector3=g.point(b)-g.point(a)
 var t: float=clampf((g.point(w.node)-g.point(a)).dot(ab)/maxf(1e-8,ab.length_squared()),0,1)
 var delta: Vector3=g.point(w.node)-g.point(a).lerp(g.point(b),t)
 var distance: float=delta.length()
 if distance<1e-8 or distance>w.radius+float(cap.radius_m)+.01:return
 var n: Vector3=delta/distance
 var r: Vector3=support(w,-n)
 var c: float=distance+n.dot(r)-float(cap.radius_m)
 var old: float=w.body_lambdas[capsule]
 if c>=0 and old<=0:return
 var wa: float=1-t
 var wb: float=t
 var weight: float=g.inverse_masses[w.node]+rotational_weight(index,r,n)+g.constraint_weight(a,b,-n*wa,-n*wb)
 var alpha: float=w.compliance/(dt*dt)
 var impulse: float=maxf(0,old+(-c-alpha*old)/(weight+alpha))-old
 var remaining: float=c+weight*impulse+w.max_compression
 if remaining<0:impulse+=-remaining/weight
 w.body_lambdas[capsule]+=impulse
 g.points[w.node]+=n*(g.inverse_masses[w.node]*impulse)
 correct_rotation(index,r,n,impulse)
 g.correct_constraint(a,b,-n*wa,-n*wb,impulse)
 if impulse>0:
  if g.compact_active:g.compact.wake_reason='wheel_body_contact'
  w.body_impulse+=impulse/dt
  w.maximum_body_impulse=maxf(w.maximum_body_impulse,impulse/dt)
  w.contact_events+=1
  g.node_contact[a]=maxf(g.node_contact[a],.3)
  g.node_contact[b]=maxf(g.node_contact[b],.3)

func finish_step(dt: float) -> void:
 for index in wheels.size():finish_one(index,dt)

func finish_one(index: int,dt: float) -> void:
 var g: RefCounted=graph.get_ref()
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
 var angular_overload: bool=w.joint_peak>w.joint_break
 w.joint_overload=maxf(0,w.joint_overload+(dt if angular_overload else -2*dt))
 w.lateral_overload=maxf(0,w.lateral_overload+(dt if w.lateral_peak>w.lateral_break else -2*dt))
 var angle: float=acos(clampf(w.alignment.dot(Vector3.BACK),-1,1))
 if active==0:detach(w,'suspension')
 elif angle>=w.detach_alignment:detach(w,'permanent_alignment')
 elif absf(w.lateral_rest-w.initial_lateral_rest)>=w.detach_offset:detach(w,'permanent_lateral_offset')
 elif w.joint_overload>=w.mount_break_delay:detach(w,'angular_overload')
 elif w.lateral_overload>=w.mount_break_delay:detach(w,'lateral_overload')

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
  states.append({'lateral_rest':w.lateral_rest,'detach_reason':w.detach_reason,'steering_angle':w.steering_angle,'alignment':w.alignment,'joint_broken':w.joint_broken,'rotation':w.rotation,'angular_velocity':w.angular_velocity,'spin':w.spin,'spin_speed':w.spin_speed,'compression':w.tire_compression,'peak_compression':w.peak_compression,'detached':w.detached,'body_impulse':w.body_impulse,'body_events':w.contact_events})
 return states

func restore(states: Array) -> void:
 for i in wheels.size():
  var w: Wheel=wheels[i]
  var s: Dictionary=states[i]
  w.lateral_rest=s.lateral_rest
  w.detach_reason=s.detach_reason
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
  var body_axis: Vector3=(g.point(w.body_nodes[1])-g.point(w.body_nodes[0])).normalized()
  result.append({'lateral_error_m':lateral_error(w),'permanent_lateral_offset_m':w.lateral_rest-w.initial_lateral_rest,'peak_lateral_force_n':w.lateral_peak,'detach_reason':w.detach_reason,'node':w.node,'name':g.config.nodes[w.node].name,'detached':w.detached,'knuckle_broken':w.joint_broken,'permanent_alignment_deg':rad_to_deg(acos(clampf(w.alignment.dot(Vector3.BACK),-1,1))),'hub_tilt_deg':rad_to_deg(acos(clampf(Basis(w.rotation).z.dot(body_axis),-1,1))),'spin_rad_s':w.spin_speed,'peak_tire_compression_m':w.peak_compression,'wheel_body_constraint_impulse_ns':w.body_impulse,'body_contact_events':w.contact_events,'angular_finite':w.rotation.is_finite() and w.angular_velocity.is_finite() and is_finite(w.spin_speed)})
 return result
