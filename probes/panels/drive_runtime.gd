extends RefCounted
## Probe driving adapter reuses the production compact chassis and tire dynamics.
const Graph=preload('res://probes/panels/panel_graph.gd')
const Compact=preload('res://scripts/compact_chassis.gd')
const Dynamics=preload('res://scripts/vehicle_dynamics.gd')
const RoadProfile=preload('res://probes/panels/road_panel_profile.gd')
const Reduced=preload('res://probes/panels/reduced_panels.gd')
var graph: RefCounted
var compact: RefCounted
var dynamics: RefCounted
var reduced: RefCounted
var h:=1.0/120
var full_h:=1.0/960
var full_remaining:=0.0
var mode_:='closed'
var full_steps:=0
var coarse_steps:=0
var ticks:=0
var time:=0.0
var sample_costs: Array=[]
var frames: Array=[]
var speed:=0.0
var wall:=true
var transitions: Array=[]
var body_projection_energy_j:=0.0

func start(kind: String='closed') -> void:
 mode_=kind;graph=Graph.new();graph.setup();graph.reset(0,Vector3.ZERO);graph.panels.reset()
 graph.config.enforce_symmetry=false
 RoadProfile.apply(graph.panels)
 if kind in ['right_free','right_sag']:
  var file:=FileAccess.open('res://probes/panels/data/'+kind+'.panelstate',FileAccess.READ)
  graph.restore(file.get_var(true))
  # This is the measured struck car, including plastic shape and broken mounts.
  RoadProfile.apply(graph.panels)
 graph.barrier_enabled=wall;graph.barrier_min=Vector3(45,0,-12);graph.barrier_max=Vector3(45.5,3.5,12)
 graph.panels.obstacle={};graph.structural_panel_wake=false
 graph.wake_requested='';graph.wake_hold_seconds=0
 _set_step(h)
 compact=Compact.new();compact.setup(graph);compact.capture_shape();graph.compact=compact;graph.compact_active=true
 dynamics=Dynamics.new();dynamics.setup(graph,JSON.parse_string(FileAccess.get_file_as_string('res://vehicles/niva.json')).dynamics)
 reduced=Reduced.new();reduced.setup(graph,compact)
 for p in graph.panels.panels:
  if p.active:reduced.freeze(p)
  if p.active and reduced.held_closed(p):reduced.dock(p)
 time=0;full_steps=0;coarse_steps=0;ticks=0;full_remaining=0;sample_costs.clear();frames=[capture()]

func controls(throttle: float,brake: float,steer: float,parking: float=0) -> void:
 dynamics.set_controls(throttle,brake,steer,parking)

func _near_hit() -> bool:
 if not graph.barrier_enabled:return false
 for i in compact.indices:
  var motion: Vector3=compact.point_velocity(i)
  var future: Vector3=graph.points[i]+motion*h
  var hit: Dictionary=graph.barrier_distance(future)
  if hit.distance<graph.radii[i]+.04 and motion.dot(hit.normal)<-1:return true
 for p in graph.panels.panels:
  if not p.active or p.detached:continue
  for i in [0,2,6,8,9]:
   var pos: Vector3=p.points[i]
   var hit: Dictionary=graph.barrier_distance(pos)
   if hit.distance<.06+p.velocity[i].length()*h and p.velocity[i].dot(hit.normal)<-1:return true
 return false

func begin_impact() -> void:
 if full_remaining>0:return
 var audit_before: Array=handoff_audit()
 graph.compact_active=false;full_remaining=.65;graph.structural_panel_wake=true;_set_step(full_h)
 graph.panels.obstacle={'center':(graph.barrier_min+graph.barrier_max)*.5,'size':graph.barrier_max-graph.barrier_min,'velocity':Vector3.ZERO,'retracting':true}
 for p in graph.panels.panels:
  if p.active:reduced.wake_impact(p)
 transitions.append({'to':'full_impact','time':time,'panel_handoff':audit_before})

func end_impact() -> void:
 graph.panels.obstacle={};graph.structural_panel_wake=false;_set_step(h)
 var before: float=graph.kinetic_energy()
 compact.mass=0
 for i in compact.indices:compact.mass+=graph.masses[i]
 compact.capture_shape();graph.compact_active=true;compact.flush()
 body_projection_energy_j+=maxf(0,before-graph.kinetic_energy())
 for p in graph.panels.panels:
  if p.active and not p.reduced:reduced.freeze(p)
  if p.active and reduced.held_closed(p):reduced.dock(p)
 transitions.append({'to':'lightweight','time':time,'body_projection_energy_j':maxf(0,before-graph.kinetic_energy())})

func _rigid_contacts(dt: float) -> void:
 for iteration in 3:
  for index in compact.indices:
   var point_: Vector3=compact.point(index)
   var floor_: Vector4=graph.floor_sample(point_)
   var normal:=Vector3(floor_.x,floor_.y,floor_.z).normalized()
   var depth: float=graph.radii[index]-(point_.y-floor_.w)
   if depth>0:_contact(index,normal,depth,dt)
   if graph.barrier_enabled:
    var hit: Dictionary=graph.barrier_distance(point_)
    depth=graph.radii[index]-float(hit.distance)
    if depth>0:_contact(index,hit.normal,depth,dt)
 compact.flush()
func _contact(index: int,normal: Vector3,depth: float,_dt: float) -> void:
 var weight: float=compact.constraint_weight(index,-1,normal,Vector3.ZERO)
 if weight<1e-8:return
 compact.correct(index,-1,normal,Vector3.ZERO,depth/weight)
 var inward: float=compact.point_velocity(index).dot(normal)
 if inward<0:compact.correct(index,-1,normal,Vector3.ZERO,-inward/weight,true)

func step() -> void:
 var began: int=Time.get_ticks_usec()
 if full_remaining<=0 and _near_hit():begin_impact()
 if full_remaining>0:
  for sub in 8:
   dynamics.step(full_h);graph.step(full_h);full_steps+=1
  full_remaining-=h
  if full_remaining<=0:end_impact()
 else:
  dynamics.step(h);compact.step(h);_rigid_contacts(h)
  reduced.step(h);coarse_steps+=1
 time+=h;speed=dynamics.body_velocity().length()*3.6
 sample_costs.append(Time.get_ticks_usec()-began)
 ticks+=1
 if ticks%2==0:
  frames.append(capture())
  if frames.size()>481:frames.pop_front()

func capture() -> Dictionary:
 return {'graph':graph.capture(),'time':time,'mode':mode_,'compact':{'center':compact.center,'rotation':compact.rotation,'linear':compact.linear_velocity,'angular':compact.angular_velocity},'full_remaining':full_remaining,'full_steps':full_steps,'coarse_steps':coarse_steps}
func restore(state: Dictionary) -> void:
 graph.restore(state.graph);time=state.time;mode_=state.mode;full_remaining=state.full_remaining
 compact.mass=0
 for i in compact.indices:compact.mass+=graph.masses[i]
 compact.capture_shape();graph.compact_active=true
 # Restore is for cheap inspection; no advance/collision/constraint work.
func stats() -> Dictionary:
 var sorted: Array=sample_costs.duplicate();sorted.sort();var total:=0.0
 for cost in sorted:total+=cost
 return {'mode':mode_,'speed_kmh':speed,'time_s':time,'full_structure_steps':full_steps,'full_panel_steps':graph.panels.active_steps,'coarse_body_steps':coarse_steps,'reduced':reduced.stats(),'mean_us':total/maxi(1,sorted.size()),'p95_us':sorted[mini(sorted.size()-1,floori(sorted.size()*.95))] if not sorted.is_empty() else 0,'p99_us':sorted[mini(sorted.size()-1,floori(sorted.size()*.99))] if not sorted.is_empty() else 0,'body_projection_energy_j':body_projection_energy_j,'mass_kg':graph.panels.total_mass()}

func _set_step(dt: float) -> void:
 graph.config.fixed_step_s=dt
 for link in graph.links:link.damping_fraction=1-exp(-link.damping_ns_per_m*link.weight_sum*dt)

func handoff_audit() -> Array:
 var out: Array=[];var frames_: Array=graph.panels.Attachment.rotations(graph)
 for p in graph.panels.panels:
  if not p.active:continue
  var errors: Array=[];var edge_error:=0.0
  for a in p.anchors:errors.append(p.points[a.node].distance_to(graph.panels.Attachment.mapped(graph,a.rest,a.binding,frames_)))
  for edge in p.edges:edge_error=maxf(edge_error,absf(p.points[edge.a].distance_to(p.points[edge.b])-edge.length))
  out.append({'id':p.id,'anchor_residual_m':errors,'enabled_anchors':p.anchors.map(func(a):return not a.broken),'latch_engaged':p.latched,'edge_residual_m':edge_error,'angle_deg':rad_to_deg(p.angle),'p0':p.points[0],'velocity0':p.velocity[0],'center_velocity':compact.linear_velocity})
 return out
