extends RefCounted
const Drive=preload('res://probes/panels/drive_runtime.gd')
const Attachment=preload('res://scripts/car_attachment.gd')
var drive: RefCounted
var speed_kmh:=60.0
var heading_deg:=0.0
var contact_speed_kmh:=-1.0
var contact_normal_kmh:=-1.0
var contact_time:=-1.0
var complete:=false
var from_rest:=false
var open_right:=false
var side_post:=false
var records: Array=[]
var history: Array=[]
var maximum_mass_error:=0.0
var finite:=true
var max_energy:=0.0
var impact_pose: Dictionary={}
func start(speed_: float=60,heading_: float=0,opening: bool=false,throttle_start: bool=false,post: bool=false) -> void:
 speed_kmh=speed_;heading_deg=heading_;from_rest=throttle_start;open_right=opening;side_post=post
 drive=Drive.new();drive.start('closed')
 if post:drive.graph.barrier_min.z=-2.8;drive.graph.barrier_max.z=-1.15
 if not from_rest:
  var g: RefCounted=drive.graph
  var frame:=Basis(Vector3.UP,deg_to_rad(heading_deg));var location:=Vector3(g.barrier_min.x-6,0,6*tan(deg_to_rad(heading_deg)) if post else 0)
  for i in g.points.size():g.points[i]=frame*g.rest[i]+location;g.velocities[i]=frame*Vector3(speed_/3.6,0,0)
  for wheel in g.wheels.wheels:wheel.rotation=frame.get_rotation_quaternion();wheel.previous_rotation=wheel.rotation;wheel.angular_velocity=Vector3.ZERO;wheel.spin_speed=-speed_/3.6/wheel.radius
  drive.compact.capture_shape();g.panels.synchronize_inactive()
 if open_right:
  # Real bounded opening actuator. Settle before staging the launch, then preserve
  # its angle/shape while assigning the car's approach velocity as one rigid field.
  var wall_before: bool=drive.graph.barrier_enabled;drive.graph.barrier_enabled=false
  var velocity: Vector3=drive.compact.linear_velocity
  for i in drive.graph.velocities.size():drive.graph.velocities[i]=Vector3.ZERO
  drive.compact.capture_shape();drive.reduced.set_open('door_right',65)
  for i in 420:drive.controls(0,1,0);drive.step()
  drive.graph.barrier_enabled=wall_before
  var p: Dictionary=drive.graph.panels.find('door_right')
  drive.compact.linear_velocity=velocity;drive.compact.angular_velocity=Vector3.ZERO;drive.compact.flush()
  p.reduced_data.linear=velocity;p.reduced_data.omega=Vector3.ZERO;drive.reduced._publish(p)
  for wheel in drive.graph.wheels.wheels:drive.graph.velocities[wheel.node]=velocity;wheel.spin_speed=-speed_/3.6/wheel.radius
  drive.graph.simulated_time=0;drive.graph.panels.clock=0;drive.graph.panels.events.clear()
  drive.full_steps=0;drive.coarse_steps=0;drive.graph.panels.active_steps=0;drive.sample_costs.clear();drive.time=0
 records=[drive.capture()];history=[snapshot('initial')]
func snapshot(kind: String='sample') -> Dictionary:
 var parts: Array=[]
 for p in drive.graph.panels.panels:
  var edge_change:=0.0
  for edge in p.edges:edge_change=maxf(edge_change,absf(edge.length-edge.original))
  parts.append({'id':p.id,'profile':p.get('profile_id',''),'weak_reference':p.get('weak_mount_reference',''),'hinge_n':p.hinge_strength_n,'latch_n':p.latch_strength_n,'closing':drive.graph.panels.closing_topology(p),'detached':p.detached,'anchors':p.anchors.map(func(a):return {'broken':a.broken,'peak_n':a.get('maximum_n',0),'step_peak_n':a.peak_n,'exposure_s':a.exposure,'blocked_peak_n':a.get('blocked_peak_n',0)}),'seats':p.get('closing_supports',[]).map(func(s):return {'broken':s.broken,'peak_n':s.maximum_n}),'local':p.get('impact_evidence',{}).duplicate(true),'angular_mount':p.get('angular_mount',{}).duplicate(true),'plastic_j':p.plastic_work,'plastic_m':edge_change,'mode':p.get('reduced_mode',''),'contacts':p.contacts})
 return {'kind':kind,'time_s':drive.time,'full_remaining_s':drive.full_remaining,'speed_kmh':drive.speed,'parts':parts}
func step() -> void:
 if complete:return
 var old_velocity: Vector3=drive.dynamics.body_velocity();var old_events: int=drive.graph.panels.events.size();var old_full: bool=drive.full_remaining>0
 drive.controls(1 if from_rest else 0,0,0);drive.step()
 if drive.graph.impact_started and contact_time<0:
  contact_time=drive.time;contact_speed_kmh=old_velocity.length()*3.6;contact_normal_kmh=old_velocity.x*3.6
  history.append(snapshot('first_contact'))
 if old_full!=(drive.full_remaining>0) or old_events!=drive.graph.panels.events.size():history.append(snapshot('handoff_or_failure'))
 if drive.ticks%4==0 and drive.full_remaining>0:history.append(snapshot())
 if drive.ticks%2==0:records.append(drive.capture())
 maximum_mass_error=maxf(maximum_mass_error,absf(drive.graph.panels.total_mass()-1210))
 for p in drive.graph.panels.panels:
  for point_ in p.points:finite=finite and point_.is_finite() and point_.length()<500
 if contact_time>=0 and drive.time>contact_time+1.0 and drive.full_remaining<=0:complete=true
 if drive.time>8:complete=true
func result() -> Dictionary:
 return {'requested_speed_kmh':speed_kmh,'heading_deg':heading_deg,'open_right':open_right,'side_post':side_post,'from_rest':from_rest,'actual_contact_kmh':contact_speed_kmh,'actual_normal_contact_kmh':contact_normal_kmh,'contact_time_s':contact_time,'finite':finite,'mass_error_kg':maximum_mass_error,'final':snapshot('final'),'events':drive.graph.panels.events.duplicate(true),'stats':drive.stats(),'history':history}
