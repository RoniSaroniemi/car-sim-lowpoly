extends RefCounted
## Input-to-wheel forces, shared by every driving scene; no rigid chassis proxy.
var graph: WeakRef
var parameters: Dictionary
var throttle:=0.0
var brake:=0.0
var steering:=0.0
var handbrake:=0.0
var steering_angle:=0.0

func setup(owner: RefCounted,settings: Dictionary) -> void:
 graph=weakref(owner)
 parameters=settings.duplicate(true)
 # JSON numbers are floats; membership tests must use integer wheel indices.
 for key in ['driven_wheels','steering_wheels','handbrake_wheels']:
  parameters[key]=PackedInt32Array(parameters[key])

func reset() -> void:
 throttle=0
 brake=0
 steering=0
 handbrake=0
 steering_angle=0

func set_controls(accelerator: float,braking: float,turn: float,parking: float=0) -> void:
 throttle=clampf(accelerator,-1,1)
 brake=clampf(braking,0,1)
 steering=clampf(turn,-1,1)
 handbrake=clampf(parking,0,1)

func body_velocity() -> Vector3:
 var g: RefCounted=graph.get_ref()
 var momentum:=Vector3.ZERO
 var mass:=0.0
 # Body stations define speed/heading; detached wheels do not steer the camera.
 for i in 28:
  momentum+=g.velocities[i]*g.masses[i]
  mass+=g.masses[i]
 return momentum/mass

func body_forward() -> Vector3:
 var g: RefCounted=graph.get_ref()
 # Lower chassis points define forward; the sloping roof does not pitch it down.
 return (g.points[12]+g.points[13]-g.points[4]-g.points[5]).normalized()

func step(dt: float) -> void:
 var g: RefCounted=graph.get_ref()
 var velocity: Vector3=body_velocity()
 var forward: Vector3=body_forward()
 var speed: float=velocity.dot(forward)
 var fraction: float=clampf(absf(speed)/(float(parameters.max_speed_kmh)/3.6),0,1)
 var angle_limit: float=deg_to_rad(parameters.steering_angle_deg)*lerpf(1.0,parameters.high_speed_steering_fraction,fraction)
 steering_angle=move_toward(steering_angle,steering*angle_limit,deg_to_rad(parameters.steering_rate_deg_s)*dt)
 g.wheels.friction_coefficient=parameters.tire_friction
 var drive_count:=0
 for index in parameters.driven_wheels:
  var w=g.wheels.wheels[index]
  if not w.detached and not w.joint_broken:drive_count+=1
 for index in g.wheels.wheels.size():
  var w=g.wheels.wheels[index]
  if w.detached:continue
  w.steering_angle=steering_angle if index in parameters.steering_wheels else 0.0
  if drive_count>0 and index in parameters.driven_wheels and not w.joint_broken:
   var limit: float=float(parameters.reverse_speed_kmh if throttle<0 else parameters.max_speed_kmh)/3.6
   var directed_speed: float=speed*signf(throttle)
   var taper: float=clampf((limit-directed_speed)/maxf(1.0,limit*.12),0,1)
   var torque: float=minf(parameters.drive_torque_nm,float(parameters.power_w)/maxf(12.0,absf(w.spin_speed)))
   # Positive throttle rolls +X, which is negative axle spin in this convention.
   w.spin_speed-=throttle*(1-brake)*torque*taper*dt/(drive_count*w.inertia_spin)
  var brake_torque: float=brake*float(parameters.brake_torque_nm)/g.wheels.wheels.size()
  if index in parameters.handbrake_wheels:
   brake_torque+=handbrake*float(parameters.handbrake_torque_nm)/parameters.handbrake_wheels.size()
  if g.contact_floor[w.node]:
   # Bearing/tire rolling loss, shared by full and compact modes. This arrests
   # the small roll induced while the initially unloaded suspension settles.
   brake_torque+=float(parameters.get('rolling_resistance',.015))*float(g.config.mass_kg)*float(g.config.gravity_mps2)*w.radius/g.wheels.wheels.size()
  w.spin_speed=move_toward(w.spin_speed,0,brake_torque*dt/w.inertia_spin)
 # External aerodynamic drag, distributed by mass without an extra chassis.
 var drag: Vector3=-velocity*velocity.length()*float(parameters.aero_drag_n_per_mps2)
 var acceleration: Vector3=drag/maxf(.001,g.body_mass_kg if g.panels_runtime_enabled else float(g.config.mass_kg))
 for i in g.velocities.size():
  if g.wheels.by_node.has(i) and g.wheels.wheels[g.wheels.by_node[i]].detached:continue
  g.velocities[i]+=acceleration*dt
