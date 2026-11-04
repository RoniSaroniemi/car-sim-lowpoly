extends RefCounted
## One rigid aggregate owns the existing body-node masses in clear-road mode.
## Wheel masses/rotations remain independent; no extra physical chassis is added.
var graph: WeakRef
var mass:=0.0
var indices:=PackedInt32Array()
var mask:=PackedByteArray()
var local_points:=PackedVector3Array()
var inertia:=Basis.IDENTITY
var inverse_inertia_local:=Basis.IDENTITY
var center:=Vector3.ZERO
var rotation:=Quaternion.IDENTITY
var linear_velocity:=Vector3.ZERO
var angular_velocity:=Vector3.ZERO
var old_center:=Vector3.ZERO
var old_rotation:=Quaternion.IDENTITY
var suspension_links: Array=[]
var iterations:=3
var expected_wheel_angular:=PackedVector3Array()
var expected_wheel_velocity:=PackedVector3Array()
var wake_reason: String=''

func setup(owner: RefCounted) -> void:
 graph=weakref(owner)
 mask.resize(owner.rest.size())
 local_points.resize(owner.rest.size())
 expected_wheel_angular.resize(owner.wheels.wheels.size())
 expected_wheel_velocity.resize(owner.wheels.wheels.size())
 for i in owner.rest.size():
  if i not in owner.wheels.by_node:
   indices.append(i)
   mask[i]=1
   mass+=owner.masses[i]
 for link in owner.links:
  if link.wheel_index>=0:suspension_links.append(link)

func capture_shape() -> void:
 var g: RefCounted=graph.get_ref()
 center=Vector3.ZERO
 linear_velocity=Vector3.ZERO
 rotation=Quaternion.IDENTITY
 for i in indices:
  center+=g.points[i]*g.masses[i]
  linear_velocity+=g.velocities[i]*g.masses[i]
 center/=mass
 linear_velocity/=mass
 var xx:=0.0;var yy:=0.0;var zz:=0.0
 var xy:=0.0;var xz:=0.0;var yz:=0.0
 var momentum:=Vector3.ZERO
 for i in indices:
  var p: Vector3=g.points[i]-center
  local_points[i]=p
  var m: float=g.masses[i]
  xx+=m*(p.y*p.y+p.z*p.z)
  yy+=m*(p.x*p.x+p.z*p.z)
  zz+=m*(p.x*p.x+p.y*p.y)
  xy-=m*p.x*p.y;xz-=m*p.x*p.z;yz-=m*p.y*p.z
  momentum+=p.cross((g.velocities[i]-linear_velocity)*m)
 inertia=Basis(Vector3(xx,xy,xz),Vector3(xy,yy,yz),Vector3(xz,yz,zz))
 inverse_inertia_local=inertia.inverse()
 angular_velocity=inverse_inertia_local*momentum
 wake_reason=''
 _cache_wheel_motion()

func point(i: int) -> Vector3:
 return center+Basis(rotation)*local_points[i]

func point_velocity(i: int) -> Vector3:
 return linear_velocity+angular_velocity.cross(point(i)-center)

func inverse_inertia(torque: Vector3) -> Vector3:
 var frame:=Basis(rotation)
 return frame*(inverse_inertia_local*(frame.transposed()*torque))

func _rotate(delta: Vector3) -> void:
 var angle: float=delta.length()
 if angle>1e-10:rotation=(Quaternion(delta/angle,minf(angle,.20))*rotation).normalized()

func constraint_weight(a: int,b: int,ga: Vector3,gb: Vector3) -> float:
 var g: RefCounted=graph.get_ref()
 var force:=Vector3.ZERO
 var torque:=Vector3.ZERO
 var weight:=0.0
 for pair in [[a,ga],[b,gb]]:
  var i: int=pair[0]
  var gradient: Vector3=pair[1]
  if i<0:continue
  if mask[i]:
   force+=gradient
   torque+=(point(i)-center).cross(gradient)
  else:weight+=g.inverse_masses[i]*gradient.length_squared()
 return weight+force.length_squared()/mass+torque.dot(inverse_inertia(torque))

func correct(a: int,b: int,ga: Vector3,gb: Vector3,impulse: float,velocity_only: bool=false) -> void:
 var g: RefCounted=graph.get_ref()
 var force:=Vector3.ZERO
 var torque:=Vector3.ZERO
 for pair in [[a,ga],[b,gb]]:
  var i: int=pair[0]
  var gradient: Vector3=pair[1]
  if i<0:continue
  if mask[i]:
   force+=gradient
   torque+=(point(i)-center).cross(gradient)
  elif velocity_only:g.velocities[i]+=gradient*(g.inverse_masses[i]*impulse)
  else:g.points[i]+=gradient*(g.inverse_masses[i]*impulse)
 if velocity_only:
  linear_velocity+=force*(impulse/mass)
  angular_velocity+=inverse_inertia(torque)*impulse
 else:
  center+=force*(impulse/mass)
  _rotate(inverse_inertia(torque)*impulse)

func flush() -> void:
 var g: RefCounted=graph.get_ref()
 var frame:=Basis(rotation)
 for i in indices:
  var arm: Vector3=frame*local_points[i]
  g.points[i]=center+arm
  g.velocities[i]=linear_velocity+angular_velocity.cross(arm)
 _cache_wheel_motion()

func _cache_wheel_motion() -> void:
 var g: RefCounted=graph.get_ref()
 for i in g.wheels.wheels.size():
  var w=g.wheels.wheels[i]
  expected_wheel_angular[i]=w.angular_velocity
  expected_wheel_velocity[i]=g.velocities[w.node]

func external_change() -> bool:
 # Direct test-fixture impulses/edits must not disappear inside the aggregate.
 var g: RefCounted=graph.get_ref()
 for i in indices:
  if g.points[i].distance_squared_to(point(i))>.000001:return true
  if g.velocities[i].distance_squared_to(point_velocity(i))>.0625:return true
 for i in g.wheels.wheels.size():
  var w=g.wheels.wheels[i]
  # Detect edits since our last step, not internally generated yaw/tilt speed.
  if w.angular_velocity.distance_squared_to(expected_wheel_angular[i])>9.0:return true
  if g.velocities[w.node].distance_squared_to(expected_wheel_velocity[i])>.0625:return true
 return false

func step(dt: float) -> void:
 var g: RefCounted=graph.get_ref()
 wake_reason=''
 # Read distributed external forces (e.g. drag) back into the same body mass.
 linear_velocity=Vector3.ZERO
 var momentum:=Vector3.ZERO
 for i in indices:linear_velocity+=g.velocities[i]*g.masses[i]
 linear_velocity/=mass
 for i in indices:momentum+=(point(i)-center).cross((g.velocities[i]-linear_velocity)*g.masses[i])
 angular_velocity=inverse_inertia(momentum)
 old_center=center
 old_rotation=rotation
 linear_velocity.y-=float(g.config.gravity_mps2)*dt
 center+=linear_velocity*dt
 _rotate(angular_velocity*dt)
 g.wheels.predict(dt)
 g.contact_wall.fill(0)
 g.contact_floor.fill(0)
 for w in g.wheels.wheels:
  var i: int=w.node
  g.old_points[i]=g.points[i]
  g.velocities[i].y-=float(g.config.gravity_mps2)*dt
  g.points[i]+=g.velocities[i]*dt
 for link in suspension_links:
  link.lambda=0
  link.peak_force=0
 for iteration in iterations:
  for offset in suspension_links.size():
   var index: int=offset if iteration%2==0 else suspension_links.size()-1-offset
   g._solve_link(suspension_links[index],dt)
  g.wheels.constrain_lateral_mounts(dt)
  g.wheels.constrain_knuckles(dt)
  g.wheels.contacts(dt)
 linear_velocity=(center-old_center)/dt
 var delta: Quaternion=(rotation*old_rotation.inverse()).normalized()
 if delta.w<0:delta=Quaternion(-delta.x,-delta.y,-delta.z,-delta.w)
 var imaginary:=Vector3(delta.x,delta.y,delta.z)
 var sine: float=imaginary.length()
 angular_velocity=imaginary*(2.0*atan2(sine,delta.w)/(dt*sine)) if sine>1e-10 else Vector3.ZERO
 for w in g.wheels.wheels:
  g.velocities[w.node]=(g.points[w.node]-g.old_points[w.node])/dt
 g.wheels.finish_step(dt)
 g._damping(dt)
 g._break_links(dt)
 flush()
 g.simulated_time+=dt
 g.maximum_energy=maxf(g.maximum_energy,g.kinetic_energy())
