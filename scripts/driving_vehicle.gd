extends 'res://scripts/vehicle_simulation.gd'
## Driving adapter: unchanged live dynamics, with recorded ownership during compatible successive impacts.
const CrashPlayer=preload('res://scripts/baked_crash_player.gd')
const CrashClip=preload('res://scripts/baked_crash_clip.gd')
const ImpactGrid=preload('res://scripts/impact_zone_grid.gd')
const States=preload('res://scripts/conditioned_crash_transitions.gd')
const ConditionedAuthor=preload('res://scripts/conditioned_crash_authoring.gd')
const ContactSensor=preload('res://scripts/baked_contact_sensor.gd')
static var cached_library: Array=[]
static var cached_conditioned: Array=[]
var baked_enabled:=true
var bake_library: Array=[]
var conditioned_library: Array=[]
var sequence_active:=false
var sequence_notice:=''
var impact_grid:=ImpactGrid.new()
var contact_sensor:=ContactSensor.new()
var crash_player: RefCounted
var baked_consumed:=false
var baked_count:=0
var baked_steps:=0
var baked_cpu_us:=0
var baked_search_cpu_us:=0
var baked_seconds:=0.0
var rigid_contact_count:=0
var bake_clock:=0.0
var bake_start_clock:=0.0
var bake_start_full_steps:=0
var bake_end_full_steps:=0
var driver_accumulator:=0.0
var last_bake: Dictionary={}
var bake_status: String='Ready'

func setup(profile_path: String='res://vehicles/niva.json',enable_driving: bool=true) -> void:
 super.setup(profile_path,enable_driving)
 if cached_library.is_empty():cached_library=CrashClip.read_library()
 bake_library=cached_library
 if cached_conditioned.is_empty():cached_conditioned=States.read_library()
 conditioned_library=cached_conditioned

func reset(speed_kmh: float=0,start: Vector3=Vector3(-9,0,0),weaken: bool=false) -> void:
 contact_sensor.reset();sequence_active=false;sequence_notice=''
 crash_player=null;baked_consumed=false;baked_count=0;baked_steps=0
 baked_cpu_us=0;baked_search_cpu_us=0;baked_seconds=0;rigid_contact_count=0;driver_accumulator=0;last_bake={};bake_status='Ready'
 super.reset(speed_kmh,start,weaken)

func set_tire_friction(value: float) -> void:
 dynamics.parameters.tire_friction=clampf(value,.10,1.50)
 solver.wheels.friction_coefficient=dynamics.parameters.tire_friction

func set_engine_power_kw(value: float) -> void:
 var watts: float=clampf(value,55,660)*1000
 var factor: float=watts/float(profile.dynamics.power_w)
 dynamics.parameters.power_w=watts
 dynamics.parameters.drive_torque_nm=float(profile.dynamics.drive_torque_nm)*factor

func reset_wall_approach(speed_kmh: float=60,heading_deg: float=0) -> void:
 var start:=Vector3(solver.barrier_min.x-12,0,0)
 reset(speed_kmh,start)
 var frame:=Basis(Vector3.UP,deg_to_rad(heading_deg))
 for i in solver.points.size():solver.points[i]=frame*solver.rest[i]+start
 for wheel in solver.wheels.wheels:
  wheel.rotation=frame.get_rotation_quaternion();wheel.previous_rotation=wheel.rotation
  wheel.spin_speed=-speed_kmh/3.6*cos(deg_to_rad(heading_deg))/wheel.radius
 compact.capture_shape()

func _basic_eligibility() -> bool:
 if not baked_enabled or not driving or (bake_library.is_empty() and conditioned_library.is_empty()):return false
 if not solver.barrier_enabled or forecast.obstacle_velocity.length()>.01:return false
 if solver.wake_requested!='':return false
 if absf(velocity().y)>2.5:return false
 var supported:=false
 for wheel in solver.wheels.wheels:
  if wheel.detached:continue
  var p: Vector3=solver.points[wheel.node]
  if p.y+solver.wheels.support(wheel,Vector3.DOWN).y-solver.floor_sample(p).w<.12:supported=true
 if not supported:return false
 var lateral: Vector3=(solver.points[5]-solver.points[4]).normalized()
 if absf(lateral.cross(forward()).normalized().y)<.94:return false
 for i in [0,12,24]:
  if absf(solver.floor_sample(solver.points[i]).w)>.03:return false
 return true

func _is_pristine() -> bool:
 if baked_count>0 or solver.links.any(func(link):return link.broken or link.damage>.03):return false
 for pane in solver.effects.glass.panes.values():
  if pane.stage>0:return false
 var interior: Dictionary=solver.effects.interior.irreversible_state()
 if interior.airbag_deployed:return false
 for seat in interior.seats:
  if absf(float(seat.plastic_angle))>.0001:return false
 return true

func start_baked_sequence() -> bool:
 if bake_library.is_empty() or conditioned_library.size()<3:
  sequence_notice='Conditioned bank has not been generated yet';return false
 baked_enabled=true
 reset_wall_approach(60,0)
 sequence_active=true;sequence_notice='Staged 60 → 60 → 120 km/h sequence'
 return true

func stage_next_supported() -> bool:
 var next: Dictionary=States.next_supported(solver,conditioned_library)
 if not next.accepted:
  sequence_notice='No transition matches this damaged state';return false
 var clock_before: float=solver.simulated_time
 ConditionedAuthor.prepare(solver,{'speed':next.speed,'angle':next.angle})
 solver.simulated_time=clock_before
 compact.capture_shape();solver.compact_active=true;mode='DRIVE'
 contact_sensor.reset();driver_accumulator=0
 return true

func _choose_speed_bin(signature: Dictionary) -> Dictionary:
 if signature.is_empty():return {'accepted':false}
 if not _is_pristine():
  var transition: Dictionary=States.choose(solver,signature,conditioned_library)
  if transition.accepted:transition['library_kind']='conditioned'
  return transition
 var speed: float=float(signature.closing_speed_mps)*3.6
 if speed<35 or speed>175:return {'accepted':false}
 var normal:=Vector3(signature.world_normal[0],signature.world_normal[1],signature.world_normal[2])
 var motion: Vector3=velocity()
 if (motion-normal*motion.dot(normal)).length()>maxf(4.0,float(signature.closing_speed_mps)*.65):return {'accepted':false}
 var nearest_speed:=0.0;var distance:=INF
 for clip in bake_library:
  var difference: float=absf(float(clip.metadata.speed_kmh)-speed)
  if difference<distance:distance=difference;nearest_speed=float(clip.metadata.speed_kmh)
 # The demo has discrete severity bins. Select speed first, then compare zones
 # and local normal within that bin. Do not mislabel this as severity interpolation.
 var normalized: Dictionary=signature.duplicate(true)
 normalized.incident_impulse_proxy_ns*=nearest_speed/speed
 var subset: Array=[];var indices: Array=[]
 for i in bake_library.size():
  if float(bake_library[i].metadata.speed_kmh)==nearest_speed:
   subset.append(bake_library[i]);indices.append(i)
 var result: Dictionary=impact_grid.choose(normalized,subset)
 if result.accepted:
  result.index=indices[int(result.index)]
  result['actual_impact_kmh']=speed;result['recorded_speed_kmh']=nearest_speed
  result['impulse_ratio']=speed/nearest_speed
 return result

func _contact_event(horizon: float) -> Dictionary:
 var motion: Vector3=velocity()
 if not contact_sensor.nearby(solver,motion):
  contact_sensor.cancel('clear_road');return {}
 if not _basic_eligibility():
  contact_sensor.cancel('state_or_pose_unsupported');return {}
 var packet: Dictionary=contact_sensor.event(solver,motion,horizon)
 if packet.is_empty():return {}
 var candidates: Array=[{'band_m':.025,'signature':packet.signature}]
 candidates.append_array(packet.fallback_signatures)
 var representative: Dictionary={}
 for candidate in candidates:
  if not candidate.signature.is_empty():representative=candidate.signature;break
 if representative.is_empty():contact_sensor.note_rejection('empty_contact');return {}
 var normal:=Vector3(representative.world_normal[0],representative.world_normal[1],representative.world_normal[2])
 if absf(normal.x)<.99:contact_sensor.note_rejection('wall_end_or_corner');return {}
 if packet.bounds_min.z<solver.barrier_min.z+.1 or packet.bounds_max.z>solver.barrier_max.z-.1:
  contact_sensor.note_rejection('no_partial_wall_recording');return {}
 if packet.bounds_max.y>solver.barrier_max.y:
  contact_sensor.note_rejection('no_short_wall_recording');return {}
 for candidate in candidates:
  var signature: Dictionary=candidate.signature
  if signature.is_empty():continue
  var selection: Dictionary=_choose_speed_bin(signature)
  if selection.get('accepted',false):
   selection['classification_band_m']=candidate.band_m
   return {'toi':packet.toi,'signature':signature,'selection':selection}
 contact_sensor.note_rejection('no_compatible_recording')
 return {}

func _wake(reason: String) -> void:
 if baked_enabled:return
 super._wake(reason)

func _rigid_body_contacts(dt: float) -> void:
 # The frozen/deformed body is one rigid aggregate. Only these cheap contact
 # projections run; the 187 structural constraints are never evaluated here.
 var nearby_wall: bool=solver.barrier_enabled and float(solver.barrier_distance(compact.center).distance)<3.5
 for iteration in 3:
  for index in compact.indices:
   var p: Vector3=compact.point(index)
   var floor_: Vector4=solver.floor_sample(p)
   var depth: float=solver.radii[index]-(p.y-floor_.w)
   if depth>0:
    _rigid_contact(index,Vector3(floor_.x,floor_.y,floor_.z).normalized(),depth,dt)
    solver.contact_floor[index]=1
   if nearby_wall:
    var hit: Dictionary=solver.barrier_distance(compact.point(index))
    depth=solver.radii[index]-float(hit.distance)
    if depth>0:
     _rigid_contact(index,hit.normal,depth,dt)
     solver.contact_wall[index]=1
 compact.flush()

func _rigid_contact(index: int,normal: Vector3,depth: float,_dt: float) -> void:
 rigid_contact_count+=1
 var weight: float=compact.constraint_weight(index,-1,normal,Vector3.ZERO)
 if weight<1e-9:return
 compact.correct(index,-1,normal,Vector3.ZERO,depth/weight)
 var inward: float=compact.point_velocity(index).dot(normal)
 if inward>=0:return
 var impulse: float=-inward/weight
 compact.correct(index,-1,normal,Vector3.ZERO,impulse,true)
 var motion: Vector3=compact.point_velocity(index)
 var tangent: Vector3=motion-normal*motion.dot(normal)
 if tangent.length()>.0001:
  var direction: Vector3=tangent.normalized()
  var friction_weight: float=compact.constraint_weight(index,-1,direction,Vector3.ZERO)
  compact.correct(index,-1,-direction,Vector3.ZERO,minf(tangent.length()/friction_weight,.7*impulse),true)

func _advance_lightweight(h: float) -> void:
 var began: int=Time.get_ticks_usec()
 if mode=='SLEEP' and absf(dynamics.throttle)+absf(dynamics.steering)<.001 and solver.wake_requested=='' and sleeping_box_min==solver.barrier_min and sleeping_box_max==solver.barrier_max:
  solver.simulated_time+=h;sleep_steps+=1;sleep_seconds+=h
  solver.effects.step_debris(h)
  sleep_cpu_us+=Time.get_ticks_usec()-began
  return
 if mode!='DRIVE':
  var previous: String=mode
  compact.capture_shape();solver.compact_active=true;mode='DRIVE'
  transitions.append({'from':previous,'to':mode,'reason':'baked_mode_rigid_driving','time_s':solver.simulated_time})
 solver.wake_requested='';solver.wake_hold_seconds=0
 before_step.emit(h)
 dynamics.step(h)
 compact.step(h)
 _rigid_body_contacts(h)
 solver.effects.step_debris(h)
 drive_steps+=1;drive_seconds+=h
 _try_sleep_drive(h)
 drive_cpu_us+=Time.get_ticks_usec()-began

func _begin_bake(event: Dictionary) -> void:
 var travel: float=event.toi
 solver.compact_active=false
 for i in solver.points.size():solver.points[i]+=solver.velocities[i]*travel
 for wheel in solver.wheels.wheels:
  wheel.spin=wrapf(wheel.spin+wheel.spin_speed*travel,-PI,PI)
  var angle: float=wheel.angular_velocity.length()*travel
  if angle>1e-9:wheel.rotation=(Quaternion(wheel.angular_velocity.normalized(),angle)*wheel.rotation).normalized()
 solver.simulated_time+=travel
 drive_seconds+=travel
 bake_start_clock=solver.simulated_time;bake_clock=bake_start_clock
 bake_start_full_steps=solver.step_count;bake_end_full_steps=bake_start_full_steps
 baked_consumed=true;baked_count+=1
 crash_player=CrashPlayer.new()
 var selected_library: Array=conditioned_library if event.selection.get('library_kind','')=='conditioned' else bake_library
 crash_player.attach_live(self,selected_library,event.signature,event.selection)
 var previous: String=mode
 mode='BAKED';bake_status='Playing'
 solver.impact_started=true;solver.impact_time=bake_start_clock
 last_bake=event.selection.duplicate(true)
 last_bake.erase('candidates')
 last_bake['start_time_s']=bake_start_clock
 last_bake['handoff_position_jump_m']=crash_player.handoff_position_jump_m
 last_bake['handoff_velocity_jump_mps']=crash_player.handoff_velocity_jump_mps
 transitions.append({'from':previous,'to':mode,'reason':'matching_baked_impact','time_s':bake_start_clock,'clip':last_bake.id})

func _advance_bake(dt: float) -> void:
 var began: int=Time.get_ticks_usec()
 crash_player.advance(dt)
 bake_clock+=dt
 solver.simulated_time=bake_clock
 baked_steps+=1;baked_seconds+=dt
 baked_cpu_us+=Time.get_ticks_usec()-began
 if crash_player.state=='COMPLETE':_finish_bake()

func _finish_bake() -> void:
 bake_end_full_steps=solver.step_count
 last_bake['solver_steps_during_replay']=bake_end_full_steps-bake_start_full_steps
 last_bake['completed']=true
 # Clear pre-crash constraint accumulators; retain recorded damage and momentum.
 for link in solver.links:
  link.lambda=0;link.peak_force=0;link.overload_time=0
  link.plastic=absf(link.length-link.original)
 for wheel in solver.wheels.wheels:
  wheel.previous_rotation=wheel.rotation;wheel.lateral_lambda=0
  wheel.lateral_overload=0;wheel.joint_overload=0;wheel.joint_impulse=Vector3.ZERO
  wheel.contact_lambdas.fill(0);wheel.body_lambdas.fill(0)
 solver.old_points=solver.points.duplicate()
 solver.contact_wall.fill(0);solver.contact_floor.fill(0)
 dynamics.steering_angle=0
 compact.capture_shape()
 bake_status='Complete — rigid damaged car' if baked_enabled else 'Complete — live damaged car'
 if baked_enabled:
  solver.compact_active=true;compact.flush();mode='DRIVE'
  transitions.append({'from':'BAKED','to':mode,'reason':'baked_playback_complete_rigid','time_s':solver.simulated_time})
 else:super._wake('baked_playback_complete')
 crash_player=null
 if sequence_active:
  if baked_count>=3:sequence_active=false;sequence_notice='Three impacts complete; damage retained'
  elif not stage_next_supported():sequence_active=false

func advance(elapsed: float,time_scale: float=1.0) -> void:
 if crash_player==null and not baked_enabled:
  super.advance(elapsed+driver_accumulator/maxf(.0001,time_scale),time_scale)
  driver_accumulator=0
  return
 driver_accumulator+=elapsed*time_scale
 while true:
  var h: float=coarse_step
  if driver_accumulator+1e-10<h:break
  if crash_player!=null:
   _advance_bake(h)
  else:
   var began: int=Time.get_ticks_usec()
   var event: Dictionary=_contact_event(h)
   baked_search_cpu_us+=Time.get_ticks_usec()-began
   if event.is_empty():_advance_lightweight(h)
   else:
    _begin_bake(event)
    _advance_bake(maxf(0,h-float(event.toi)))
  driver_accumulator=maxf(0,driver_accumulator-h)

func statistics() -> Dictionary:
 var result: Dictionary=super.statistics()
 result['baked_count']=baked_count;result['baked_steps']=baked_steps
 result['baked_cpu_ms']=baked_cpu_us/1000.0;result['bake_search_cpu_ms']=baked_search_cpu_us/1000.0
 result['last_bake']=last_bake.duplicate(true)
 result['contact_sensor']=contact_sensor.statistics()
 result['rigid_contacts']=rigid_contact_count;result['baked_seconds']=baked_seconds
 result.total_cpu_ms+=float(baked_cpu_us+baked_search_cpu_us)/1000
 result.cpu_ms_per_sim_second=result.total_cpu_ms/maxf(.001,drive_seconds+full_seconds+sleep_seconds+baked_seconds)
 return result
