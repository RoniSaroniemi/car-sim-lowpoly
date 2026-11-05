extends SceneTree
const Driving=preload('res://scripts/driving_vehicle.gd')
const Roof=preload('res://scripts/roof_landing_geometry.gd')
const Heading=preload('res://scripts/airborne_camera_heading.gd')
var checks: Dictionary={}
var runs: Array=[]
func _initialize() -> void:call_deferred('_run')
func com(g: RefCounted) -> Vector3:
 var total:=Vector3.ZERO;var mass:=0.0
 for i in g.points.size():total+=g.points[i]*g.masses[i];mass+=g.masses[i]
 return total/mass
func _run() -> void:
 for roll in [0.,45.,120.,180.]:
  for spin in [0.,1.]:
   var car:=Driving.new();car.setup();car.solver.barrier_enabled=false
   var g: RefCounted=car.solver;var rotation:=Basis(Vector3.RIGHT,deg_to_rad(roll))
   for i in g.points.size():g.points[i]=rotation*g.rest[i]+Vector3(-20,30,0)
   var center: Vector3=g.station_center(2)
   for i in g.points.size():g.velocities[i]=Vector3(12,3,0)+Vector3.RIGHT.cross(g.points[i]-center)*spin
   for w in g.wheels.wheels:w.rotation=rotation.get_rotation_quaternion();w.previous_rotation=w.rotation;w.angular_velocity=Vector3.RIGHT*spin
   g.panels.synchronize_inactive();g.effects.synchronize();car.compact.capture_shape()
   var initial: Basis=Roof.basis(g);var initial_com:=com(g)
   var initial_vy:=0.0;var total_mass:=0.0
   for i in g.points.size():initial_vy+=g.velocities[i].y*g.masses[i];total_mass+=g.masses[i]
   initial_vy/=total_mass
   for tick in 120:car.advance(1./120)
   var expected: Basis=Basis(Vector3.RIGHT,spin)*initial
   var angle: float=rad_to_deg(expected.get_rotation_quaternion().angle_to(Roof.basis(g).get_rotation_quaternion()))
   var key: String='roll%d_spin%d'%[roundi(roll),roundi(spin)]
   checks[key+'_no_uprighting']=angle<.25
   checks[key+'_angular_velocity_preserved']=car.compact.angular_velocity.distance_to(Vector3.RIGHT*spin)<.005
   checks[key+'_ballistic_mass_center']=absf(com(g).y-(initial_com.y+initial_vy-9.81*.5))<.08
   checks[key+'_no_crash_or_full_solver']=car.full_steps==0 and car.baked_count==0
   runs.append({'case':key,'orientation_error_deg':angle,'final_omega':str(car.compact.angular_velocity),'initial_com_velocity_y':initial_vy,'vertical_com_error_m':com(g).y-(initial_com.y+initial_vy-9.81*.5)})
 # Yaw/pitch changes of the airborne car must not spin the chase camera.
 var car:=Driving.new();car.setup();var reference:=Heading.new();reference.sample(car)
 for i in car.solver.points.size():car.solver.points[i]+=Vector3.UP*20
 var target: float=reference.sample(car)
 for angle in [1.,2.,3.]:
  var r:=Basis(Vector3.UP,angle)*Basis(Vector3.BACK,1.5)
  for i in car.solver.points.size():car.solver.points[i]=r*car.solver.rest[i]+Vector3(0,20,0)
  checks['camera_keeps_heading_'+str(angle)]=absf(angle_difference(reference.sample(car),target))<.00001
 var passed: bool=checks.values().all(func(v):return v)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification/airborne'))
 FileAccess.open('res://verification/airborne/validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':runs,'scope':'Uncontacted shared driving body and mounted wheels, zero and sustained roll, ballistic gravity; camera heading independent of airborne pose'},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('AIRBORNE_VERIFIED ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
