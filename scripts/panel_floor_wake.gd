extends RefCounted
## Optional floor-contact policy for the roof-landing recipe and live driving.
## Existing offline wall recipes keep their original physical provenance.
static func step(g: RefCounted,h: float) -> void:
 if not g.panels_runtime_enabled or g.panels.playback:return
 g.panels.synchronize_inactive()
 for p in g.panels.panels:
  if p.active:continue
  for i in p.points.size():
   var velocity: Vector3=p.velocity[i]+Vector3.DOWN*float(g.config.gravity_mps2)*h
   var future: Vector3=p.points[i]+velocity*h
   var floor_: Vector4=g.floor_sample(future)
   var normal:=Vector3(floor_.x,floor_.y,floor_.z).normalized()
   if (future.y-floor_.w)*normal.y<=.04 and velocity.dot(normal)<-.0001:
    g.panels.activate(p);break
