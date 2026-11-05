extends RefCounted
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Zones=preload('res://scripts/impact_zone_grid.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
var vehicle: RefCounted
var grid:=Zones.new()
var frames: Array=[]
var signature: Dictionary={}
var history: Dictionary={}
var origin:=Vector3.ZERO
var elapsed:=0.0
var next_sample:=0.0
var armed:=false
var completed:=false
var full_steps:=0
var cpu_us:=0
var duration:=2.5
var angle_deg:=0.0
var speed_kmh:=120.0
var quality_multiplier:=4
var preparation_speed_mps:=0.0
var result: Dictionary={}

func start(heading_degrees: float=0,launch_speed_kmh: float=120) -> void:
 angle_deg=wrapf(heading_degrees,-180,180)
 speed_kmh=launch_speed_kmh
 vehicle=Vehicle.new()
 vehicle.setup('res://vehicles/niva.json',false)
 vehicle.set_simulation_quality(quality_multiplier)
 vehicle.solver.set_impact_mode(0)
 vehicle.solver.config.enforce_symmetry=absf(angle_deg)<.001
 var heading:=Basis(Vector3.UP,deg_to_rad(angle_deg))
 var start_position:=Vector3(-9,0,0)
 vehicle.reset(speed_kmh,start_position)
 for i in vehicle.solver.points.size():
  vehicle.solver.points[i]=heading*vehicle.solver.rest[i]+start_position
  vehicle.solver.velocities[i]=Vector3(speed_kmh/3.6,0,0)
 for w in vehicle.solver.wheels.wheels:
  w.rotation=heading.get_rotation_quaternion();w.previous_rotation=w.rotation
  w.spin_speed*=cos(deg_to_rad(angle_deg))
 frames.clear();history.clear();signature={}
 armed=false;completed=false;full_steps=0;cpu_us=0;elapsed=0;next_sample=0

func step() -> void:
 if completed:return
 var g: RefCounted=vehicle.solver
 var dt: float=g.config.fixed_step_s
 var began: int=Time.get_ticks_usec()
 if not armed:
  var velocity: Vector3=vehicle.velocity()
  var toi: float=grid.time_to_contact(g,velocity,dt)
  if is_finite(toi):
   # Register an exact contact pose, then keep every subsequent solve at the selected physical timestep.
   for i in g.points.size():g.points[i]+=velocity*toi
   # Prepare suspension through the approach, then initialize the recorded
   # impact at exactly the requested velocity. The approach is not baked.
   preparation_speed_mps=velocity.length()
   var impact_velocity:=Vector3(speed_kmh/3.6,0,0)
   var delta: Vector3=impact_velocity-velocity
   for i in g.velocities.size():g.velocities[i]+=delta
   for w in g.wheels.wheels:w.spin_speed=-impact_velocity.dot(grid.body_basis(g).x)/w.radius
   velocity=impact_velocity
   if g.panels_runtime_enabled:g.panels.synchronize_inactive()
   if g.effects!=null:g.effects.synchronize()
   g.initial_energy=g.kinetic_energy();g.maximum_energy=g.initial_energy
   signature=grid.signature(g,velocity)
   assert(not signature.is_empty())
   origin=g.station_center(2)
   armed=true
   frames.append(Clip.local_frame(g,origin))
   next_sample=1.0/120.0
  else:
   vehicle.step(dt)
   full_steps+=1
   cpu_us+=Time.get_ticks_usec()-began
   return
 var before: PackedVector3Array=g.velocities.duplicate()
 vehicle.step(dt)
 full_steps+=1
 elapsed+=dt
 for i in g.points.size():
  if not g.contact_wall[i]:continue
  var hit: Dictionary=g.barrier_distance(g.points[i])
  var id: int=grid.zone(g.rest[i]-grid.body_basis(g).transposed()*hit.normal*g.radii[i])
  var lost: float=maxf(0,(before[i]-g.velocities[i]).dot(-hit.normal))*g.masses[i]
  if not history.has(str(id)):history[str(id)]={'contact_substeps':0,'nodal_momentum_loss_proxy_ns':0.0}
  history[str(id)].contact_substeps+=1
  history[str(id)].nodal_momentum_loss_proxy_ns+=lost
 if elapsed+1e-9>=next_sample:
  frames.append(Clip.local_frame(g,origin))
  next_sample+=1.0/120.0
 cpu_us+=Time.get_ticks_usec()-began
 if elapsed+1e-9>=duration:
  completed=true
  result={'metadata':{'version':3,'id':Clip.case_id(angle_deg,speed_kmh),'heading_deg':angle_deg,'launch_mode':'wall_normal_slam','contact_velocity_normalized':true,'preparation_speed_mps':preparation_speed_mps,'speed_kmh':speed_kmh,'duration_s':duration,'sample_hz':120,'physics_hz':roundi(1.0/float(g.config.fixed_step_s)),'quality_multiplier':quality_multiplier,'material_profile':g.config.get('material_profile','legacy'),'grid':[5,3,3],'signature':signature,'zone_contact_history':history,'origin':[origin.x,origin.y,origin.z],'full_solver_steps':full_steps,'record_cpu_ms':cpu_us/1000.0,'structure_sha256':FileAccess.get_sha256('res://structure.json'),'wheel_solver_sha256':FileAccess.get_sha256('res://scripts/wheel_physics.gd'),'scope':'Frontal or oblique car heading into a fixed flat barrier; symmetry is disabled for oblique cases. Incident severity and nodal momentum-loss values are proxies, not calibrated contact-force measurements. Frames include root motion, damage and wheel states.'},'frames':frames}
  var inputs: Dictionary={}
  for path in ['structure.json','vehicles/niva.json','scripts/structure_solver.gd','scripts/wheel_physics.gd','scripts/vehicle_dynamics.gd','scripts/vehicle_simulation.gd','scripts/compact_chassis.gd','scripts/collision_forecast.gd','scripts/impact_zone_grid.gd','scripts/vehicle_effects.gd','scripts/vehicle_glass.gd','scripts/vehicle_interior.gd']:
   inputs[path]=FileAccess.get_sha256('res://'+path)
  if g.panels_runtime_enabled:inputs.merge(g.panels.input_fingerprints(),true)
  inputs.merge(g.effects.glass.input_fingerprints(),true)
  inputs.merge(g.effects.interior.input_fingerprints(),true)
  result.metadata['input_sha256']=inputs
