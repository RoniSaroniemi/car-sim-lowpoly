extends RefCounted
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Library=preload('res://probes/multicar/library.gd')
var vehicle: RefCounted
var graph: RefCounted
var id: int
var center:=Vector3.ZERO
var yaw:=0.0
var velocity:=Vector3.ZERO
var omega:=0.0
var mass:=1210.0
var inertia:=1850.0
var root_nodes_condensed:=true
var local_points:=PackedVector3Array()
var rest_local:=PackedVector3Array()
var bounds_center:=Vector3.ZERO
var half:=Vector2(2.02,.92)
var clip_id: String=''
var clip_time:=0.0
var played:=0
var last_selection: Dictionary={}
var contact_events: Array=[]
var prior_irreversible: Dictionary={}
var interpolation_origin:=PackedVector3Array()
var handoff_error:=0.0
var throttle:=0.0
var brake:=0.0
var steering:=0.0
var floor_drag:=false
var physics_steps:=0
var unsupported_contacts:=0
var spin_phase:=0.0
var transient_mass_owner_count:=1
func setup(number: int,position_: Vector3,heading: float,motion: Vector3) -> void:
 id=number;vehicle=Vehicle.new();vehicle.setup('res://vehicles/niva.json',false);graph=vehicle.solver
 # This planar proof keeps all panels condensed in the sole root mass.
 # Production opening-panel cages are intentionally outside this adapter.
 graph.panels_runtime_enabled=false;graph.reconcile_panel_masses()
 graph.barrier_enabled=false;graph.compact_active=false
 center=position_;yaw=heading;velocity=motion
 var mean:=Vector3.ZERO
 for i in graph.rest.size():mean+=graph.rest[i]*graph.masses[i]
 mean/=mass
 for p in graph.rest:rest_local.append(p-mean)
 local_points=rest_local.duplicate();publish(0)
func basis() -> Basis:return Basis(Vector3.UP,yaw)
func forward() -> Vector3:return basis().x
func root_energy() -> float:return .5*mass*velocity.length_squared()+.5*inertia*omega*omega
func begin_clip(chosen: String,selection: Dictionary) -> bool:
 if played>0 or not clip_id.is_empty():
  unsupported_contacts+=1;last_selection={'accepted':false,'reason':'damage_history_not_in_probe_bank','contacts':selection};return false
 var data: Dictionary=Library.get_clip(chosen,graph)
 if data.is_empty():last_selection={'accepted':false,'reason':'missing_composite_recording'};return false
 # This bounded proof uses attached-wheel clips only; don't silently steal free wheels.
 if data.frames.any(func(f):return f.wheels.any(func(w):return w.detached)):
  unsupported_contacts+=1;last_selection={'accepted':false,'reason':'detached_wheel_channel_needs_independent_owner'};return false
 prior_irreversible=graph.capture()
 interpolation_origin=local_points.duplicate()
 clip_id=chosen;clip_time=0;played+=1;last_selection=selection.duplicate(true)
 last_selection['accepted']=true;last_selection['clip']=chosen
 graph.effects.begin_playback(data.frames[0].effects)
 publish(0)
 return true
func controls_step(h: float) -> void:
 if throttle!=0:
  var speed: float=velocity.dot(forward())
  var power: float=220000/maxf(8,absf(speed))
  velocity+=forward()*throttle*minf(9500,power)/mass*h
  if velocity.length()>160.0/3.6:velocity=velocity.normalized()*160.0/3.6
 if brake>0:velocity=velocity.move_toward(Vector3.ZERO,brake*8*h)
 if floor_drag:
  var longitudinal: Vector3=forward()*velocity.dot(forward())
  velocity=(longitudinal+(velocity-longitudinal)*exp(-2.8*h)).move_toward(Vector3.ZERO,.08*h)
 if absf(steering)>.001 and velocity.length()>.5:omega=move_toward(omega,steering*clampf(velocity.dot(forward())*.045,-.8,.8),h*2)
 else:omega*=exp(-1.5*h)
func move_root(h: float) -> void:
 center+=velocity*h;yaw+=omega*h
func advance_shape(h: float) -> void:
 physics_steps+=1
 if not clip_id.is_empty():clip_time=minf(float(Library.clips[clip_id].metadata.duration_s),clip_time+h)
 spin_phase-=velocity.dot(forward())/.39*h
 publish(h)
func publish(h: float) -> void:
 var before: PackedVector3Array=graph.points.duplicate()
 var state: Dictionary={};var source: Dictionary={}
 if not clip_id.is_empty():
  source=Library.frame(clip_id,clip_time);state=source.a.duplicate(true)
  local_points=source.points.duplicate()
  var s: float=clampf(clip_time/.08,0,1);var weight: float=s*s*(3-2*s)
  var initial: PackedVector3Array=Library.tracks[clip_id][0].points
  for i in local_points.size():local_points[i]+=(interpolation_origin[i]-initial[i])*(1-weight)
  state.time=graph.simulated_time+h
 else:state=graph.capture();state.time=graph.simulated_time+h
 var rotation:=basis();var lowest:=INF
 for wheel in graph.wheels.wheels:lowest=minf(lowest,local_points[wheel.node].y-wheel.radius)
 center.y=-lowest
 var points:=PackedVector3Array();var velocities:=PackedVector3Array()
 for i in local_points.size():
  var arm: Vector3=rotation*local_points[i]
  points.append(center+arm)
  velocities.append(velocity+Vector3.UP.cross(arm)*omega)
 state.points=points;state.velocities=velocities
 for i in state.wheels.size():
  var q: Quaternion=source.rotations[i] if not source.is_empty() else Quaternion.IDENTITY
  state.wheels[i].rotation=(rotation.get_rotation_quaternion()*q).normalized()
  state.wheels[i].spin=spin_phase
  state.wheels[i].angular_velocity=Vector3.UP*omega
 graph.restore(state,false)
 if not source.is_empty():
  graph.effects.restore_interpolated(source.a.effects,source.b.effects,source.alpha)
  graph.effects.surface.restore(source.surface)
  if not prior_irreversible.is_empty():
   graph.plastic_work=maxf(graph.plastic_work,prior_irreversible.plastic_work)
   for i in graph.links.size():
    graph.links[i].damage=maxf(graph.links[i].damage,prior_irreversible.link_damage[i]);graph.links[i].broken=graph.links[i].broken or bool(prior_irreversible.broken[i])
 graph.effects.step_debris(h)
 var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
 for i in 30:low=low.min(local_points[i]);high=high.max(local_points[i])
 bounds_center=(low+high)*.5;bounds_center.y=0
 half=Vector2((high.x-low.x)*.5+.12,(high.z-low.z)*.5+.10)
func capture() -> Dictionary:
 return {'id':id,'center':center,'yaw':yaw,'velocity':velocity,'omega':omega,'mass':mass,'inertia':inertia,'glass_transient':{'debris':graph.effects.glass.debris.duplicate(true),'emitted':graph.effects.glass.emitted.duplicate(true),'playback_clock':graph.effects.glass.playback_clock},'clip_id':clip_id,'clip_time':clip_time,'played':played,'local_points':local_points.duplicate(),'graph':graph.capture(),'selection':last_selection.duplicate(true),'spin':spin_phase}
func restore(state: Dictionary) -> void:
 center=state.center;yaw=state.yaw;velocity=state.velocity;omega=state.omega;mass=state.mass;inertia=state.inertia;clip_id=state.clip_id;clip_time=state.clip_time;played=state.played;local_points=state.local_points.duplicate();spin_phase=state.spin
 last_selection=state.selection.duplicate(true);graph.restore(state.graph)

 var transient: Dictionary=state.glass_transient
 graph.effects.glass.debris=transient.debris.duplicate(true)
 graph.effects.glass.emitted=transient.emitted.duplicate(true)
 graph.effects.glass.playback_clock=transient.playback_clock
