extends RefCounted
## Full live roof/floor authoring. Non-wheel body probes define first contact.
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Fixture=preload('res://scripts/body_impact_fixture.gd')
const Grid=preload('res://scripts/impact_zone_grid.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const CASES=['roof_flat','roof_corner']
var vehicle: RefCounted
var frames: Array=[]
var signature: Dictionary={}
var history: Dictionary={}
var origin:=Vector3.ZERO
var contact_rotation:=Quaternion.IDENTITY
var fixture_descriptor: Dictionary={}
var case_name: String='roof_flat'
var speed_kmh:=35.0
var quality_multiplier:=4
var elapsed:=0.0
var next_sample:=0.0
var duration:=2.5
var armed:=false
var completed:=false
var full_steps:=0
var cpu_us:=0
var preparation_velocity:=Vector3.ZERO
var first_contact_gap_m:=INF
var result: Dictionary={}

static func full_chassis_basis(g: RefCounted) -> Basis:
 # Lower chassis anchors avoid the sloping roof and preserve roll/pitch.
 var forward: Vector3=(g.points[12]+g.points[13]-g.points[4]-g.points[5]).normalized()
 var lateral: Vector3=g.points[5]-g.points[4]
 lateral=(lateral-forward*forward.dot(lateral)).normalized()
 if forward.length_squared()<.5 or lateral.length_squared()<.5:return Basis.IDENTITY
 var up: Vector3=lateral.cross(forward).normalized()
 return Basis(forward,up,forward.cross(up).normalized()).orthonormalized()

static func minimum_body_floor_gap(g: RefCounted,floor_y: float=0) -> float:
 var gap:=INF
 for i in g.points.size():
  if g.wheels.by_node.has(i):continue
  gap=minf(gap,g.points[i].y-floor_y-g.radii[i])
 return gap

static func body_floor_time_to_contact(g: RefCounted,horizon: float,floor_y: float=0) -> float:
 var first:=INF
 var gravity: float=maxf(0,float(g.config.gravity_mps2))
 for i in g.points.size():
  if g.wheels.by_node.has(i):continue
  var gap: float=g.points[i].y-floor_y-g.radii[i]
  var vy: float=g.velocities[i].y
  if gap<=1e-8:
   if vy<-.01:first=0
   continue
  var t:=INF
  if gravity>.00001:
   # Match the solver's semi-implicit fractional step:
   # gap + vy*t - gravity*t*t = 0.
   t=2*gap/(sqrt(vy*vy+4*gravity*gap)-vy)
  elif vy<-.00001:t=-gap/vy
  if t>=0 and t<=horizon+1e-10:first=minf(first,t)
 return first

static func floor_signature(g: RefCounted,velocity: Vector3,tolerance: float=.002,floor_y: float=0) -> Dictionary:
 var basis: Basis=full_chassis_basis(g)
 var local_normal: Vector3=basis.transposed()*Vector3.UP
 var grid:=Grid.new()
 var masses: Dictionary={};var total:=0.0;var hit_nodes: Array=[]
 for i in g.points.size():
  if g.wheels.by_node.has(i):continue
  if g.points[i].y-floor_y-g.radii[i]>tolerance:continue
  var id: int=grid.zone(g.rest[i]-local_normal*g.radii[i])
  masses[id]=float(masses.get(id,0))+g.masses[i]
  total+=g.masses[i];hit_nodes.append(i)
 if hit_nodes.is_empty() or velocity.y>=-.1:return {}
 var closing: float=-velocity.y
 var momentum: float=float(g.config.mass_kg)*closing
 var energy: float=.5*float(g.config.mass_kg)*closing*closing
 var zones: Array=[]
 var ids: Array=masses.keys();ids.sort()
 for id in ids:
  var weight: float=float(masses[id])/total
  zones.append({'id':id,'weight':weight,'incident_impulse_proxy_ns':momentum*weight,'incident_energy_proxy_j':energy*weight})
 return {'zones':zones,'normal':[local_normal.x,local_normal.y,local_normal.z],'world_normal':[0,1,0],'velocity':[velocity.x,velocity.y,velocity.z],'closing_speed_mps':closing,'incident_impulse_proxy_ns':momentum,'incident_energy_proxy_j':energy,'hit_nodes':hit_nodes,'grid':[5,3,3],'contact_source':'non_wheel_body_floor_probes'}

func start(fixture_case: String='roof_flat',impact_speed_kmh: float=35,quality: int=4) -> void:
 assert(fixture_case in CASES)
 assert(impact_speed_kmh>0)
 case_name=fixture_case;speed_kmh=impact_speed_kmh
 quality_multiplier=quality if quality in [1,2,4] else 4
 vehicle=Vehicle.new();vehicle.setup('res://vehicles/niva.json',false)
 Fixture.start(vehicle,case_name,1.0,true,speed_kmh/3.6)
 vehicle.set_simulation_quality(quality_multiplier)
 fixture_descriptor=Fixture.descriptor(case_name,speed_kmh/3.6,1.0)
 if vehicle.solver.effects!=null:vehicle.solver.effects.synchronize()
 frames.clear();signature={};history={};result={}
 elapsed=0;next_sample=0;armed=false;completed=false;full_steps=0;cpu_us=0
 preparation_velocity=Vector3.ZERO;first_contact_gap_m=INF

func _register_contact(toi: float) -> void:
 var g: RefCounted=vehicle.solver
 var gravity: float=float(g.config.gravity_mps2)
 for i in g.points.size():
  g.points[i]+=g.velocities[i]*toi+Vector3.DOWN*gravity*toi*toi
  g.velocities[i]+=Vector3.DOWN*gravity*toi
 for wheel in g.wheels.wheels:
  wheel.spin=wrapf(wheel.spin+wheel.spin_speed*toi,-PI,PI)
  var angle: float=wheel.angular_velocity.length()*toi
  if angle>1e-9:wheel.rotation=(Quaternion(wheel.angular_velocity.normalized(),angle)*wheel.rotation).normalized()
 g.simulated_time+=toi
 preparation_velocity=vehicle.velocity()
 var correction: Vector3=Vector3.UP*(-speed_kmh/3.6-preparation_velocity.y)
 for i in g.velocities.size():g.velocities[i]+=correction
 var impact_velocity: Vector3=preparation_velocity+correction
 if g.effects!=null:g.effects.synchronize()
 first_contact_gap_m=minimum_body_floor_gap(g)
 signature=floor_signature(g,impact_velocity)
 assert(not signature.is_empty(),'Roof contact boundary must contain a non-wheel floor probe')
 contact_rotation=full_chassis_basis(g).get_rotation_quaternion()
 origin=g.station_center(2)
 g.initial_energy=g.kinetic_energy();g.maximum_energy=g.initial_energy
 g.impact_started=true;g.impact_time=g.simulated_time
 armed=true
 frames.append(Clip.local_frame(g,origin));next_sample=1.0/120

func step() -> void:
 if completed:return
 var g: RefCounted=vehicle.solver
 var dt: float=g.config.fixed_step_s
 var began: int=Time.get_ticks_usec()
 if not armed:
  var toi: float=body_floor_time_to_contact(g,dt)
  if not is_finite(toi):
   vehicle.step(dt);full_steps+=1;cpu_us+=Time.get_ticks_usec()-began;return
  _register_contact(toi)
 var before: PackedVector3Array=g.velocities.duplicate()
 vehicle.step(dt);full_steps+=1;elapsed+=dt
 var local_normal: Vector3=full_chassis_basis(g).transposed()*Vector3.UP
 var grid:=Grid.new()
 for i in g.points.size():
  if g.wheels.by_node.has(i) or not g.contact_floor[i]:continue
  var id: int=grid.zone(g.rest[i]-local_normal*g.radii[i])
  if not history.has(str(id)):history[str(id)]={'contact_substeps':0,'nodal_momentum_loss_proxy_ns':0.0}
  history[str(id)].contact_substeps+=1
  history[str(id)].nodal_momentum_loss_proxy_ns+=maxf(0,g.velocities[i].y-before[i].y)*g.masses[i]
 if elapsed+1e-9>=next_sample:
  frames.append(Clip.local_frame(g,origin));next_sample+=1.0/120
 cpu_us+=Time.get_ticks_usec()-began
 if elapsed+1e-9>=duration:_complete()

func _complete() -> void:
 completed=true
 var g: RefCounted=vehicle.solver
 var inputs: Dictionary={}
 for path in ['structure.json','structures/niva_multiaxis_live.json','vehicles/niva.json','scripts/roof_crash_recorder.gd','scripts/body_impact_fixture.gd','scripts/baked_crash_clip.gd','scripts/structure_solver.gd','scripts/wheel_physics.gd','scripts/vehicle_dynamics.gd','scripts/vehicle_simulation.gd','scripts/compact_chassis.gd','scripts/collision_forecast.gd','scripts/impact_zone_grid.gd','scripts/vehicle_effects.gd','scripts/vehicle_glass.gd','scripts/vehicle_interior.gd']:
  inputs[path]=FileAccess.get_sha256('res://'+path)
 if g.panels_runtime_enabled:inputs.merge(g.panels.input_fingerprints(),true)
 if g.effects!=null:
  inputs.merge(g.effects.glass.input_fingerprints(),true)
  inputs.merge(g.effects.interior.input_fingerprints(),true)
 result={'metadata':{'version':3,'family':'roof_floor','id':case_name+'_'+str(roundi(speed_kmh)),'heading_deg':0.0,'fixture_case':case_name,'fixture_descriptor':fixture_descriptor,'launch_mode':'roof_body_floor_drop','speed_kmh':speed_kmh,'contact_velocity_normalized':true,'preparation_velocity_mps':[preparation_velocity.x,preparation_velocity.y,preparation_velocity.z],'first_body_floor_gap_m':first_contact_gap_m,'duration_s':duration,'sample_hz':120,'physics_hz':roundi(1.0/float(g.config.fixed_step_s)),'quality_multiplier':quality_multiplier,'material_profile':g.config.get('material_profile','legacy'),'material_profile_version':g.config.get('material_profile_version',0),'grid':[5,3,3],'signature':signature,'zone_contact_history':history,'origin':[origin.x,origin.y,origin.z],'contact_rotation_xyzw':[contact_rotation.x,contact_rotation.y,contact_rotation.z,contact_rotation.w],'full_solver_steps':full_steps,'record_cpu_ms':cpu_us/1000.0,'structure_sha256':FileAccess.get_sha256('res://structure.json'),'wheel_solver_sha256':FileAccess.get_sha256('res://scripts/wheel_physics.gd'),'input_sha256':inputs,'scope':'Full live roof/floor authoring with non-wheel body-sphere contact boundary, requested normal contact speed, full3D car frame, promoted materials, body/wheel/effects states. Impulse/energy/history fields are incident proxies, not calibrated contact reaction measurements.'},'frames':frames}
