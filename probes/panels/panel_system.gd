extends RefCounted
## Probe-owned panels. Intact shut mass is condensed; active cage mass is extracted once.
const Attachment=preload('res://scripts/car_attachment.gd')
var graph: WeakRef
var panels: Array=[]
var dt:=1.0/480
var obstacle: Dictionary={}
var events: Array=[]
var clock:=0.0
var active_steps:=0
var idle_steps:=0
var contact_count:=0
var total_cpu_us:=0
var max_release_us:=0
var release_continuity: Array=[]
var activation_continuity: Array=[]
var bind_points:=PackedVector3Array()

func setup(g: RefCounted) -> void:
 graph=weakref(g)
 for item in [['door_left',25.0,1],['door_right',25.0,-1],['bonnet',18.0,0],['tailgate',22.0,0]]:
  var id: String=item[0];var side: int=item[2]
  var pivot:=Vector3(.54,1.04,.905*side) if side!=0 else (Vector3(1.615,1.07,0) if id=='bonnet' else Vector3(-1.36,1.78,0))
  var rest:=PackedVector3Array()
  for u in 3:
   for v in 3:rest.append(surface_rest(id,float(u)/2,float(v)/2,side))
  var normal: Vector3=(rest[3]-rest[0]).cross(rest[1]-rest[0]).normalized()
  if side==1:normal=-normal
  rest.append(rest[4]-normal*.07)
  var edges: Array=[]
  for a in 9:
   for b in range(a+1,9):
    var du: int=absi(a/3-b/3);var dv: int=absi(a%3-b%3)
    if maxi(du,dv)<=1 or (du==2 and dv==0) or (du==0 and dv==2):
     var length: float=rest[a].distance_to(rest[b])
     edges.append({'a':a,'b':b,'original':length,'length':length,'lambda':0.0,'damage':0.0,'bend':maxi(du,dv)>1})
  for a in [0,2,4,6,8]:
   var length: float=rest[a].distance_to(rest[9])
   edges.append({'a':a,'b':9,'original':length,'length':length,'lambda':0.0,'damage':0.0,'bend':true})
  var anchors: Array=[]
  for node in [0,2,7]:anchors.append({'node':node,'rest':rest[node],'binding':Attachment.binding(g,rest[node]),'lambda':Vector3.ZERO,'peak_n':0.0,'exposure':0.0,'broken':false})
  var reservation: Dictionary={}
  # Condensed metal mass lives in substantial lower rails, not the tiny roof nodes.
  # Extracting by visual skin weights could make a 2.5 kg roof control negative.
  var donors: Array=[8,9,12,13] if side!=0 else ([16,17,20,21,24,25] if id=='bonnet' else [0,1,4,5])
  for node in donors:reservation[node]=float(item[1])/donors.size()
  panels.append({'id':id,'side':side,'mass':float(item[1]),'pivot':pivot,'rest':rest,'points':rest.duplicate(),'old':rest.duplicate(),'velocity':PackedVector3Array(),'edges':edges,'anchors':anchors,'reservation':reservation,'active':false,'detached':false,'latched':true,'target':0.0,'angle':0.0,'angular_speed':0.0,'plastic_work':0.0,'contacts':0,'last_normal':Vector3.ZERO,'maximum_force':0.0,'maximum_deflection':0.0,'release_time':-1.0,'active_seconds':0.0,'control_work':0.0,'contact_work':0.0,'hinge_strength_n':3800.0,'latch_strength_n':1300.0,'failure_delay_s':.012})
  panels[-1]['bindings']=[]
  for point_ in rest:panels[-1].bindings.append(Attachment.binding(g,point_))
 reset()

static func surface_rest(id: String,u: float,v: float,side: int) -> Vector3:
 if side!=0:
  var top: float=lerpf(1.22,1.72,minf(1,u*2))
  return Vector3(.54-u*1.02,lerpf(.565,top,v),side*.905)
 if id=='bonnet':return Vector3(1.615-u*1.03,1.07+u*.045,lerpf(-.79,.79,v))
 return Vector3(lerpf(-1.36,-1.78,u),lerpf(1.78,.98,u),lerpf(-.66,.66,v))

func reset() -> void:
 clock=0;events.clear();active_steps=0;idle_steps=0;contact_count=0;total_cpu_us=0;release_continuity.clear();activation_continuity.clear();max_release_us=0
 for panel in panels:
  panel.active=false;panel.detached=false;panel.latched=true;panel.target=0;panel.angle=0;panel.angular_speed=0;panel.plastic_work=0;panel.contacts=0;panel.maximum_force=0;panel.maximum_deflection=0;panel.release_time=-1;panel.active_seconds=0;panel.control_work=0;panel.contact_work=0;panel.quiet_s=0;panel.latch_ready_s=0
  panel.points=panel.rest.duplicate();panel.old=panel.rest.duplicate();panel.velocity=PackedVector3Array();panel.velocity.resize(10);panel.velocity.fill(Vector3.ZERO)
  for edge in panel.edges:edge.length=edge.original;edge.damage=0;edge.lambda=0
  for anchor in panel.anchors:anchor.broken=false;anchor.exposure=0;anchor.peak_n=0;anchor.maximum_n=0;anchor.lambda=Vector3.ZERO
 synchronize_inactive()

func find(id: String) -> Dictionary:
 for p in panels:
  if p.id==id:return p
 return {}

func axis(p: Dictionary,frames: Array) -> Vector3:
 var frame: Transform3D=Attachment.frame_with_rotations(graph.get_ref(),p.pivot,frames)
 return frame.basis*Vector3.UP if p.side!=0 else frame.basis*Vector3.FORWARD

func synchronize_inactive() -> void:
 var g: RefCounted=graph.get_ref();var frames: Array=Attachment.rotations(g)
 for p in panels:
  if p.active:continue
  for i in 10:
   p.points[i]=Attachment.mapped(g,p.rest[i],p.bindings[i],frames)
   var b: Dictionary=p.bindings[i];var velocity:=Vector3.ZERO
   for k in b.ids.size():velocity+=g.velocities[b.ids[k]]*b.weights[k]
   p.velocity[i]=velocity

func momentum() -> Dictionary:
 var g: RefCounted=graph.get_ref();var linear:=Vector3.ZERO;var angular:=Vector3.ZERO
 for i in g.points.size():linear+=g.velocities[i]*g.masses[i];angular+=g.points[i].cross(g.velocities[i]*g.masses[i])
 for p in panels:
  if not p.active:continue
  for i in 10:linear+=p.velocity[i]*p.mass/10;angular+=p.points[i].cross(p.velocity[i]*p.mass/10)
 return {'linear':linear,'angular':angular}

func activate(p: Dictionary) -> void:
 if p.active:return
 synchronize_inactive()
 var before: Dictionary=momentum();var g: RefCounted=graph.get_ref()
 p.active=true
 for node in p.reservation:g.masses[node]-=float(p.reservation[node]);g.inverse_masses[node]=1/g.masses[node]
 g.config.mass_kg-=p.mass
 for link in g.links:
  link.weight_sum=g.inverse_masses[link.a]+g.inverse_masses[link.b]
  link.damping_fraction=1-exp(-link.damping_ns_per_m*link.weight_sum*dt)
 var correction: Dictionary=_correct_momentum(before)
 correction['id']=p.id;activation_continuity.append(correction)

func _correct_momentum(before: Dictionary) -> Dictionary:
 var g: RefCounted=graph.get_ref()
 var after: Dictionary=momentum();var mass: float=0;var center:=Vector3.ZERO
 for i in g.points.size():mass+=g.masses[i];center+=g.points[i]*g.masses[i]
 center/=mass
 var delta: Vector3=(before.linear-after.linear)/mass
 for i in g.velocities.size():g.velocities[i]+=delta
 after=momentum()
 var xx:=0.0;var yy:=0.0;var zz:=0.0;var xy:=0.0;var xz:=0.0;var yz:=0.0
 for i in g.points.size():
  var r: Vector3=g.points[i]-center;var m: float=g.masses[i]
  xx+=m*(r.y*r.y+r.z*r.z);yy+=m*(r.x*r.x+r.z*r.z);zz+=m*(r.x*r.x+r.y*r.y);xy-=m*r.x*r.y;xz-=m*r.x*r.z;yz-=m*r.y*r.z
 var inertia:=Basis(Vector3(xx,xy,xz),Vector3(xy,yy,yz),Vector3(xz,yz,zz))
 var omega: Vector3=inertia.inverse()*(before.angular-after.angular)
 for i in g.velocities.size():g.velocities[i]+=omega.cross(g.points[i]-center)
 after=momentum()
 return {'linear_error':before.linear.distance_to(after.linear),'angular_error':before.angular.distance_to(after.angular)}

func _condense(p: Dictionary) -> void:
 var before: Dictionary=momentum();var g: RefCounted=graph.get_ref()
 p.active=false
 for node in p.reservation:g.masses[node]+=float(p.reservation[node]);g.inverse_masses[node]=1/g.masses[node]
 g.config.mass_kg+=p.mass
 for link in g.links:
  link.weight_sum=g.inverse_masses[link.a]+g.inverse_masses[link.b]
  link.damping_fraction=1-exp(-link.damping_ns_per_m*link.weight_sum*dt)
 var correction: Dictionary=_correct_momentum(before);correction['id']=p.id;correction['condense']=true;activation_continuity.append(correction)

func set_open(id: String,degrees: float) -> bool:
 var p: Dictionary=find(id)
 if p.is_empty() or p.detached or p.anchors.any(func(a):return a.broken):return false
 if degrees>.1:activate(p);p.latched=false
 p.target=deg_to_rad(clampf(degrees,0,95 if id=='tailgate' else 82))
 return true

func prepare_step(h: float) -> void:
 var began: int=Time.get_ticks_usec();dt=h;clock+=h
 if obstacle.is_empty() and not panels.any(func(p):return p.active):
  idle_steps+=panels.size();total_cpu_us+=Time.get_ticks_usec()-began;return
 if not obstacle.is_empty():synchronize_inactive()
 for p in panels:
  if not p.active and not obstacle.is_empty():
   var center: Vector3=obstacle.center+obstacle.velocity*h
   var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
   for point in p.points:low=low.min(point);high=high.max(point)
   var padding: Vector3=Vector3.ONE*.12+obstacle.velocity.abs()*h*2
   if AABB(low-padding,high-low+padding*2).intersects(AABB(center-obstacle.size*.5,obstacle.size)):activate(p)
  if not p.active:idle_steps+=1;continue
  active_steps+=1;p.active_seconds+=h
  p.old=p.points.duplicate()
  var frames: Array=Attachment.rotations(graph.get_ref())
  var hinge: Vector3=(p.points[0]+p.points[2])*.5
  var arm: Vector3=p.points[7]-hinge;var hinge_axis: Vector3=axis(p,frames)
  var rest_arm: Vector3=p.rest[7]-(p.rest[0]+p.rest[2])*.5
  var mount: Transform3D=Attachment.frame_with_rotations(graph.get_ref(),p.pivot,frames)
  var base_arm: Vector3=mount.basis*rest_arm
  var signed: float=atan2(hinge_axis.dot(base_arm.cross(arm)),base_arm.dot(arm))
  var sign_: float=float(p.side) if p.side!=0 else 1.0
  p.angle=signed*sign_
  var axis_arm: Vector3=hinge_axis.cross(arm)
  p.angular_speed=axis_arm.dot(p.velocity[7]-(p.velocity[0]+p.velocity[2])*.5)/maxf(.01,axis_arm.length_squared())*sign_
  var intact: bool=not p.anchors.any(func(a):return a.broken)
  var gravity_torque:=0.0
  for point_ in p.points:gravity_torque+=hinge_axis.dot((point_-hinge).cross(Vector3.DOWN*(9.81*p.mass/10)))*sign_
  var cap: float=30 if p.side!=0 else 180
  var spring: float=80 if p.side!=0 else 280
  var damping: float=18 if p.side!=0 else 55
  # The UI actuator supplies bounded lifting torque; bonnet/hatch must overcome gravity.
  var torque: float=clampf((p.target-p.angle)*spring-p.angular_speed*damping-gravity_torque,-cap,cap) if intact and not p.latched else -p.angular_speed*1.2
  var max_angle: float=deg_to_rad(100 if p.id=='tailgate' else 96)
  if p.angle<0:torque+=-p.angle*450-p.angular_speed*18
  elif p.angle>max_angle:torque+=(max_angle-p.angle)*450-p.angular_speed*18
  if p.detached:torque=0
  var force: Vector3=axis_arm.normalized()*torque/maxf(.1,axis_arm.length())*sign_
  p.velocity[7]+=force*(10/p.mass)*h
  p.control_work+=maxf(0,force.dot(p.velocity[7])*h)
  if not p.detached:
   var g: RefCounted=graph.get_ref()
   var binding: Dictionary=p.anchors[0].binding
   for k in binding.ids.size():g.velocities[binding.ids[k]]-=force*g.inverse_masses[binding.ids[k]]*binding.weights[k]*h
  for i in 10:p.velocity[i].y-=9.81*h;p.points[i]+=p.velocity[i]*h
  for edge in p.edges:edge.lambda=0
  for anchor in p.anchors:anchor.lambda=Vector3.ZERO;anchor.peak_n=0
 total_cpu_us+=Time.get_ticks_usec()-began

func solve() -> void:
 if not panels.any(func(p):return p.active):return
 var g: RefCounted=graph.get_ref();var frames: Array=Attachment.rotations(g)
 for p in panels:
  if not p.active:continue
  var inv: float=10/p.mass
  for edge in p.edges:
   var d: Vector3=p.points[edge.b]-p.points[edge.a];var length: float=d.length()
   if length<1e-7:continue
   var n: Vector3=d/length;var stiffness: float=85000 if not edge.bend else 18000
   var alpha: float=1/(stiffness*dt*dt)
   var dl: float=(-(length-edge.length)-alpha*edge.lambda)/(inv*2+alpha)
   var force: float=absf(edge.lambda+dl)/(dt*dt)
   var yield_n: float=(1500 if not edge.bend else 450)*(1+edge.damage*.6)
   if force>yield_n:
    var capped: float=signf(edge.lambda+dl)*yield_n*dt*dt
    var wanted: float=clampf(length+alpha*capped,edge.original*.48,edge.original*1.30)
    p.plastic_work+=yield_n*absf(wanted-edge.length)
    edge.length=wanted;edge.damage=maxf(edge.damage,absf(wanted-edge.original)/maxf(.01,edge.original*.4))
    dl=(-(length-edge.length)-alpha*edge.lambda)/(inv*2+alpha)
   edge.lambda+=dl;p.points[edge.a]-=n*inv*dl;p.points[edge.b]+=n*inv*dl
  if not p.detached:
   for index in 3:
    if index==2 and not p.latched:continue
    var anchor: Dictionary=p.anchors[index]
    if anchor.broken:continue
    var target: Vector3=Attachment.mapped(g,anchor.rest,anchor.binding,frames)
    var weight: float=inv
    for k in anchor.binding.ids.size():weight+=g.inverse_masses[anchor.binding.ids[k]]*pow(anchor.binding.weights[k],2)
    var stiffness: float=80000 if index==2 else 500000
    var alpha: float=1/(stiffness*dt*dt)
    var d: Vector3=p.points[anchor.node]-target
    var dl: Vector3=(-d-anchor.lambda*alpha)/(weight+alpha)
    anchor.lambda+=dl;p.points[anchor.node]+=dl*inv
    for k in anchor.binding.ids.size():g.points[anchor.binding.ids[k]]-=dl*g.inverse_masses[anchor.binding.ids[k]]*anchor.binding.weights[k]
    anchor.peak_n=maxf(anchor.peak_n,anchor.lambda.length()/(dt*dt));anchor.maximum_n=maxf(anchor.maximum_n,anchor.peak_n);p.maximum_force=maxf(p.maximum_force,anchor.peak_n)
  for i in 10:
   if not obstacle.is_empty():_box_contact(p,i)
   if p.points[i].y<.045:p.points[i].y=.045

func _box_contact(p: Dictionary,i: int) -> void:
 var center: Vector3=obstacle.center+obstacle.velocity*dt
 var low: Vector3=center-obstacle.size*.5-Vector3.ONE*.035
 var high: Vector3=center+obstacle.size*.5+Vector3.ONE*.035
 var relative_start: Vector3=p.old[i]-obstacle.center
 var relative_end: Vector3=p.points[i]-center
 var half: Vector3=obstacle.size*.5+Vector3.ONE*.035
 var inside: bool=p.points[i].x>=low.x and p.points[i].x<=high.x and p.points[i].y>=low.y and p.points[i].y<=high.y and p.points[i].z>=low.z and p.points[i].z<=high.z
 var normal:=Vector3.ZERO
 if inside:
  var delta: Vector3=p.points[i]-p.points[i].clamp(low,high)
  var distances: Array=[p.points[i].x-low.x,high.x-p.points[i].x,p.points[i].y-low.y,high.y-p.points[i].y,p.points[i].z-low.z,high.z-p.points[i].z]
  var normals: Array=[Vector3.LEFT,Vector3.RIGHT,Vector3.DOWN,Vector3.UP,Vector3.FORWARD,Vector3.BACK]
  var face: int=distances.find(distances.min());normal=normals[face];p.points[i]+=normal*float(distances[face])
 else:
  var delta: Vector3=relative_end-relative_start;var entry:=0.0;var exit:=1.0;var hit:=true;var hit_axis:=-1
  for a in 3:
   if absf(delta[a])<1e-8:
    if relative_start[a]<-half[a] or relative_start[a]>half[a]:hit=false
   else:
    var t0: float=(-half[a]-relative_start[a])/delta[a];var t1: float=(half[a]-relative_start[a])/delta[a]
    if minf(t0,t1)>entry:entry=minf(t0,t1);hit_axis=a
    exit=minf(exit,maxf(t0,t1))
   if entry>exit:hit=false
  if hit and hit_axis>=0 and entry>=0 and entry<=1:
   normal[hit_axis]=-signf(delta[hit_axis]);p.points[i][hit_axis]=center[hit_axis]+normal[hit_axis]*half[hit_axis]
 if normal.length_squared()>.5:
  contact_count+=1;p.contacts+=1;p.last_normal=normal
  p.contact_work+=maxf(0,obstacle.velocity.dot(normal))*p.mass/10*maxf(0,(p.points[i]-p.old[i]).dot(normal))/dt

func finish_step() -> void:
 for p in panels:
  if not p.active:continue
  for i in 10:
   p.velocity[i]=(p.points[i]-p.old[i])/dt
   p.velocity[i]*=exp(-.5*dt)
   if p.points[i].y<=.04501:
    p.velocity[i].y=maxf(0,p.velocity[i].y);p.velocity[i].x*=.99;p.velocity[i].z*=.99
  # Dissipative axial damping, preserving panel COM momentum.
  var inv: float=10/p.mass
  for edge in p.edges:
   var n: Vector3=(p.points[edge.b]-p.points[edge.a]).normalized()
   var relative: float=(p.velocity[edge.b]-p.velocity[edge.a]).dot(n)
   var correction: Vector3=n*relative*(1-exp(-25*dt))*.5
   p.velocity[edge.a]+=correction;p.velocity[edge.b]-=correction
  for index in 3:
   var a: Dictionary=p.anchors[index]
   if a.broken or (index==2 and not p.latched):continue
   var limit: float=p.latch_strength_n if index==2 else p.hinge_strength_n*(.60 if index==0 else 1.0)
   a.exposure=maxf(0,a.exposure+dt*(1 if a.peak_n>limit else -2))
   var delay: float=.008 if index==0 else p.failure_delay_s
   if a.exposure>=delay:
    a.broken=true
    events.append({'id':events.size(),'time':clock,'panel':p.id,'kind':['lower_hinge','upper_hinge','latch'][index],'force_n':a.peak_n})
    if index==2:p.latched=false
  if not p.detached and p.anchors[0].broken and p.anchors[1].broken:
   var began: int=Time.get_ticks_usec();var before: Dictionary=momentum();var positions: PackedVector3Array=p.points.duplicate();var velocities: PackedVector3Array=p.velocity.duplicate()
   p.detached=true;p.latched=false;p.anchors[2].broken=true;p.release_time=clock
   events.append({'id':events.size(),'time':clock,'panel':p.id,'kind':'detached','force_n':p.maximum_force})
   var after: Dictionary=momentum()
   release_continuity.append({'panel':p.id,'point_error_m':0.0 if positions==p.points else INF,'velocity_error_mps':0.0 if velocities==p.velocity else INF,'linear_error_ns':before.linear.distance_to(after.linear),'angular_error_nms':before.angular.distance_to(after.angular)})
   max_release_us=maxi(max_release_us,Time.get_ticks_usec()-began)
  if not p.detached and not p.anchors[2].broken and p.target<.01 and absf(p.angle)<.025 and absf(p.angular_speed)<.12:
   p.latch_ready_s+=dt
   if p.latch_ready_s>.08:p.latched=true
  else:p.latch_ready_s=0
  if p.latched and not p.anchors.any(func(a):return a.broken) and p.plastic_work<.01:
   var g: RefCounted=graph.get_ref();var frames: Array=Attachment.rotations(g);var residual:=0.0;var speed:=0.0
   for i in 10:
    residual=maxf(residual,p.points[i].distance_to(Attachment.mapped(g,p.rest[i],p.bindings[i],frames)))
    var mount_velocity:=Vector3.ZERO
    for k in p.bindings[i].ids.size():mount_velocity+=g.velocities[p.bindings[i].ids[k]]*p.bindings[i].weights[k]
    speed=maxf(speed,p.velocity[i].distance_to(mount_velocity))
   p.quiet_s=p.quiet_s+dt if residual<.006 and speed<.12 else 0.0
   if p.quiet_s>.25:_condense(p)
  else:p.quiet_s=0

func total_mass() -> float:
 var total:=0.0
 for mass in graph.get_ref().masses:total+=mass
 for p in panels:
  if p.active:total+=p.mass
 return total

func capture() -> Dictionary:
 var states: Array=[]
 for p in panels:
  states.append({'id':p.id,'points':p.points.duplicate(),'velocity':p.velocity.duplicate(),'active':p.active,'detached':p.detached,'latched':p.latched,'target':p.target,'angle':p.angle,'plastic_work':p.plastic_work,'anchors':p.anchors.duplicate(true),'edges':p.edges.duplicate(true),'release_time':p.release_time,'contacts':p.contacts,'maximum_force':p.maximum_force})
 return {'version':1,'panels':states,'events':events.duplicate(true),'time':clock,'mass':total_mass()}

func restore(state: Dictionary) -> void:
 clock=state.time;events=state.events.duplicate(true)
 for i in panels.size():
  for key in state.panels[i]:
   if key!='id':panels[i][key]=state.panels[i][key].duplicate(true) if state.panels[i][key] is Dictionary or state.panels[i][key] is Array else state.panels[i][key]
  panels[i].old=panels[i].points.duplicate()

func statistics() -> Dictionary:
 return {'active_steps':active_steps,'idle_steps':idle_steps,'contacts':contact_count,'mass_kg':total_mass(),'panel_nodes':panels.size()*10,'max_release_us':max_release_us,'release_continuity':release_continuity,'activation_continuity':activation_continuity,'events':events}
