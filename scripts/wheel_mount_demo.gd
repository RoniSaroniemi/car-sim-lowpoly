extends RefCounted
## A timed external-load fixture, used by the visible demo and its verification.
var graph: WeakRef
var active:=false
var time:=0.0
var phase: String=''
var saw_aligned:=false
var saw_bent:=false
var saw_detached:=false
var largest_retained_bend:=0.0

func start(solver: RefCounted) -> void:
 graph=weakref(solver)
 solver.request_full_solve('wheel_mount_fixture',3.1)
 active=true
 time=0
 phase='Normal support — wheel stays aligned'
 saw_aligned=false
 saw_bent=false
 saw_detached=false
 largest_retained_bend=0

func stop() -> void:
 active=false
 phase=''

func step(dt: float) -> void:
 if not active:return
 var g: RefCounted=graph.get_ref()
 var w=g.wheels.wheels[3]
 var side: Vector3=(g.points[w.body_nodes[1]]-g.points[w.body_nodes[0]]).normalized()
 var forward: Vector3=Vector3.UP.cross(side).normalized()
 var force:=Vector3.ZERO
 var torque:=Vector3.ZERO
 if time>=.4 and time<.6:
  force=side*2000.0
 if time>=1.0 and time<1.0125:
  torque=forward*10000.0
 if time>=1.04 and time<2.3:
  phase='Over yield — permanent bend'
  var angle: float=rad_to_deg(acos(clampf(w.alignment.dot(Vector3.BACK),-1,1)))
  if angle>.05 and not w.detached:
   saw_bent=true
   largest_retained_bend=maxf(largest_retained_bend,angle)
 if time>=2.3 and not w.detached:
  phase='Over break threshold — releasing wheel'
  force=side*100000.0
  torque=forward*30000.0
 if w.detached:
  phase='Wheel released — R repairs the car'
  saw_detached=true
  force=Vector3.ZERO
  torque=Vector3.ZERO
 if time>=.65 and time<.95:
  saw_aligned=not w.detached and absf(g.wheels.lateral_error(w))<.001 and w.alignment.dot(Vector3.BACK)>cos(deg_to_rad(.1))
 # Apply external fixture loads at the actual structural timestep.
 g.velocities[w.node]+=force*g.inverse_masses[w.node]*dt
 w.angular_velocity+=g.wheels.inverse_inertia(w,torque)*dt
 time+=dt
 if time>=3.0:active=false
