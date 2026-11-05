extends RefCounted
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Zones=preload('res://scripts/impact_zone_grid.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
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

func setup(clip_data: Dictionary) -> void:
 setup_library([clip_data],float(clip_data.metadata.get('heading_deg',0)),float(clip_data.metadata.speed_kmh))

func setup_library(clips: Array,heading_degrees: float=0,speed_kmh: float=120) -> void:
 library=clips
 approach_angle_deg=heading_degrees
 approach_speed_kmh=speed_kmh
 vehicle=Vehicle.new()
 vehicle.setup('res://vehicles/niva.json',false)
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
 for w in vehicle.solver.wheels.wheels:
  w.spin_speed=-speed*cos(deg_to_rad(approach_angle_deg))/w.radius
  w.spin=wrapf(w.spin-w.spin_speed*approach_distance/speed,-PI,PI)
 state='APPROACH';time=0;incoming={};match_result={};full_steps=0;player_cpu_us=0;sample_count=0
 handoff_position_jump_m=0;pose_registration_error_m=0
 handoff_offsets.clear();handoff_velocity_offsets.clear();wheel_spin_offsets.clear();wheel_handoff_rotations.clear()
 replay_rotation=Basis.IDENTITY

func attach_live(owner: RefCounted,clips: Array,signature: Dictionary,selection: Dictionary) -> void:
 # Reuse the live graph without constructing another vehicle or owning owner.
 _owned_vehicle=null;_live_vehicle=weakref(owner)
 library=clips;incoming=signature;match_result=selection
 data=library[int(selection.index)]
 time=0;state='REPLAY';full_steps=0;player_cpu_us=0;sample_count=0
 handoff_offsets.clear();handoff_velocity_offsets.clear();wheel_spin_offsets.clear();wheel_handoff_rotations.clear()
 handoff_position_jump_m=0;handoff_velocity_jump_mps=0;pose_registration_error_m=0
 _begin_replay()

func _begin_replay() -> void:
 var g: RefCounted=vehicle.solver
 var before: PackedVector3Array=g.points.duplicate()
 var velocity_before: PackedVector3Array=g.velocities.duplicate()
 var wheel_before: Array=g.wheels.capture()
 # Register selected clip in the incoming car heading and contact anchor.
 var body_x: Vector3=grid.body_basis(g).x
 var actual_heading: float=rad_to_deg(atan2(-body_x.z,body_x.x))
 replay_rotation=Basis(Vector3.UP,deg_to_rad(actual_heading-float(data.metadata.heading_deg)))
 origin=g.station_center(2)
 Clip.apply(g,data,0,origin,replay_rotation)
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
 apply_pose(0)
 for i in before.size():
  handoff_position_jump_m=maxf(handoff_position_jump_m,before[i].distance_to(g.points[i]))
  handoff_velocity_jump_mps=maxf(handoff_velocity_jump_mps,velocity_before[i].distance_to(g.velocities[i]))

func apply_pose(at_time: float) -> void:
 var g: RefCounted=vehicle.solver
 Clip.apply(g,data,at_time,origin,replay_rotation)
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

func advance(dt: float) -> void:
 if state in ['COMPLETE','REJECTED']:return
 var began: int=Time.get_ticks_usec()
 var g: RefCounted=vehicle.solver
 if state=='APPROACH':
  var toi: float=grid.time_to_contact(g,incoming_velocity,dt)
  var travel: float=toi if is_finite(toi) else dt
  origin+=incoming_velocity*travel
  for i in g.points.size():g.points[i]+=incoming_velocity*travel
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
  sample_count+=1
  if time>=float(data.metadata.duration_s)-1e-8:state='COMPLETE'
 player_cpu_us+=Time.get_ticks_usec()-began
