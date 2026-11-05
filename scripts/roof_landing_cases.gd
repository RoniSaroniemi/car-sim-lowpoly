extends RefCounted
const Geometry=preload('res://scripts/roof_landing_geometry.gd')
const DIRECTORY='res://bakes/roof_landing'
static func specifications() -> Array:
 var result: Array=[]
 for down in [4.0,7.0]:
  for roll in [-15.0,0.0,15.0]:
   result.append({'id':'roof_landing_f60_d%d_r%s'%[roundi(down),'m15' if roll<0 else ('p15' if roll>0 else '000')],'forward_kmh':60.0,'down_mps':down,'roll_deg':roll,'roll_rate':signf(roll)*.35})
 return result
static func place(vehicle: RefCounted,spec: Dictionary,clearance: float=0,start: Vector3=Vector3(-45,0,0),yaw: float=0) -> void:
 vehicle.reset(0,start)
 var g: RefCounted=vehicle.solver
 var rotation:=Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,PI+deg_to_rad(float(spec.roll_deg)))
 for i in g.points.size():g.points[i]=rotation*g.rest[i]+start
 for wheel in g.wheels.wheels:
  wheel.rotation=rotation.get_rotation_quaternion();wheel.previous_rotation=wheel.rotation
  wheel.angular_velocity=rotation.x*float(spec.roll_rate);wheel.spin_speed=-float(spec.forward_kmh)/3.6/wheel.radius
 g.panels.synchronize_inactive()
 var shift:=clearance-Geometry.minimum_gap(g)
 for i in g.points.size():g.points[i].y+=shift
 var center: Vector3=g.station_center(2)
 var down: float=sqrt(maxf(0,float(spec.down_mps)*float(spec.down_mps)-2*float(g.config.gravity_mps2)*clearance))
 var linear: Vector3=rotation.x*float(spec.forward_kmh)/3.6+Vector3.DOWN*down
 var omega: Vector3=rotation.x*float(spec.roll_rate)
 for i in g.points.size():g.velocities[i]=linear+omega.cross(g.points[i]-center)
 g.panels.synchronize_inactive();g.effects.synchronize()
 vehicle.compact.capture_shape();g.initial_energy=g.kinetic_energy();g.maximum_energy=g.initial_energy
static func read_library() -> Array:
 var clip_script=load('res://scripts/baked_crash_clip.gd');var result: Array=[]
 for spec in specifications():
  var data: Dictionary=clip_script.read(DIRECTORY+'/'+spec.id+'.crashclip')
  if not data.is_empty():result.append(data)
 return result
