extends 'res://scripts/vehicle_simulation.gd'
## Driving adapter: unchanged live dynamics, with recorded ownership during compatible successive impacts.
const CrashPlayer=preload('res://scripts/baked_crash_player.gd')
const CrashClip=preload('res://scripts/baked_crash_clip.gd')
const ImpactGrid=preload('res://scripts/impact_zone_grid.gd')
const States=preload('res://scripts/conditioned_crash_transitions.gd')
const ConditionedAuthor=preload('res://scripts/conditioned_crash_authoring.gd')
const Coverage=preload('res://scripts/baked_contact_coverage.gd')
const Partials=preload('res://scripts/partial_crash_library.gd')
const ContactSensor=preload('res://scripts/baked_contact_sensor.gd')
const RoofLandingCases=preload('res://scripts/roof_landing_cases.gd')
const RoofLandingSensor=preload('res://scripts/roof_landing_sensor.gd')
const PanelFloorWake=preload('res://scripts/panel_floor_wake.gd')
const RoofStiffness=preload('res://scripts/roof_stiffness_tuning.gd')
var roof_stiffness: float=RoofStiffness.DEFAULT
const GroundImpact=preload('res://scripts/ground_impact_geometry.gd')
const IncrementalPlayer=preload('res://scripts/incremental_crash_player.gd')
const WorldSensor=preload('res://scripts/world_impact_sensor.gd')
var world_impact_sensor:=WorldSensor.new()
const RoofResponse=preload('res://scripts/roof_landing_response.gd')
static var cached_library: Array=[]
static var cached_conditioned: Array=[]
static var cached_roof_landings: Array=[]
var roof_landing_library: Array=[]
var roof_landing_sensor:=RoofLandingSensor.new()
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
var impact_history: Array=[]
var bake_status: String='Ready'

func setup(profile_path: String='res://vehicles/niva.json',enable_driving: bool=true) -> void:
 super.setup(profile_path,enable_driving)
 if cached_library.is_empty():cached_library=CrashClip.read_library()+Partials.read_library()
 bake_library=cached_library
 if cached_conditioned.is_empty():cached_conditioned=States.read_library()
 conditioned_library=cached_conditioned
 if cached_roof_landings.is_empty():cached_roof_landings=RoofLandingCases.read_library()
 roof_landing_library=cached_roof_landings
 for clip in bake_library+conditioned_library+roof_landing_library:
  if not clip.has('_input_compatibility'):clip['_input_compatibility']=CrashClip.input_compatibility(clip)
  CrashClip.prepare_surfaces(solver,clip)
 for clip in roof_landing_library:CrashClip.prepare_surfaces(solver,RoofResponse.prepare(solver,clip))
 for clip in bake_library+roof_landing_library:IncrementalPlayer.prepare(solver,clip)
 if not before_step.is_connected(_live_panel_floor_wake):before_step.connect(_live_panel_floor_wake)

func _live_panel_floor_wake(h: float) -> void:
 if not baked_enabled and mode=='FULL':
  RoofStiffness.apply_live(solver,roof_stiffness);PanelFloorWake.step(solver,h)

func stage_roof_landing(roll_deg: float=0,down_mps: float=4) -> void:
 var spec: Dictionary={'roll_deg':roll_deg,'forward_kmh':60.0,'down_mps':down_mps,'roll_rate':signf(roll_deg)*.35}
 var clearance: float=minf(.30,down_mps*down_mps/(4*float(solver.config.gravity_mps2)))
 RoofLandingCases.place(self,spec,clearance)
 baked_enabled=true;mode='DRIVE';solver.compact_active=true

func reset(speed_kmh: float=0,start: Vector3=Vector3(-9,0,0),weaken: bool=false) -> void:
 contact_sensor.reset();sequence_active=false;sequence_notice=''
 impact_history.clear()
 roof_landing_sensor.reset()
 world_impact_sensor.reset()
 crash_player=null;baked_consumed=false;baked_count=0;baked_steps=0
 baked_cpu_us=0;baked_search_cpu_us=0;baked_seconds=0;rigid_contact_count=0;driver_accumulator=0;last_bake={};bake_status='Ready'
 super.reset(speed_kmh,start,weaken)

func set_roof_stiffness(value: float) -> void:
 roof_stiffness=RoofStiffness.bounded(value)
 if not baked_enabled and mode=='FULL':RoofStiffness.apply_live(solver,roof_stiffness)

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
 if solver.panels_runtime_enabled and solver.panels.panels.any(func(p):return p.active or p.plastic_work>.01 or p.anchors.any(func(a):return a.broken)):return false
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
 prepare_lightweight_panels()
 compact.capture_shape();solver.compact_active=true;mode='DRIVE'
 contact_sensor.reset();driver_accumulator=0
 return true

func _choose_speed_bin(signature: Dictionary,coverage: Dictionary={}) -> Dictionary:
 if signature.is_empty():return {'accepted':false}
 if not _is_pristine():
  var pool: Array=[];var indices: Array=[]
  for i in conditioned_library.size():
   if conditioned_library[i]._input_compatibility.compatible:pool.append(conditioned_library[i]);indices.append(i)
  var transition: Dictionary=States.choose(solver,signature,pool)
  if transition.accepted:
   transition.index=indices[int(transition.index)]
   var recorded: Dictionary=conditioned_library[int(transition.index)].metadata.get('contact_coverage',{})
   if not coverage.is_empty() and not Coverage.compatible(coverage,recorded).accepted:return {'accepted':false,'reason':'no_conditioned_footprint_recording'}
   transition['library_kind']='conditioned'
  return transition
 if not coverage.is_empty():
  # Filter before severity binning: a stale clip must not select a speed bin
  # that hides a compatible recording at another speed.
  var pool: Array=[];var indices: Array=[]
  for i in bake_library.size():
   if bake_library[i]._input_compatibility.compatible:pool.append(bake_library[i]);indices.append(i)
  var selection: Dictionary=Coverage.choose(signature,coverage,pool,float(signature.closing_speed_mps)*3.6)
  if selection.get('accepted',false):selection.index=indices[int(selection.index)]
  return selection
 var speed: float=float(signature.closing_speed_mps)*3.6
 if speed<35 or speed>175:return {'accepted':false}
 var normal:=Vector3(signature.world_normal[0],signature.world_normal[1],signature.world_normal[2])
 var motion: Vector3=velocity()
 if (motion-normal*motion.dot(normal)).length()>maxf(4.0,float(signature.closing_speed_mps)*.65):return {'accepted':false}
 var nearest_speed:=0.0;var distance:=INF
 for clip in bake_library:
  if clip.metadata.has('contact_coverage'):continue
  if not clip._input_compatibility.compatible:continue
  var difference: float=absf(float(clip.metadata.speed_kmh)-speed)
  if difference<distance:distance=difference;nearest_speed=float(clip.metadata.speed_kmh)
 # The demo has discrete severity bins. Select speed first, then compare zones
 # and local normal within that bin. Do not mislabel this as severity interpolation.
 var normalized: Dictionary=signature.duplicate(true)
 normalized.incident_impulse_proxy_ns*=nearest_speed/speed
 var subset: Array=[];var indices: Array=[]
 for i in bake_library.size():
  if not bake_library[i].metadata.has('contact_coverage') and float(bake_library[i].metadata.speed_kmh)==nearest_speed and bake_library[i]._input_compatibility.compatible:
   subset.append(bake_library[i]);indices.append(i)
 var result: Dictionary=impact_grid.choose(normalized,subset)
 if result.accepted:
  result.index=indices[int(result.index)]
  result['actual_impact_kmh']=speed;result['recorded_speed_kmh']=nearest_speed
  result['impulse_ratio']=speed/nearest_speed
 return result

func _contact_event(horizon: float) -> Dictionary:
 var roof_event: Dictionary=roof_landing_sensor.event(self,horizon,roof_landing_library)
 if not roof_event.is_empty():return roof_event
 var motion: Vector3=velocity()
 if not contact_sensor.nearby(solver,motion):
  contact_sensor.cancel('clear_road');return world_impact_sensor.event(self,horizon,bake_library)
 if not _basic_eligibility():
  contact_sensor.cancel('state_or_pose_unsupported');return world_impact_sensor.event(self,horizon,bake_library)
 var packet: Dictionary=contact_sensor.event(solver,motion,horizon)
 if packet.is_empty():return world_impact_sensor.event(self,horizon,bake_library)
 var candidates: Array=[{'band_m':.025,'signature':packet.signature}]
 candidates.append_array(packet.fallback_signatures)
 var representative: Dictionary={}
 for candidate in candidates:
  if not candidate.signature.is_empty():representative=candidate.signature;break
 if representative.is_empty():contact_sensor.note_rejection('empty_contact');return world_impact_sensor.event(self,horizon,bake_library)
 var coverage: Dictionary=Coverage.describe(solver,packet,representative)
 var rejection: String='no_compatible_footprint_recording'
 for candidate in candidates:
  var signature: Dictionary=candidate.signature
  if signature.is_empty():continue
  coverage=Coverage.describe(solver,packet,signature)
  var selection: Dictionary=_choose_speed_bin(signature,coverage)
  if selection.get('accepted',false):
   selection['classification_band_m']=candidate.band_m
   selection['contact_coverage']=coverage
   return {'toi':packet.toi,'signature':signature,'selection':selection}
  rejection=selection.get('reason',rejection)
 contact_sensor.note_rejection(rejection)
 return world_impact_sensor.event(self,horizon,bake_library)

func _wake(reason: String) -> void:
 if baked_enabled:return
 super._wake(reason)

func _rigid_body_contacts(dt: float) -> void:
 # The frozen/deformed body is one rigid aggregate. Only these cheap contact
 # projections run; the 187 structural constraints are never evaluated here.
 var nearby_wall: bool=float(solver.static_contact(compact.center,3.5).distance)<3.5
 for iteration in 3:
  for index in compact.indices:
   var p: Vector3=compact.point(index)
   var floor_: Vector4=solver.floor_sample(p)
   var depth: float=solver.radii[index]-(p.y-floor_.w)
   if depth>0:
    _rigid_contact(index,Vector3(floor_.x,floor_.y,floor_.z).normalized(),depth,dt)
    solver.contact_floor[index]=1
   if nearby_wall:
    var hit: Dictionary=solver.static_contact(compact.point(index),solver.radii[index])
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
 if mode=='SLEEP' and compact.linear_velocity.length_squared()<.0025 and compact.angular_velocity.length_squared()<.0025 and not compact.external_change() and absf(dynamics.throttle)+absf(dynamics.steering)<.001 and solver.wake_requested=='' and sleeping_box_min==solver.barrier_min and sleeping_box_max==solver.barrier_max:
  solver.simulated_time+=h;sleep_steps+=1;sleep_seconds+=h
  step_reduced_panels(h)
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
 step_reduced_panels(h)
 solver.effects.step_debris(h)
 drive_steps+=1;drive_seconds+=h
 _try_sleep_drive(h)
 drive_cpu_us+=Time.get_ticks_usec()-began

func _begin_bake(event: Dictionary) -> void:
 var travel: float=event.toi
 if solver.panels_runtime_enabled:solver.panels.synchronize_inactive()
 solver.compact_active=false
 var rigid_contact: bool=event.get('rigid_contact',event.get('floor_contact',false))
 if rigid_contact:GroundImpact.advance(self,travel)
 for i in solver.points.size():
  if rigid_contact:continue
  solver.points[i]+=solver.velocities[i]*travel
 if solver.panels_runtime_enabled and not rigid_contact:
  for p in solver.panels.panels:
   for i in 10:p.points[i]+=p.velocity[i]*travel
   if p.has('reduced_data'):
    p.reduced_data.center+=p.reduced_data.linear*travel
    var omega: Vector3=p.reduced_data.omega;var angle: float=omega.length()*travel
    if angle>1e-9:p.reduced_data.rotation=(Quaternion(omega.normalized(),angle)*p.reduced_data.rotation).normalized()
  solver.panels.pose_revision+=1
  if event.get('floor_contact',false):solver.panels.synchronize_inactive()
 for wheel in solver.wheels.wheels:
  wheel.spin=wrapf(wheel.spin+wheel.spin_speed*travel,-PI,PI)
  var angle: float=wheel.angular_velocity.length()*travel
  if angle>1e-9 and not rigid_contact:wheel.rotation=(Quaternion(wheel.angular_velocity.normalized(),angle)*wheel.rotation).normalized()
 solver.simulated_time+=travel
 drive_seconds+=travel
 bake_start_clock=solver.simulated_time;bake_clock=bake_start_clock
 bake_start_full_steps=solver.step_count;bake_end_full_steps=bake_start_full_steps
 baked_consumed=true;baked_count+=1
 crash_player=IncrementalPlayer.new() if event.selection.get('incremental',false) else CrashPlayer.new()
 var contact_gap:=RoofLandingCases.Geometry.minimum_gap(solver) if event.get('floor_contact',false) else INF
 var selected_library: Array=conditioned_library if event.selection.get('library_kind','')=='conditioned' else bake_library
 if event.selection.get('library_kind','')=='roof_landing':selected_library=roof_landing_library
 crash_player.attach_live(self,selected_library,event.signature,event.selection)
 var previous: String=mode
 mode='BAKED';bake_status='Playing'
 solver.impact_started=true;solver.impact_time=bake_start_clock
 last_bake=event.selection.duplicate(true)
 if event.selection.get('contact_family','')=='roof_landing_floor':world_impact_sensor.latches['terrain_body']=true
 if event.get('floor_contact',false):last_bake['contact_gap_m']=contact_gap
 last_bake.erase('candidates')
 last_bake['start_time_s']=bake_start_clock
 last_bake['handoff_position_jump_m']=crash_player.handoff_position_jump_m
 last_bake['handoff_velocity_jump_mps']=crash_player.handoff_velocity_jump_mps
 impact_history.append(last_bake.duplicate(true))
 transitions.append({'from':previous,'to':mode,'reason':'matching_baked_impact','time_s':bake_start_clock,'clip':last_bake.id})

func _advance_bake(dt: float) -> void:
 var began: int=Time.get_ticks_usec()
 crash_player.advance(dt)
 bake_clock+=dt
 solver.simulated_time=bake_clock
 baked_steps+=1;baked_seconds+=dt
 baked_cpu_us+=Time.get_ticks_usec()-began
 if crash_player.state=='COMPLETE':_finish_bake()

func _advance_incremental_root(h: float) -> void:
 before_step.emit(h)
 dynamics.step(h);compact.step(h);_rigid_body_contacts(h)
 step_reduced_panels(h);solver.effects.step_debris(h)

func _fit_incremental_contacts() -> void:
 # The render/panel roof can extend past the sparse structural spheres. Keep
 # those same contact proxies outside terrain after an incremental shape edit.
 for iteration in 4:
  solver.panels.synchronize_inactive()
  var deepest:=0.0;var normal:=Vector3.ZERO
  for p in RoofLandingCases.Geometry.probes(solver):
   if p.source=='wheel':continue
   var floor_hit: Dictionary=GroundImpact.gap(solver,p.position,p.radius)
   if floor_hit.distance<deepest:deepest=floor_hit.distance;normal=floor_hit.normal
   var hit: Dictionary=solver.static_contact(p.position,p.radius)
   var gap: float=float(hit.distance)-p.radius
   if gap<deepest:deepest=gap;normal=hit.normal
  if deepest>=-.001:break
  compact.center+=normal*(-deepest+.0001)
  var inward: float=compact.linear_velocity.dot(normal)
  if inward<0:compact.linear_velocity-=normal*inward
  compact.flush()
 solver.panels.synchronize_inactive()
 # Shape changes and finite wheel rotation can leave a small nonlinear contact
 # remainder after the normal suspension iterations. Preserve tire compliance,
 # but keep the existing wheel mass/hard rim above the same world surfaces.
 for wheel in solver.wheels.wheels:
  var position: Vector3=solver.points[wheel.node]
  var floor_hit: Vector4=solver.floor_sample(position)
  var normal:=Vector3(floor_hit.x,floor_hit.y,floor_hit.z).normalized()
  var support: Vector3=solver.wheels.support(wheel,-normal)
  var distance: float=(position.y-floor_hit.w)*normal.y+support.dot(normal)
  var excess: float=-float(wheel.max_compression)-distance
  if excess>.001:
   solver.points[wheel.node]+=normal*excess
   var inward: float=solver.velocities[wheel.node].dot(normal)
   if inward<0:solver.velocities[wheel.node]-=normal*inward

func _finish_bake() -> void:
 prepare_lightweight_panels()
 bake_end_full_steps=solver.step_count
 last_bake['solver_steps_during_replay']=bake_end_full_steps-bake_start_full_steps
 last_bake['completed']=true
 for item in impact_history:
  if item.get('start_time_s',-1)==last_bake.start_time_s:item.merge(last_bake,true)
  if item.get('overlay',false) and item.get('parent_id','')==last_bake.id and not item.get('completed',false):
   item['completed']=true;item['solver_steps_during_replay']=bake_end_full_steps-bake_start_full_steps
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
 result['roof_stiffness']=roof_stiffness
 result['baked_count']=baked_count;result['baked_steps']=baked_steps
 result['baked_cpu_ms']=baked_cpu_us/1000.0;result['bake_search_cpu_ms']=baked_search_cpu_us/1000.0
 result['last_bake']=last_bake.duplicate(true)
 result['impact_history']=impact_history.duplicate(true)
 result['contact_sensor']=contact_sensor.statistics()
 result['rigid_contacts']=rigid_contact_count;result['baked_seconds']=baked_seconds
 result.total_cpu_ms+=float(baked_cpu_us+baked_search_cpu_us)/1000
 result.cpu_ms_per_sim_second=result.total_cpu_ms/maxf(.001,drive_seconds+full_seconds+sleep_seconds+baked_seconds)
 return result
