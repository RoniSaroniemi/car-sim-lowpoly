extends RefCounted
## Keep the horizon/heading reference steady while the physical car tumbles.
var heading:=0.0
var initialized:=false
func reset() -> void:initialized=false
func sample(car: RefCounted) -> float:
 var g: RefCounted=car.solver;var forward: Vector3=car.forward()
 var supported:=false
 for wheel in g.wheels.wheels:
  if wheel.detached:continue
  var p: Vector3=g.points[wheel.node]+g.wheels.support(wheel,Vector3.DOWN)
  if p.y-g.floor_sample(p).w<.12:supported=true
 var horizontal:=Vector2(forward.x,forward.z)
 if not initialized or (supported and horizontal.length()>.3):
  if horizontal.length()>.1:heading=atan2(forward.z,forward.x)
  initialized=true
 return heading
