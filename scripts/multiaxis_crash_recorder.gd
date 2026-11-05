extends RefCounted
## Full-physics authoring, never used by a runtime contact selector.
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Cases=preload('res://scripts/multiaxis_crash_cases.gd')
const Roof=preload('res://scripts/roof_crash_recorder.gd')
const Grid=preload('res://scripts/impact_zone_grid.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
var vehicle: RefCounted
var descriptor: Dictionary={}
var frames: Array=[]
var result: Dictionary={}
var signature: Dictionary={}
var origin:=Vector3.ZERO
var contact_rotation:=Quaternion.IDENTITY
var speed_kmh:=60.0
var quality_multiplier:=4
var duration:=2.5
var elapsed:=0.0
var preparation_s:=0.0
var next_sample:=0.0
var armed:=false
var completed:=false
var error: String=''
var full_steps:=0
var authoring_step_us:=0
var simulation_call_us:=0
var setup_us:=0
var start_us:=0
var maximum_mass_error:=0.0
var first_gap:=INF
var preparation_velocity:=Vector3.ZERO
var first_body_gap:=INF
var initial_metrics: Dictionary={}

static func probes(g: RefCounted) -> Array:
 var result: Array=[]
 for i in g.points.size():
  if g.wheels.by_node.has(i):continue
  result.append({'source':'body','node':i,'position':g.points[i],'velocity':g.velocities[i],'radius':float(g.radii[i]),'rest':g.rest[i],'mass':float(g.masses[i])})
 for wheel in g.wheels.wheels:
  var support: Vector3=g.wheels.support(wheel,Vector3.DOWN)
  result.append({'source':'wheel','node':int(wheel.node),'position':g.points[wheel.node]+support,'velocity':g.velocities[wheel.node],'radius':0.0,'rest':g.rest[wheel.node],'support':support,'mass':float(g.masses[wheel.node])})
 if g.panels_runtime_enabled:
  for panel in g.panels.panels:
   for k in panel.points.size():result.append({'source':'panel','panel':panel.id,'node':k,'position':panel.points[k],'velocity':panel.velocity[k],'radius':.04,'rest':panel.rest[k],'mass':float(panel.mass)/panel.points.size()})
 return result

static func minimum_gap(g: RefCounted) -> float:
 var minimum:=INF
 for p in probes(g):minimum=minf(minimum,float(p.position.y)-float(p.radius))
 return minimum

static func time_to_contact(g: RefCounted,horizon: float) -> float:
 var first:=INF
 var gravity: float=maxf(0,float(g.config.gravity_mps2))
 for p in probes(g):
  var gap: float=p.position.y-p.radius;var vy: float=p.velocity.y
  if gap<=1e-8:
   if vy<-.01:first=0
   continue
  var t:=INF
  if gravity>1e-7:t=2*gap/(sqrt(vy*vy+4*gravity*gap)-vy)
  elif vy<-.000001:t=-gap/vy
  if t>=0 and t<=horizon+1e-10:first=minf(first,t)
 return first

static func floor_signature(g: RefCounted,velocity: Vector3,tolerance: float=.0002) -> Dictionary:
 var basis:=Roof.full_chassis_basis(g)
 var local_normal: Vector3=basis.transposed()*Vector3.UP
 var grid:=Grid.new();var masses: Dictionary={};var total:=0.0;var contacts: Array=[]
 for p in probes(g):
  if float(p.position.y)-float(p.radius)>tolerance:continue
  var rest: Vector3=p.rest-local_normal*float(p.radius)
  if p.source=='wheel':rest=p.rest+basis.transposed()*p.support
  var id: int=grid.zone(rest)
  masses[id]=float(masses.get(id,0))+p.mass;total+=float(p.mass)
  contacts.append({'source':p.source,'node':p.node,'panel':p.get('panel',''),'zone':id,'gap_m':float(p.position.y)-float(p.radius)})
 if contacts.is_empty() or velocity.y>=-.1:return {}
 var speed: float=-velocity.y
 var momentum: float=g.config.mass_kg*speed;var energy: float=.5*g.config.mass_kg*speed*speed
 var zones: Array=[];var ids:=masses.keys();ids.sort()
 for id in ids:
  var weight: float=masses[id]/total
  zones.append({'id':id,'weight':weight,'incident_impulse_proxy_ns':momentum*weight,'incident_energy_proxy_j':energy*weight})
 return {'zones':zones,'normal':[local_normal.x,local_normal.y,local_normal.z],'world_normal':[0,1,0],'velocity':[velocity.x,velocity.y,velocity.z],'closing_speed_mps':speed,'incident_impulse_proxy_ns':momentum,'incident_energy_proxy_j':energy,'first_contacts':contacts,'grid':[5,3,3],'contact_source':'body_or_oriented_tire_or_panel_cage_floor'}

func start(case_key: String='top',impact_speed_kmh: float=60,quality: int=4) -> void:
 start_us=Time.get_ticks_usec()
 descriptor=Cases.find(case_key)
 assert(not descriptor.is_empty() and impact_speed_kmh>0 and quality in [1,2,4])
 speed_kmh=impact_speed_kmh;quality_multiplier=quality
 vehicle=Vehicle.new();vehicle.setup('res://vehicles/niva.json',false)
 vehicle.adaptive_enabled=false;vehicle.reset(0,Vector3.ZERO);vehicle.set_simulation_quality(quality)
 var g: RefCounted=vehicle.solver
 g.config.enforce_symmetry=false;g.compact_active=false;g.barrier_enabled=false;g.terrain=null;vehicle.mode='FULL'
 var q: Array=descriptor.rotation_xyzw
 var rotation:=Basis(Quaternion(q[0],q[1],q[2],q[3]))
 for i in g.points.size():g.points[i]=rotation*g.rest[i];g.velocities[i]=Vector3.DOWN*speed_kmh/3.6
 for wheel in g.wheels.wheels:
  wheel.rotation=rotation.get_rotation_quaternion();wheel.previous_rotation=wheel.rotation;wheel.angular_velocity=Vector3.ZERO;wheel.spin_speed=0
 _synchronize()
 var offset:=Vector3(-12,float(descriptor.clearance_m)-minimum_gap(g),0)
 for i in g.points.size():g.points[i]+=offset
 _synchronize()
 g.initial_energy=g.kinetic_energy();g.maximum_energy=g.initial_energy
 vehicle.compact.capture_shape()
 initial_metrics=_outcome()
 frames=[];result={};signature={};elapsed=0;preparation_s=0;next_sample=0;armed=false;completed=false;error='';full_steps=0;authoring_step_us=0;simulation_call_us=0;maximum_mass_error=0
 setup_us=Time.get_ticks_usec()-start_us

func _synchronize() -> void:
 var g: RefCounted=vehicle.solver
 if g.panels_runtime_enabled:g.panels.synchronize_inactive()
 if g.effects!=null:g.effects.synchronize()

func _register_contact(toi: float) -> void:
 var g: RefCounted=vehicle.solver
 var gravity: float=g.config.gravity_mps2
 for i in g.points.size():
  g.points[i]+=g.velocities[i]*toi+Vector3.DOWN*gravity*toi*toi;g.velocities[i]+=Vector3.DOWN*gravity*toi
 for panel in g.panels.panels:
  if not panel.active:continue
  for k in panel.points.size():
   panel.points[k]+=panel.velocity[k]*toi+Vector3.DOWN*gravity*toi*toi;panel.velocity[k]+=Vector3.DOWN*gravity*toi
 for wheel in g.wheels.wheels:
  wheel.spin=wrapf(wheel.spin+wheel.spin_speed*toi,-PI,PI)
  var angle: float=wheel.angular_velocity.length()*toi
  if angle>1e-9:wheel.rotation=(Quaternion(wheel.angular_velocity.normalized(),angle)*wheel.rotation).normalized()
 g.simulated_time+=toi;preparation_s+=toi
 preparation_velocity=vehicle.velocity()
 var correction:=Vector3.UP*(-speed_kmh/3.6-preparation_velocity.y)
 for i in g.velocities.size():g.velocities[i]+=correction
 for panel in g.panels.panels:
  if panel.active:
   for k in panel.velocity.size():panel.velocity[k]+=correction
 _synchronize()
 first_gap=minimum_gap(g);first_body_gap=Roof.minimum_body_floor_gap(g)
 signature=floor_signature(g,preparation_velocity+correction)
 if signature.is_empty():_fail('No physical contact at computed boundary');return
 contact_rotation=Roof.full_chassis_basis(g).get_rotation_quaternion();origin=g.station_center(2)
 g.initial_energy=g.kinetic_energy();g.maximum_energy=g.initial_energy;g.impact_started=true;g.impact_time=g.simulated_time
 armed=true;frames.append(Clip.local_frame(g,origin));next_sample=1.0/120

func _simulate(dt: float) -> void:
 var began:=Time.get_ticks_usec();vehicle.step(dt);simulation_call_us+=Time.get_ticks_usec()-began;full_steps+=1

func step() -> void:
 if completed:return
 var began:=Time.get_ticks_usec();var g: RefCounted=vehicle.solver;var dt: float=g.config.fixed_step_s
 if not armed:
  var toi:=time_to_contact(g,dt)
  if not is_finite(toi):
   _simulate(dt);preparation_s+=dt;authoring_step_us+=Time.get_ticks_usec()-began
   if preparation_s>3:_fail('No contact within bounded 3 second preparation')
   return
  _register_contact(toi)
  if completed:return
 _simulate(dt);elapsed+=dt
 if elapsed+1e-9>=next_sample:
  maximum_mass_error=maxf(maximum_mass_error,absf(g.owned_mass_kg()-1210))
  for point in g.points:
   if not point.is_finite():_fail('Nonfinite body state');return
  for panel in g.panels.panels:
   for point in panel.points:
    if not point.is_finite():_fail('Nonfinite panel cage state');return
  frames.append(Clip.local_frame(g,origin));next_sample+=1.0/120
 authoring_step_us+=Time.get_ticks_usec()-began
 if elapsed+1e-9>=duration:_complete()

func _fail(message: String) -> void:
 error=message;completed=true;push_error('MULTIAXIS_AUTHORING_FAILED '+message)

func _outcome() -> Dictionary:
 var g: RefCounted=vehicle.solver;var panels: Array=[]
 for panel in g.panels.panels:panels.append({'id':panel.id,'active':panel.active,'latched':panel.latched,'detached':panel.detached,'plastic_work_j':panel.plastic_work,'broken_anchors':panel.anchors.filter(func(a):return a.broken).size(),'contacts':panel.contacts})
 var panes: Dictionary={}
 for id in g.effects.glass.capture().panes:
  var pane: Dictionary=g.effects.glass.capture().panes[id]
  panes[id]={'stage':pane.get('stage',0),'crack':pane.get('crack',0),'missing_cells':Array(pane.get('mask',[])).count(0),'released_cells':Array(pane.get('released',[])).count(1),'events':pane.get('events',[]).size()}
 return {'mass_kg':g.owned_mass_kg(),'panels':panels,'panes':panes,'body_plastic_work_j':g.plastic_work,'body_metrics':g.metrics()}

static func input_fingerprints(g: RefCounted) -> Dictionary:
 var inputs: Dictionary={}
 for path in ['structure.json','structures/niva_multiaxis_live.json','vehicles/niva.json','scripts/multiaxis_crash_cases.gd','scripts/multiaxis_crash_recorder.gd','scripts/roof_crash_recorder.gd','scripts/baked_crash_clip.gd','scripts/structure_solver.gd','scripts/wheel_physics.gd','scripts/vehicle_dynamics.gd','scripts/vehicle_simulation.gd','scripts/compact_chassis.gd','scripts/collision_forecast.gd','scripts/impact_zone_grid.gd','scripts/vehicle_effects.gd','scripts/vehicle_glass.gd','scripts/vehicle_interior.gd']:
  inputs[path]=FileAccess.get_sha256('res://'+path)
 inputs.merge(g.panels.input_fingerprints(),true)
 inputs.merge(g.effects.glass.input_fingerprints(),true);inputs.merge(g.effects.interior.input_fingerprints(),true)
 return inputs

func _complete() -> void:
 var g: RefCounted=vehicle.solver
 if frames.size()!=301 or maximum_mass_error>.00001:_fail('Frame count or mass conservation failed');return
 completed=true
 result={'metadata':{'version':3,'family':'multiaxis_floor','id':descriptor.key+'_'+str(roundi(speed_kmh)),'direction_key':descriptor.key,'heading_deg':descriptor.azimuth_deg,'fixture_descriptor':descriptor,'launch_mode':'full_car_floor_slam','speed_kmh':speed_kmh,'contact_velocity_normalized':true,'preparation_velocity_mps':[preparation_velocity.x,preparation_velocity.y,preparation_velocity.z],'preparation_s':preparation_s,'first_physical_floor_gap_m':first_gap,'first_body_floor_gap_m':first_body_gap,'duration_s':duration,'sample_hz':120,'physics_hz':roundi(1.0/float(g.config.fixed_step_s)),'quality_multiplier':quality_multiplier,'material_profile':g.config.get('material_profile','legacy'),'material_profile_version':g.config.get('material_profile_version',0),'panels_schema':1,'initial_mass_kg':initial_metrics.mass_kg,'maximum_mass_error_kg':maximum_mass_error,'grid':[5,3,3],'signature':signature,'origin':[origin.x,origin.y,origin.z],'contact_rotation_xyzw':[contact_rotation.x,contact_rotation.y,contact_rotation.z,contact_rotation.w],'full_solver_steps':full_steps,'setup_wall_ms':setup_us/1000.0,'simulation_call_wall_ms':simulation_call_us/1000.0,'authoring_step_wall_ms':authoring_step_us/1000.0,'total_wall_ms':(Time.get_ticks_usec()-start_us)/1000.0,'structure_sha256':FileAccess.get_sha256('res://structure.json'),'wheel_solver_sha256':FileAccess.get_sha256('res://scripts/wheel_physics.gd'),'input_sha256':input_fingerprints(g),'initial_outcome':initial_metrics,'final_outcome':_outcome(),'scope':'Actual full physics, closed latched panels, earliest body/tire/panel contact. Incident energy and momentum are proxies, not calibrated reaction measurements. Scoped timings are monotonic wall time, process CPU is measured by batch supervisor.'},'frames':frames}
