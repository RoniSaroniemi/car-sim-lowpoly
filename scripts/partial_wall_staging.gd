extends RefCounted
## Reproducible, still-drivable finite-wall test launch. No solver is duplicated.
static func stage(car: RefCounted,speed: float=60,angle: float=0,overlap: float=.5,side: String='right',distance: float=3) -> void:
 var start:=Vector3(car.solver.barrier_min.x-distance,0,0)
 car.reset(speed,start)
 var basis:=Basis(Vector3.UP,deg_to_rad(angle))
 var low:=INF;var high:=-INF
 for i in car.solver.points.size():
  car.solver.points[i]=basis*car.solver.rest[i]+start
  low=minf(low,car.solver.points[i].z-car.solver.radii[i]);high=maxf(high,car.solver.points[i].z+car.solver.radii[i])
 if overlap<1:
  var shift: float=car.solver.barrier_min.z-(high-overlap*(high-low)) if side=='left' else car.solver.barrier_max.z-(low+overlap*(high-low))
  for i in car.solver.points.size():car.solver.points[i].z+=shift
 for wheel in car.solver.wheels.wheels:
  wheel.rotation=basis.get_rotation_quaternion();wheel.previous_rotation=wheel.rotation
  wheel.spin_speed=-speed/3.6*cos(deg_to_rad(angle))/wheel.radius
 car.compact.capture_shape();car.solver.effects.synchronize()
 var panels: Variant=car.solver.get('panels')
 if panels!=null and panels.has_method('synchronize_inactive'):panels.synchronize_inactive()
