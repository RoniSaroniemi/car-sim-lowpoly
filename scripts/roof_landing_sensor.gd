extends RefCounted
## Contact-time selector for the bounded moving roof/floor recipe. No solves.
const Geometry=preload('res://scripts/roof_landing_geometry.gd')
const Grid=preload('res://scripts/impact_zone_grid.gd')
var last_rejection: String=''
var checks:=0
var probe_queries:=0
func reset() -> void:last_rejection='';checks=0;probe_queries=0
func reject(reason: String) -> Dictionary:last_rejection=reason;return {}
func event(vehicle: RefCounted,horizon: float,library: Array) -> Dictionary:
 checks+=1
 var g: RefCounted=vehicle.solver;var frame:=Geometry.basis(g)
 if vehicle.baked_count>0 or -frame.y.y<cos(deg_to_rad(26)):
  last_rejection='';return {}
 if library.is_empty():return reject('roof_recordings_missing')
 if not vehicle._is_pristine():return reject('roof_damage_history_not_recorded')
 if absf(frame.x.y)>sin(deg_to_rad(8)):return reject('roof_pitch_outside_slice')
 var center: Vector3=g.station_center(2)
 var surface: Vector4=g.floor_sample(center)
 if center.y-surface.w>2.5:return {}
 var motion: Vector3=vehicle.compact.linear_velocity
 var omega: Vector3=vehicle.compact.angular_velocity
 var forward: float=motion.dot(frame.x)
 if forward<10.8 or forward>22.5:return reject('roof_forward_speed_outside_slice')
 var ground_side:=Vector3(-frame.x.z,0,frame.x.x).normalized()
 if absf(motion.dot(ground_side))>2:return reject('roof_sideways_speed_outside_slice')
 if absf(omega.dot(frame.x))>.75 or absf(omega.dot(frame.y))>.25 or absf(omega.dot(frame.z))>.25:return reject('roof_rotation_outside_slice')
 g.panels.synchronize_inactive()
 var probes: Array=Geometry.probes(g);probe_queries+=1
 var toi:=INF;var gravity: float=g.config.gravity_mps2
 for p in probes:
  var future: Vector3=p.position+p.velocity*horizon
  var floor_: Vector4=g.floor_sample(future)
  if floor_.y<.999 or absf(floor_.w-surface.w)>.015:return reject('roof_requires_flat_ground')
  var gap: float=p.position.y-p.radius-floor_.w
  if gap<-.025:return reject('roof_started_inside_ground')
  var vy: float=p.velocity.y
  if gap<=1e-7:
   if vy<-.1:toi=0
   continue
  var t: float=2*gap/(sqrt(vy*vy+4*gravity*gap)-vy) if gravity>.000001 else (-gap/vy if vy<0 else INF)
  if t>=0 and t<=horizon:toi=minf(toi,t)
 if not is_finite(toi):return {}
 var signature: Dictionary=Geometry.signature(g,toi)
 if signature.is_empty():return reject('roof_no_incoming_contact')
 var speed: float=signature.closing_speed_mps
 var best: Dictionary={};var best_score:=-INF
 var normal:=Vector3(signature.normal[0],signature.normal[1],signature.normal[2])
 var grid:=Grid.new()
 for index in library.size():
  var clip: Dictionary=library[index]
  if not clip.get('_input_compatibility',{}).get('compatible',false):continue
  if clip.metadata.get('material_profile','')!=g.config.get('material_profile',''):continue
  if absf(float(clip.metadata.initial_mass_kg)-float(g.config.mass_kg))>.01 or clip.frames[0].points.size()!=g.points.size():continue
  var spec: Dictionary=clip.metadata.landing_spec
  var expected: Dictionary=clip.metadata.signature
  var n:=Vector3(expected.normal[0],expected.normal[1],expected.normal[2])
  var angle: float=rad_to_deg(acos(clampf(n.dot(normal),-1,1)))
  var ratio: float=speed/float(expected.closing_speed_mps)
  if angle>10 or ratio<.65 or ratio>1.35:continue
  var normalized: Dictionary=signature.duplicate(true)
  normalized.incident_impulse_proxy_ns=expected.incident_impulse_proxy_ns
  var matched: Dictionary=grid.match_signature(normalized,expected)
  if not matched.accepted:continue
  var score: float=matched.score-.15*absf(log(ratio))-.1*absf(omega.dot(frame.x)-float(spec.roll_rate))
  if score<=best_score:continue
  best_score=score
  best={'accepted':true,'index':index,'id':clip.metadata.id,'library_kind':'roof_landing','contact_family':'roof_landing_floor','score':score,'zone_overlap':matched.zone_overlap,'angle_error_deg':angle,'closing_speed_mps':speed,'forward_speed_kmh':forward*3.6,'actual_impact_kmh':speed*3.6,'recorded_speed_kmh':float(expected.closing_speed_mps)*3.6,'impulse_ratio':ratio,'floor_y':surface.w}
 if best.is_empty():return reject('roof_no_matching_pose_or_speed')
 last_rejection=''
 return {'toi':toi,'signature':signature,'selection':best,'floor_contact':true}
