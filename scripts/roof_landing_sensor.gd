extends RefCounted
## Contact-time selector for the bounded moving roof/floor recipe. No solves.
const Geometry=preload('res://scripts/roof_landing_geometry.gd')
const Ground=preload('res://scripts/ground_impact_geometry.gd')
const Response=preload('res://scripts/roof_landing_response.gd')
const Grid=preload('res://scripts/impact_zone_grid.gd')
var last_rejection: String=''
var checks:=0
var probe_queries:=0
func reset() -> void:last_rejection='';checks=0;probe_queries=0
func reject(reason: String) -> Dictionary:last_rejection=reason;return {}
func event(vehicle: RefCounted,horizon: float,library: Array) -> Dictionary:
 checks+=1
 var g: RefCounted=vehicle.solver;var frame:=Geometry.basis(g)
 if vehicle.baked_count>0:
  last_rejection='';return {}
 var center: Vector3=g.station_center(2)
 var surface: Vector4=g.floor_sample(center)
 var reference_normal:=Vector3(surface.x,surface.y,surface.z).normalized()
 if -frame.y.dot(reference_normal)<.05:
  last_rejection='';return {}
 if center.y-surface.w>3:return {}
 if library.is_empty():return reject('roof_recordings_missing')
 if not vehicle._is_pristine():return reject('roof_damage_history_not_recorded')
 var motion: Vector3=vehicle.compact.linear_velocity
 var omega: Vector3=vehicle.compact.angular_velocity
 if motion.length()>75 or omega.length()>16:return reject('roof_speed_outside_slice')
 var packet: Dictionary=Ground.packet(vehicle,horizon)
 if packet.is_empty():return {}
 probe_queries+=1
 var signature: Dictionary=packet.signature
 var speed: float=signature.closing_speed_mps
 var normal_world: Vector3=packet.ground_normal
 if -frame.y.dot(normal_world)<.05:return reject('ground_contact_not_roof_side')
 if signature.first_contacts.all(func(hit):return hit.source=='wheel'):return reject('roof_wheels_first')
 var forward: float=motion.dot(frame.x)
 # Static load is sufficient in the intentionally weak-roof game profile.
 if speed<.01 and packet.toi>0:return {}
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
  var damage_speed: float=clampf(speed,4.0,7.0)
  var ratio: float=damage_speed/float(expected.closing_speed_mps)
  if angle>86:continue
  var normalized: Dictionary=signature.duplicate(true)
  normalized.incident_impulse_proxy_ns=expected.incident_impulse_proxy_ns
  var matched: Dictionary=grid.match_signature(normalized,expected)
  var score: float=.60*exp(-.5*pow(angle/35.0,2))+.20*float(matched.get('zone_overlap',0))+.20*exp(-absf(log(ratio)))
  if score<=best_score:continue
  best_score=score
  best={'accepted':true,'index':index,'id':clip.metadata.id,'library_kind':'roof_landing','contact_family':'roof_landing_floor','score':score,'zone_overlap':matched.zone_overlap,'angle_error_deg':angle,'closing_speed_mps':speed,'forward_speed_kmh':forward*3.6,'actual_impact_kmh':speed*3.6,'recorded_speed_kmh':float(expected.closing_speed_mps)*3.6,'impulse_ratio':ratio,'floor_y':surface.w,'ground_normal':[normal_world.x,normal_world.y,normal_world.z],'ground_point':[packet.ground_point.x,packet.ground_point.y,packet.ground_point.z],'roof_damage_gain':Response.GAIN,'activation_threshold_mps':.01}
 if best.is_empty():return reject('roof_no_matching_pose_or_speed')
 last_rejection=''
 packet['selection']=best
 return packet
