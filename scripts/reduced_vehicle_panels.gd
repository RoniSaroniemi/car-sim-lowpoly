extends RefCounted
## Frozen plastic shape, reduced rigid momentum, and reciprocal two-point hinges.
const AngularMount=preload('res://scripts/panel_angular_mount.gd')
const Attachment=preload('res://scripts/car_attachment.gd')
var graph: RefCounted
var system: RefCounted
var compact: RefCounted
var reduced_steps:=0
var full_wakes:=0
var transitions: Array=[]
var projection_energy_j:=0.0
var damping_energy_j:=0.0
var contacts:=0
var step_costs: Array=[]
var control:=true

func setup(owner: RefCounted,aggregate: RefCounted=null) -> void:
 graph=owner;system=owner.panels;compact=aggregate
 for p in system.panels:p['reduced_mode']='asleep_closed';p['reduced']=false

func _inertia(p: Dictionary,offsets: PackedVector3Array) -> Basis:
 var xx:=0.0;var yy:=0.0;var zz:=0.0;var xy:=0.0;var xz:=0.0;var yz:=0.0
 for r in offsets:
  var m: float=p.mass/10
  xx+=m*(r.y*r.y+r.z*r.z);yy+=m*(r.x*r.x+r.z*r.z);zz+=m*(r.x*r.x+r.y*r.y);xy-=m*r.x*r.y;xz-=m*r.x*r.z;yz-=m*r.y*r.z
 return Basis(Vector3(xx,xy,xz),Vector3(xy,yy,yz),Vector3(xz,yz,zz))

func freeze(p: Dictionary) -> void:
 if not p.active:return
 var before: Dictionary=system.momentum();var points: PackedVector3Array=p.points.duplicate();var velocities: PackedVector3Array=p.velocity.duplicate()
 var center:=Vector3.ZERO;var linear:=Vector3.ZERO
 for i in 10:center+=p.points[i]/10;linear+=p.velocity[i]/10
 var offsets:=PackedVector3Array();var angular_momentum:=Vector3.ZERO;var energy:=0.0
 for i in 10:offsets.append(p.points[i]-center);angular_momentum+=offsets[i].cross((p.velocity[i]-linear)*p.mass/10);energy+=.5*p.mass/10*p.velocity[i].length_squared()
 var inertia: Basis=_inertia(p,offsets)
 var omega: Vector3=inertia.inverse()*angular_momentum
 var rigid_energy: float=.5*p.mass*linear.length_squared()+.5*omega.dot(inertia*omega)
 projection_energy_j+=maxf(0,energy-rigid_energy)
 p['reduced_data']={'center':center,'rotation':Quaternion.IDENTITY,'linear':linear,'omega':omega,'offsets':offsets,'inverse_inertia':inertia.inverse(),'quiet':0.0,'sleep':false,'age':0.0,'old_mount_velocity':Vector3.ZERO}
 p.reduced=true;p.reduced_mode='detached' if p.detached else 'coarse_swing'
 # No pose/velocity write at the transfer boundary. Rigid projection preserves P/L;
 # non-rigid kinetic energy is explicitly reported and dissipated on next step.
 var after: Dictionary=system.momentum()
 transitions.append({'id':p.id,'to':p.reduced_mode,'time':system.clock,'pose_error_m':0.0 if points==p.points else INF,'velocity_error_mps':0.0 if velocities==p.velocity else INF,'linear_error_ns':before.linear.distance_to(after.linear),'angular_error_nms':before.angular.distance_to(after.angular),'removed_internal_energy_j':maxf(0,energy-rigid_energy)})

func _refresh_mass() -> void:
 if compact==null:return
 compact.mass=0
 for i in compact.indices:compact.mass+=graph.masses[i]
 compact.capture_shape();graph.compact_active=true

func dock(p: Dictionary) -> void:
 var frames: Array=Attachment.rotations(graph)
 var mount: Transform3D=Attachment.frame_with_rotations(graph,p.pivot,frames)
 var local:=PackedVector3Array()
 for point_ in p.points:local.append(mount.affine_inverse()*point_)
 p['frozen_local']=local
 var before: PackedVector3Array=p.points.duplicate()
 system._condense(p);p.reduced=false
 p.reduced_mode='frozen_plastic' if p.plastic_work>.01 or p.anchors.any(func(a):return a.broken) or p.get('closing_supports',[]).any(func(s):return s.broken) else 'asleep_closed'
 _refresh_mass();system.synchronize_inactive()
 transitions.append({'id':p.id,'to':p.reduced_mode,'time':system.clock,'pose_error_m':_error(before,p.points),'mass_kg':system.total_mass()})

func _error(a: PackedVector3Array,b: PackedVector3Array) -> float:
 var result:=0.0
 for i in a.size():result=maxf(result,a[i].distance_to(b[i]))
 return result

func set_open(id: String,degrees: float) -> bool:
 var p: Dictionary=system.find(id)
 if p.is_empty() or p.detached or p.anchors.any(func(a):return a.broken):return false
 if degrees>.1 and not p.active:
  system.activate(p);_refresh_mass();freeze(p)
 p.target=deg_to_rad(clampf(degrees,0,95 if id=='tailgate' else 82))
 if degrees>.1:
  p.latched=false
  if p.has('closing_engaged'):p.closing_engaged=false
 return true

func _inverse(p: Dictionary,v: Vector3) -> Vector3:
 var d: Dictionary=p.reduced_data;var b:=Basis(d.rotation)
 return b*(d.inverse_inertia*(b.transposed()*v))

func _rotate(p: Dictionary,v: Vector3) -> void:
 var angle: float=v.length()
 if angle>1e-9:p.reduced_data.rotation=(Quaternion(v/angle,minf(angle,.25))*p.reduced_data.rotation).normalized()

func _point(p: Dictionary,i: int) -> Vector3:
 var d: Dictionary=p.reduced_data
 return d.center+Basis(d.rotation)*d.offsets[i]

func _velocity(p: Dictionary,i: int) -> Vector3:
 var d: Dictionary=p.reduced_data
 return d.linear+d.omega.cross(_point(p,i)-d.center)

func _body_velocity(binding: Dictionary,target: Vector3) -> Vector3:
 if compact!=null:return compact.linear_velocity+compact.angular_velocity.cross(target-compact.center)
 var v:=Vector3.ZERO
 for k in binding.ids.size():v+=graph.velocities[binding.ids[k]]*binding.weights[k]
 return v

func _body_weight(target: Vector3,normal: Vector3) -> float:
 if compact==null:return 1/maxf(1,graph.body_mass_kg)
 var r: Vector3=target-compact.center
 return 1/compact.mass+r.cross(normal).dot(compact.inverse_inertia(r.cross(normal)))

func _body_impulse(target: Vector3,impulse: Vector3) -> void:
 if compact!=null:
  compact.linear_velocity+=impulse/compact.mass
  compact.angular_velocity+=compact.inverse_inertia((target-compact.center).cross(impulse))
 else:
  for i in graph.velocities.size():graph.velocities[i]+=impulse/graph.body_mass_kg

func _impulse(p: Dictionary,i: int,j: Vector3) -> void:
 var d: Dictionary=p.reduced_data
 d.linear+=j/p.mass;d.omega+=_inverse(p,(_point(p,i)-d.center).cross(j))

func _hinge(p: Dictionary,index: int,target: Vector3,h: float,axial_free: Vector3=Vector3.ZERO) -> void:
 var a: Dictionary=p.anchors[index];var point_: Vector3=_point(p,a.node)
 var r: Vector3=point_-p.reduced_data.center
 var target_velocity: Vector3=_body_velocity(a.binding,target)
 var normals: Array=[Vector3.RIGHT,Vector3.UP,Vector3.BACK]
 if axial_free.length_squared()>.5:
  var perpendicular: Vector3=axial_free.cross(Vector3.RIGHT if absf(axial_free.x)<.8 else Vector3.UP).normalized()
  normals=[perpendicular,axial_free.cross(perpendicular).normalized()]
 for normal in normals:
  var relative: Vector3=_velocity(p,a.node)-target_velocity
  var error: Vector3=point_-(target-target_velocity*h)
  var weight: float=1/p.mass+r.cross(normal).dot(_inverse(p,r.cross(normal)))+_body_weight(target,normal)
  var impulse: Vector3=normal*(-relative.dot(normal)-error.dot(normal)*.18/h)/maxf(.0001,weight)
  _impulse(p,a.node,impulse);_body_impulse(target,-impulse)

func _publish(p: Dictionary) -> void:
 for i in 10:p.points[i]=_point(p,i);p.velocity[i]=_velocity(p,i)
 p.old=p.points.duplicate()

func step(h: float,only_ids: Array=[],flush_body: bool=true) -> void:
 var began: int=Time.get_ticks_usec();system.clock+=h
 var frames: Array=Attachment.rotations(graph)
 for p in system.panels:
  if not p.active or not p.reduced or (not only_ids.is_empty() and p.id not in only_ids):continue
  reduced_steps+=1
  var d: Dictionary=p.reduced_data;d.age+=h
  if d.sleep:continue
  var old_center: Vector3=d.center;var old_rotation: Quaternion=d.rotation
  var old_linear: Vector3=d.linear;var old_omega: Vector3=d.omega
  d.linear.y-=9.81*h
  var mount: Transform3D=Attachment.frame_with_rotations(graph,p.pivot,frames)
  var hinge_axis: Vector3=mount.basis*Vector3.UP if p.side!=0 else mount.basis*Vector3.FORWARD
  var sign_: float=p.side if p.side!=0 else 1
  var arm: Vector3=_point(p,7)-(_point(p,0)+_point(p,2))*.5
  var base_arm: Vector3=mount.basis*(p.rest[7]-(p.rest[0]+p.rest[2])*.5)
  p.angle=atan2(hinge_axis.dot(base_arm.cross(arm)),base_arm.dot(arm))*sign_
  p.angular_speed=(d.omega-(compact.angular_velocity if compact!=null else Vector3.ZERO)).dot(hinge_axis)*sign_
  var intact: bool=not p.anchors.any(func(a):return a.broken)
  var torque: float=0
  if not p.detached:
   torque=-p.angular_speed*1.2
   if intact and not p.latched and control:
    var gravity_torque: float=hinge_axis.dot((d.center-(_point(p,0)+_point(p,2))*.5).cross(Vector3.DOWN*p.mass*9.81))*sign_
    torque=clampf((p.target-p.angle)*(80 if p.side else 280)-p.angular_speed*(18 if p.side else 55)-gravity_torque,-30 if p.side else -180,30 if p.side else 180)
   var limit: float=deg_to_rad(100 if p.id=='tailgate' else 96)
   if p.angle<0:torque+=-p.angle*450-p.angular_speed*18
   if p.angle>limit:torque+=(limit-p.angle)*450-p.angular_speed*18
   var angular_impulse: Vector3=hinge_axis*torque*sign_*h
   d.omega+=_inverse(p,angular_impulse)
   if compact!=null:compact.angular_velocity-=compact.inverse_inertia(angular_impulse)
   for iteration in 3:
    for k in 3:
     if p.anchors[k].broken or (k==2 and not p.latched):continue
     var target: Vector3=Attachment.mapped(graph,p.anchors[k].rest,p.anchors[k].binding,frames)
     _hinge(p,k,target,h,hinge_axis if k==1 and not p.anchors[0].broken else Vector3.ZERO)
    if p.get('closing_engaged',false):
     for seat in p.get('closing_supports',[]):
      if seat.broken:continue
      var target: Vector3=Attachment.mapped(graph,seat.rest,seat.binding,frames)
      _seat(p,seat,target,mount.basis*Vector3.BACK*float(p.side),h)
  AngularMount.reduced(self,p,frames,h)
  d.center+=d.linear*h;_rotate(p,d.omega*h)
  # Cheap finite support proxies; floor response is rigid impulse, not cage solving.
  var grounded:=false
  for i in [0,2,6,8,9]:
   var point_: Vector3=_point(p,i)
   var sample: Vector4=graph.floor_sample(point_)
   var floor_normal:=Vector3(sample.x,sample.y,sample.z).normalized()
   var depth: float=.04-(point_.y-sample.w)*floor_normal.y
   if depth>0:
    grounded=true
    d.center+=floor_normal*depth
    var r: Vector3=point_-d.center
    var weight: float=1/p.mass+r.cross(floor_normal).dot(_inverse(p,r.cross(floor_normal)))
    var vn: float=_velocity(p,i).dot(floor_normal)
    if vn<0:_impulse(p,i,floor_normal*(-vn/weight))
    var tangent: Vector3=_velocity(p,i);tangent-=floor_normal*tangent.dot(floor_normal)
    if tangent.length()>.0001:_impulse(p,i,-tangent.normalized()*minf(tangent.length()*p.mass/5,.7*p.mass*9.81*h/5))
    contacts+=1
   _wall_contact(p,i,old_center,old_rotation,h)
  # Angular damping is bearing/contact loss; report explicit loss.
  var energy_before: float=.5*p.mass*d.linear.length_squared()
  if p.detached:
   d.linear*=exp(-.08*h);d.omega*=exp(-(.18+1.5*float(grounded))*h)
  damping_energy_j+=maxf(0,energy_before-.5*p.mass*d.linear.length_squared())
  _stop(p,mount,hinge_axis,sign_,h)
  _publish(p)
  system.try_detach(p)
  if p.detached:p.reduced_mode='detached' if not d.sleep else 'detached_sleep'
  if not p.detached and not p.anchors[2].broken and p.target<.01 and absf(p.angle)<.008 and absf(p.angular_speed)<.05:
   p['close_quiet']=p.get('close_quiet',0.0)+h
   if p.close_quiet>.18:
    p.latched=true
    if p.has('closing_engaged'):p.closing_engaged=true
    dock(p)
  else:p.close_quiet=0.0
  if p.active and held_closed(p) and d.linear.length()<.1 and d.omega.length()<.1:dock(p)
  if p.detached:
   var rotation_basis:=Basis(d.rotation)
   var inertia_world: Basis=rotation_basis*d.inverse_inertia.inverse()*rotation_basis.transposed()
   var energy: float=.5*p.mass*d.linear.length_squared()+.5*d.omega.dot(inertia_world*d.omega)
   d.quiet=d.quiet+h if grounded and energy<.3 else 0.0
   if d.quiet>.5:
    d.sleep=true;p.reduced_mode='detached_sleep';d.linear=Vector3.ZERO;d.omega=Vector3.ZERO;damping_energy_j+=energy;_publish(p)
 if compact!=null and flush_body:compact.flush()
 system.pose_revision+=1
 system.synchronize_inactive()
 step_costs.append(Time.get_ticks_usec()-began)

func wake_impact(p: Dictionary) -> void:
 if not p.active:system.activate(p);_refresh_mass()
 p.reduced=false;p.reduced_mode='full_impact';full_wakes+=1
 transitions.append({'id':p.id,'to':'full_impact','time':system.clock})

func stats() -> Dictionary:
 var modes: Dictionary={}
 for p in system.panels:modes[p.id]=p.get('reduced_mode','full_impact')
 return {'modes':modes,'reduced_steps':reduced_steps,'full_impact_wakes':full_wakes,'projection_energy_j':projection_energy_j,'damping_energy_j':damping_energy_j,'contacts':contacts,'transitions':transitions,'mass_kg':system.total_mass()}

func _stop(p: Dictionary,mount: Transform3D,hinge_axis: Vector3,sign_: float,h: float) -> void:
 if p.detached:return
 if p.anchors[0].broken or p.anchors[1].broken:
  if not AngularMount.single(p):return
 var arm: Vector3=_point(p,7)-(_point(p,0)+_point(p,2))*.5
 var base: Vector3=mount.basis*(p.rest[7]-(p.rest[0]+p.rest[2])*.5)
 var angle: float=atan2(hinge_axis.dot(base.cross(arm)),base.dot(arm))*sign_
 var limit: float=deg_to_rad(100 if p.id=='tailgate' else 96)
 var correction: float=clampf(clampf(angle,0,limit)-angle,-.08,.08)
 if absf(correction)>.000001:
  var pivot_: Vector3=(_point(p,0)+_point(p,2))*.5
  var rotation_=Quaternion(hinge_axis,correction*sign_)
  p.reduced_data.center=pivot_+rotation_*(p.reduced_data.center-pivot_)
  p.reduced_data.rotation=(rotation_*p.reduced_data.rotation).normalized()
  var relative: float=(p.reduced_data.omega-(compact.angular_velocity if compact!=null else Vector3.ZERO)).dot(hinge_axis)*sign_
  if relative*correction<0:
   var weight: float=hinge_axis.dot(_inverse(p,hinge_axis))+(hinge_axis.dot(compact.inverse_inertia(hinge_axis)) if compact!=null else 0)
   var impulse: Vector3=-hinge_axis*relative*sign_/maxf(.0001,weight)
   p.reduced_data.omega+=_inverse(p,impulse)
   if compact!=null:compact.angular_velocity-=compact.inverse_inertia(impulse)
 p.angle=clampf(angle+correction,-PI,PI)

func _seat(p: Dictionary,seat: Dictionary,target: Vector3,normal: Vector3,h: float) -> void:
 var point_: Vector3=_point(p,seat.node);var r: Vector3=point_-p.reduced_data.center
 var target_velocity: Vector3=_body_velocity(seat.binding,target)
 var v: Vector3=_velocity(p,seat.node)-target_velocity
 var weight: float=1/p.mass+r.cross(normal).dot(_inverse(p,r.cross(normal)))+_body_weight(target,normal)
 var impulse: Vector3=normal*(-v.dot(normal)-(point_-(target-target_velocity*h)).dot(normal)*.12/h)/maxf(.0001,weight)
 _impulse(p,seat.node,impulse);_body_impulse(target,-impulse)

func _wall_contact(p: Dictionary,i: int,old_center: Vector3,old_rotation: Quaternion,_h: float) -> void:
 var point_: Vector3=_point(p,i)
 var hit: Dictionary=system.static_contact(point_,.04)
 if not is_finite(float(hit.distance)):return
 var normal: Vector3=hit.normal;var depth: float=.04-float(hit.distance)
 if depth<=0 and hit.get('source','barrier')=='barrier':
  var start: Vector3=old_center+Basis(old_rotation)*p.reduced_data.offsets[i]
  var boundary: float=graph.barrier_min.x-.04
  if start.x<boundary and point_.x>=boundary:
   var t: float=(boundary-start.x)/maxf(.00001,point_.x-start.x)
   var crossing: Vector3=start.lerp(point_,t)
   if crossing.y>=graph.barrier_min.y and crossing.y<=graph.barrier_max.y and crossing.z>=graph.barrier_min.z and crossing.z<=graph.barrier_max.z:
    normal=Vector3.LEFT;depth=point_.x-boundary
 if depth<=0:return
 p.reduced_data.center+=normal*depth
 var r: Vector3=point_-p.reduced_data.center
 var weight: float=1/p.mass+r.cross(normal).dot(_inverse(p,r.cross(normal)))
 var inward: float=_velocity(p,i).dot(normal)
 if inward<0:_impulse(p,i,-normal*inward/maxf(.00001,weight))
 contacts+=1

func held_closed(p: Dictionary) -> bool:
 if p.detached or p.anchors[0].broken or p.anchors[1].broken:return false
 return (p.latched and not p.anchors[2].broken) or (p.get('closing_engaged',false) and p.get('closing_supports',[]).any(func(s):return not s.broken))
