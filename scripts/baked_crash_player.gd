extends RefCounted
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Zones=preload('res://scripts/impact_zone_grid.gd')
const States=preload('res://scripts/conditioned_crash_transitions.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Roof=preload('res://scripts/roof_crash_recorder.gd')
const RoofResponse=preload('res://scripts/roof_landing_response.gd')
var roof_horizontal_delta:=Vector3.ZERO
var _owned_vehicle: RefCounted
var _live_vehicle: WeakRef
var vehicle: RefCounted:
 get:return _live_vehicle.get_ref() if _live_vehicle!=null else _owned_vehicle
 set(value):
  _owned_vehicle=value;_live_vehicle=null
var grid:=Zones.new()
var library: Array=[]
var data: Dictionary={}
var origin:=Vector3.ZERO
var incoming_velocity:=Vector3.ZERO
var approach_distance:=8.0
var approach_angle_deg:=0.0
var approach_speed_kmh:=120.0
var state: String='READY'
var time:=0.0
var incoming: Dictionary={}
var match_result: Dictionary={}
var full_steps:=0
var player_cpu_us:=0
var sample_count:=0
var handoff_position_jump_m:=0.0
var pose_registration_error_m:=0.0
var replay_rotation:=Basis.IDENTITY
var handoff_offsets:=PackedVector3Array()
var handoff_velocity_offsets:=PackedVector3Array()
var handoff_velocity_jump_mps:=0.0
var wheel_spin_offsets:=PackedFloat64Array()
var wheel_handoff_rotations: Array=[]
var blend_seconds:=.10
var persistent_free_wheels:=PackedInt32Array()
var irreversible_initial: Dictionary={}
var surface_initial: Dictionary={}
var persistent_free_panels: Array=[]
var panel_handoff: Dictionary={}

func setup(clip_data: Dictionary) -> void:
 setup_library([clip_data],float(clip_data.metadata.get('heading_deg',0)),float(clip_data.metadata.speed_kmh))

func setup_library(clips: Array,heading_degrees: float=0,speed_kmh: float=120) -> void:
 library=clips
 approach_angle_deg=heading_degrees
 approach_speed_kmh=speed_kmh
 vehicle=Vehicle.new()
 vehicle.setup('res://vehicles/niva.json',false)
 for clip in library:Clip.prepare_surfaces(vehicle.solver,clip)
 vehicle.solver.set_impact_mode(0)
 vehicle.solver.config.enforce_symmetry=false
 reset()

func reset() -> void:
 # One common pristine template for every approach. No clip is selected yet.
 data=library[0]
 for candidate in library:
  if absf(float(candidate.metadata.heading_deg))<.001 and absf(float(candidate.metadata.speed_kmh)-approach_speed_kmh)<.001:data=candidate;break
 var heading:=Basis(Vector3.UP,deg_to_rad(approach_angle_deg))
 var template_angle: float=float(data.metadata.get('heading_deg',0))
 var template_rotation:=Basis(Vector3.UP,deg_to_rad(approach_angle_deg-template_angle))
 origin=Vector3.ZERO
 Clip.apply(vehicle.solver,data,0,origin,template_rotation)
 var leading_x: float=-INF
 for i in vehicle.solver.points.size():leading_x=maxf(leading_x,vehicle.solver.points[i].x+vehicle.solver.radii[i])
 origin=Vector3(-leading_x,float(data.metadata.origin[1]),0)
 var direction: Vector3=Vector3.RIGHT
 origin-=direction*approach_distance
 Clip.apply(vehicle.solver,data,0,origin,template_rotation)
 var speed: float=approach_speed_kmh/3.6
 incoming_velocity=direction*speed
 for i in vehicle.solver.velocities.size():vehicle.solver.velocities[i]=incoming_velocity
 if vehicle.solver.panels_runtime_enabled:
  for p in vehicle.solver.panels.panels:
   p.velocity.fill(incoming_velocity)
   if p.has('reduced_data'):p.reduced_data.linear=incoming_velocity;p.reduced_data.omega=Vector3.ZERO
 for w in vehicle.solver.wheels.wheels:
  w.spin_speed=-speed*cos(deg_to_rad(approach_angle_deg))/w.radius
  w.spin=wrapf(w.spin-w.spin_speed*approach_distance/speed,-PI,PI)
 persistent_free_wheels.clear();irreversible_initial={}
 persistent_free_panels.clear();panel_handoff.clear()
 state='APPROACH';time=0;incoming={};match_result={};full_steps=0;player_cpu_us=0;sample_count=0
 handoff_position_jump_m=0;pose_registration_error_m=0
 handoff_offsets.clear();handoff_velocity_offsets.clear();wheel_spin_offsets.clear();wheel_handoff_rotations.clear()
 replay_rotation=Basis.IDENTITY

func attach_live(owner: RefCounted,clips: Array,signature: Dictionary,selection: Dictionary) -> void:
 # Reuse the live graph without constructing another vehicle or owning owner.
 _owned_vehicle=null;_live_vehicle=weakref(owner)
 library=clips;incoming=signature;match_result=selection
 data=library[int(selection.index)]
 roof_horizontal_delta=Vector3.ZERO
 if data.metadata.get('family','')=='roof_landing_floor':
  data=RoofResponse.prepare(owner.solver,data)
  blend_seconds=.30
 time=0;state='REPLAY';full_steps=0;player_cpu_us=0;sample_count=0
 handoff_offsets.clear();handoff_velocity_offsets.clear();wheel_spin_offsets.clear();wheel_handoff_rotations.clear()
 handoff_position_jump_m=0;handoff_velocity_jump_mps=0;pose_registration_error_m=0
 persistent_free_wheels=States.detached_wheel_indices(vehicle.solver)
 irreversible_initial=vehicle.solver.capture()
 persistent_free_panels=[]
 if vehicle.solver.panels_runtime_enabled:
  for p in vehicle.solver.panels.panels:
   if p.detached:persistent_free_panels.append(p.id)
 _begin_replay()

func _begin_replay() -> void:
 var g: RefCounted=vehicle.solver
 surface_initial=g.effects.surface.capture() if g.effects!=null else {}
 var before: PackedVector3Array=g.points.duplicate()
 var velocity_before: PackedVector3Array=g.velocities.duplicate()
 var wheel_before: Array=g.wheels.capture()
 var panels_before: Dictionary=g.panels.capture() if g.panels_runtime_enabled else {}
 var retained: Dictionary=_retained_components(g)
 if g.effects!=null:
  var initial_effects: Dictionary=data.frames[0].get('effects',{}).duplicate(true)
  for id in retained.get('glass',{}):initial_effects.glass.panes[id]=retained.glass[id]
  g.effects.begin_playback(initial_effects)
 # Register selected clip in the incoming car heading and contact anchor.
 if data.metadata.has('contact_rotation_xyzw'):
  var q: Array=data.metadata.contact_rotation_xyzw
  var recorded:=Basis(Quaternion(q[0],q[1],q[2],q[3]))
  replay_rotation=Roof.full_chassis_basis(g)*recorded.transposed()
 else:
  var body_x: Vector3=grid.body_basis(g).x
  var actual_heading: float=rad_to_deg(atan2(-body_x.z,body_x.x))
  replay_rotation=Basis(Vector3.UP,deg_to_rad(actual_heading-float(data.metadata.heading_deg)))
 origin=g.station_center(2)
 if data.metadata.get('family','')=='roof_landing_floor':
  # Register the recorded floor to the actual contact plane, independent of
  # car roll/pitch. The pose difference blends from the incoming car state.
  var actual_x: Vector3=Roof.full_chassis_basis(g).x
  var q: Array=data.metadata.contact_rotation_xyzw
  var recorded_x: Vector3=Basis(Quaternion(q[0],q[1],q[2],q[3])).x
  var n: Array=match_result.get('ground_normal',[0,1,0]);var ground_normal:=Vector3(n[0],n[1],n[2]).normalized()
  var forward: Vector3=actual_x-ground_normal*actual_x.dot(ground_normal)
  if forward.length()<.15:forward=ground_normal.cross(Vector3.BACK)
  forward=forward.normalized()
  var target:=Basis(forward,ground_normal,forward.cross(ground_normal).normalized())
  var reference:=Basis(Vector3.UP,atan2(-recorded_x.z,recorded_x.x))
  replay_rotation=target*reference.transposed()
  var point: Array=match_result.get('ground_point',[origin.x,g.floor_sample(origin).w,origin.z])
  var contact_point:=Vector3(point[0],point[1],point[2])
  origin+=ground_normal*(float(data.metadata.origin[1])-(origin-contact_point).dot(ground_normal))
  var actual_velocity: Vector3=(velocity_before[8]+velocity_before[9]+velocity_before[10]+velocity_before[11])*.25
  var recorded_velocity: Vector3=(data.frames[0].velocities[8]+data.frames[0].velocities[9]+data.frames[0].velocities[10]+data.frames[0].velocities[11])*.25
  roof_horizontal_delta=replay_rotation.transposed()*actual_velocity-recorded_velocity;roof_horizontal_delta.y=0
 var initial_data: Dictionary=RoofResponse.view(data,0,roof_horizontal_delta) if data.metadata.get('family','')=='roof_landing_floor' else data
 Clip.apply(g,initial_data,0,origin,replay_rotation,retained)
 panel_handoff={}
 if g.panels_runtime_enabled and not panels_before.is_empty():
  for old in panels_before.panels:
   var p: Dictionary=g.panels.find(old.id)
   var offsets:=PackedVector3Array();var velocities:=PackedVector3Array()
   for k in 10:offsets.append(old.points[k]-p.points[k]);velocities.append(old.velocity[k]-p.velocity[k])
   panel_handoff[p.id]={'position':offsets,'velocity':velocities}
   if p.id in persistent_free_panels:_restore_free_panel(old)
  g.reconcile_panel_masses()
 handoff_offsets.resize(g.points.size())
 handoff_velocity_offsets.resize(g.points.size())
 for i in g.points.size():
  handoff_offsets[i]=before[i]-g.points[i]
  handoff_velocity_offsets[i]=velocity_before[i]-g.velocities[i]
  pose_registration_error_m=maxf(pose_registration_error_m,handoff_offsets[i].length())
 for i in g.wheels.wheels.size():
  var w= g.wheels.wheels[i]
  wheel_spin_offsets.append(angle_difference(w.spin,wheel_before[i].spin))
  wheel_handoff_rotations.append(wheel_before[i].rotation)
 if not persistent_free_wheels.is_empty():
  var restored_wheels: Array=g.wheels.capture()
  for index in persistent_free_wheels:
   var node: int=g.wheels.wheels[index].node
   g.points[node]=before[node];g.velocities[node]=velocity_before[node]
   restored_wheels[index]=wheel_before[index]
  g.wheels.restore(restored_wheels)
 apply_pose(0)
 for i in before.size():
  handoff_position_jump_m=maxf(handoff_position_jump_m,before[i].distance_to(g.points[i]))
  handoff_velocity_jump_mps=maxf(handoff_velocity_jump_mps,velocity_before[i].distance_to(g.velocities[i]))

func apply_pose(at_time: float) -> void:
 var g: RefCounted=vehicle.solver
 var preserved: Dictionary={}
 var free_panels: Array=[]
 if g.panels_runtime_enabled:
  for p in g.panels.capture().panels:
   if p.id in persistent_free_panels:free_panels.append(p)
 if not persistent_free_wheels.is_empty():
  preserved={'wheels':g.wheels.capture(),'points':g.points.duplicate(),'velocities':g.velocities.duplicate()}
 var sampled: Dictionary=RoofResponse.view(data,at_time,roof_horizontal_delta) if data.metadata.get('family','')=='roof_landing_floor' else data
 Clip.apply(g,sampled,at_time,origin,replay_rotation,_retained_components(g))
 var s: float=clampf(at_time/blend_seconds,0,1)
 var weight: float=1-3*s*s+2*s*s*s
 var velocity_weight: float=s*s*s-2*s*s+s
 var dp: float=(-6*s+6*s*s)/blend_seconds if s<1 else 0
 var dv: float=3*s*s-4*s+1 if s<1 else 0
 for i in handoff_offsets.size():
  g.points[i]+=handoff_offsets[i]*weight+handoff_velocity_offsets[i]*blend_seconds*velocity_weight
  g.velocities[i]+=handoff_offsets[i]*dp+handoff_velocity_offsets[i]*dv
 for i in wheel_spin_offsets.size():
  var w=g.wheels.wheels[i]
  w.spin=wrapf(w.spin+wheel_spin_offsets[i],-PI,PI)
  # Only the small pre-contact hub-pose discrepancy is blended out.
  var initial: Quaternion=(replay_rotation.get_rotation_quaternion()*data.frames[0].wheels[i].rotation).normalized()
  var correction: Quaternion=wheel_handoff_rotations[i]*initial.inverse()
  w.rotation=(Quaternion.IDENTITY.slerp(correction,weight)*w.rotation).normalized()
 if g.panels_runtime_enabled:
  for id in panel_handoff:
   if id in persistent_free_panels:continue
   var p: Dictionary=g.panels.find(id);var offsets: Dictionary=panel_handoff[id]
   var dc:=Vector3.ZERO;var dv_:=Vector3.ZERO
   for k in 10:
    var dx: Vector3=offsets.position[k]*weight+offsets.velocity[k]*blend_seconds*velocity_weight
    var v: Vector3=offsets.position[k]*dp+offsets.velocity[k]*dv
    p.points[k]+=dx;p.velocity[k]+=v;dc+=dx/10;dv_+=v/10
   if p.has('reduced_data'):p.reduced_data.center+=dc;p.reduced_data.linear+=dv_
  for p in free_panels:_restore_free_panel(p)
  g.reconcile_panel_masses();g.panels.pose_revision+=1

 if not irreversible_initial.is_empty():States.irreversible_floor(g,irreversible_initial)
 if g.effects!=null and not surface_initial.is_empty():g.effects.surface.retain(surface_initial)
 if not preserved.is_empty():
  var wheel_state: Array=g.wheels.capture()
  for index in persistent_free_wheels:
   var node: int=g.wheels.wheels[index].node
   g.points[node]=preserved.points[node];g.velocities[node]=preserved.velocities[node]
   wheel_state[index]=preserved.wheels[index]
  g.wheels.restore(wheel_state)
 if data.metadata.get('family','')=='roof_landing_floor':
  var gap:=INF;var lift_normal:=Vector3.UP
  for i in g.points.size():
   if g.wheels.by_node.has(i):continue
   var floor_: Vector4=g.floor_sample(g.points[i]);var normal:=Vector3(floor_.x,floor_.y,floor_.z).normalized()
   var distance: float=(g.points[i].y-floor_.w)*normal.y-g.radii[i]
   if distance<gap:gap=distance;lift_normal=normal
  for p in g.panels.panels:
   if p.detached:continue
   for point in p.points:
    var floor_: Vector4=g.floor_sample(point);var normal:=Vector3(floor_.x,floor_.y,floor_.z).normalized()
    var distance: float=(point.y-floor_.w)*normal.y-.04
    if distance<gap:gap=distance;lift_normal=normal
  if gap<-.002:
   var lift:=lift_normal*(-gap)
   for i in g.points.size():g.points[i]+=lift
   for p in g.panels.panels:
    if p.detached:continue
    for i in p.points.size():p.points[i]+=lift
    if p.has('reduced_data'):p.reduced_data.center+=lift
   g.panels.pose_revision+=1

func _advance_existing_free_wheels(dt: float) -> void:
 if dt<1e-8:return
 var g: RefCounted=vehicle.solver
 for index in persistent_free_wheels:
  var wheel=g.wheels.wheels[index];var node: int=wheel.node
  g.wheels.predict_one(index,dt)
  g.old_points[node]=g.points[node]
  g.velocities[node].y-=float(g.config.gravity_mps2)*dt
  g.points[node]+=g.velocities[node]*dt
  g.contact_floor[node]=0;g.contact_wall[node]=0
  for iteration in 3:g.wheels.contacts_one(index,dt,false)
  g.velocities[node]=(g.points[node]-g.old_points[node])/dt
  g.wheels.finish_one(index,dt)

func advance(dt: float) -> void:
 if state in ['COMPLETE','REJECTED']:return
 var began: int=Time.get_ticks_usec()
 var g: RefCounted=vehicle.solver
 if state=='APPROACH':
  var toi: float=grid.time_to_contact(g,incoming_velocity,dt)
  var travel: float=toi if is_finite(toi) else dt
  origin+=incoming_velocity*travel
  for i in g.points.size():g.points[i]+=incoming_velocity*travel
  if g.panels_runtime_enabled:
   var panel_state: Dictionary=Clip.PanelState.transformed(g.panels.capture(),Basis.IDENTITY,incoming_velocity*travel)
   g.panels.restore(panel_state)
  for w in g.wheels.wheels:w.spin=wrapf(w.spin+w.spin_speed*travel,-PI,PI)
  if is_finite(toi):
   incoming=grid.signature(g,incoming_velocity)
   match_result=grid.choose(incoming,library)
   state='REPLAY' if match_result.accepted else 'REJECTED'
   time=0
   if state=='REPLAY':
    data=library[int(match_result.index)]
    _begin_replay()
 elif state=='REPLAY':
  time=minf(float(data.metadata.duration_s),time+dt)
  apply_pose(time)
  _advance_existing_free_wheels(dt)
  if not persistent_free_panels.is_empty() and vehicle.reduced_panels!=null:vehicle.reduced_panels.step(dt,persistent_free_panels,false)
  sample_count+=1
  if time>=float(data.metadata.duration_s)-1e-8:state='COMPLETE'
 if g.effects!=null:g.effects.step_debris(dt)
 player_cpu_us+=Time.get_ticks_usec()-began

func _restore_free_panel(snapshot: Dictionary) -> void:
 var p: Dictionary=vehicle.solver.panels.find(snapshot.id)
 vehicle.solver.panels.restore_panel(snapshot)
 if not p.get('reduced',false):vehicle.reduced_panels.freeze(p)

func _retained_components(g: RefCounted) -> Dictionary:
 var retained: Dictionary={'panels':[],'glass':{}}
 if not g.panels_runtime_enabled or persistent_free_panels.is_empty():return retained
 for p in g.panels.capture().panels:
  if p.id in persistent_free_panels:retained.panels.append(p)
 if g.effects!=null:
  var glass: Dictionary=g.effects.glass.capture()
  for id in glass.panes:
   if g.panels.panel_for_glass(id) in persistent_free_panels:retained.glass[id]=glass.panes[id]
 return retained
