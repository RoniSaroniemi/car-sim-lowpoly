extends 'res://tools/probes/baked_trigger_investigation/baseline_driving_vehicle.gd'
var events: Array=[]
var forecast_events: Dictionary={}
var detector_cpu_us:=0
var candidates_ranked:=0

func basic_reason() -> String:
 if not baked_enabled:return 'baked_disabled'
 if not driving:return 'not_driving'
 if baked_consumed:return 'already_baked'
 if bake_library.is_empty():return 'empty_library'
 if not solver.barrier_enabled:return 'barrier_disabled'
 if forecast.obstacle_velocity.length()>.01:return 'moving_barrier'
 if solver.wake_requested!='':return 'wake_requested'
 if solver.links.any(func(link):return link.broken or link.damage>.03):return 'preexisting_link_damage'
 if absf(velocity().y)>2.5:return 'vertical_velocity'
 var supported:=false
 for wheel in solver.wheels.wheels:
  var p: Vector3=solver.points[wheel.node]
  if p.y+solver.wheels.support(wheel,Vector3.DOWN).y-solver.floor_sample(p).w<.12:supported=true
 if not supported:return 'airborne'
 var lateral: Vector3=(solver.points[5]-solver.points[4]).normalized()
 if absf(lateral.cross(forward()).normalized().y)<.94:return 'tilt'
 for index in [0,12,24]:
  if absf(solver.floor_sample(solver.points[index]).w)>.03:return 'nonflat_terrain'
 return ''

func nodal_toi(horizon: float) -> float:
 var earliest:=INF
 for i in solver.points.size():
  var radius: float=solver.radii[i]
  var a: Vector3=solver.barrier_min-Vector3.ONE*radius
  var b: Vector3=solver.barrier_max+Vector3.ONE*radius
  var entry:=0.0;var exit:=horizon;var hit:=true
  var motion: Vector3=solver.velocities[i]
  for axis in 3:
   if absf(motion[axis])<1e-7:
    if solver.points[i][axis]<a[axis] or solver.points[i][axis]>b[axis]:hit=false
   else:
    var t0: float=(a[axis]-solver.points[i][axis])/motion[axis]
    var t1: float=(b[axis]-solver.points[i][axis])/motion[axis]
    entry=maxf(entry,minf(t0,t1));exit=minf(exit,maxf(t0,t1))
   if entry>exit:hit=false
  if hit and exit>=0 and entry<=horizon:earliest=minf(earliest,maxf(0,entry))
 return earliest

func band_signature(motion: Vector3,band: float) -> Dictionary:
 var masses:=PackedFloat32Array();masses.resize(45)
 var total:=0.0;var normal:=Vector3.ZERO
 for index in solver.points.size():
  var hit: Dictionary=solver.barrier_distance(solver.points[index])
  if float(hit.distance)-solver.radii[index]>band or motion.dot(hit.normal)>=-.1:continue
  var id: int=impact_grid.zone(solver.rest[index]-(impact_grid.body_basis(solver).transposed()*hit.normal)*solver.radii[index])
  masses[id]+=solver.masses[index];total+=solver.masses[index];normal+=hit.normal
 if total==0:return {}
 normal=normal.normalized()
 var local: Vector3=impact_grid.body_basis(solver).transposed()*normal
 var speed: float=maxf(0,-motion.dot(normal))
 var zones: Array=[]
 for id in 45:
  if masses[id]>0:zones.append({'id':id,'weight':masses[id]/total})
 return {'zones':zones,'normal':[local.x,local.y,local.z],'world_normal':[normal.x,normal.y,normal.z],'closing_speed_mps':speed,'incident_impulse_proxy_ns':speed*solver.config.mass_kg}

func diagnose(horizon: float,nodal: bool=false) -> Dictionary:
 var motion: Vector3=velocity()
 var center: Vector3=solver.station_center(2)
 var result: Dictionary={'time_s':solver.simulated_time,'horizon_s':horizon,'nodal':nodal,'reason':'remote','possible':false,'accepted':false,'body_heading_deg':rad_to_deg(atan2(-forward().z,forward().x)),'speed_kmh':motion.length()*3.6,'center':[center.x,center.y,center.z]}
 if float(solver.barrier_distance(center).distance)>3.5+motion.length()*horizon:return result
 var toi: float=nodal_toi(horizon) if nodal else impact_grid.time_to_contact(solver,motion,horizon)
 if not is_finite(toi):result.reason='no_swept_contact';return result
 result.possible=true;result['toi_s']=toi
 var before: PackedVector3Array=solver.points.duplicate()
 for i in solver.points.size():solver.points[i]+=solver.velocities[i]*toi
 var signature: Dictionary=impact_grid.signature(solver,motion)
 var wide_signatures: Dictionary={}
 for band in [.050,.100]:wide_signatures[str(band)]=band_signature(motion,band)
 var z_low:=INF;var z_high:=-INF;var y_high:=-INF
 for i in solver.points.size():
  z_low=minf(z_low,solver.points[i].z-solver.radii[i]);z_high=maxf(z_high,solver.points[i].z+solver.radii[i]);y_high=maxf(y_high,solver.points[i].y+solver.radii[i])
 result['projected_z']=[z_low,z_high]
 result['overlap_fraction']=maxf(0,minf(z_high,solver.barrier_max.z)-maxf(z_low,solver.barrier_min.z))/maxf(.0001,z_high-z_low)
 result['signature']=signature
 var fits:=not signature.is_empty()
 var geometry_reason: String=''
 if signature.is_empty():geometry_reason='empty_signature'
 else:
  var normal:=Vector3(signature.world_normal[0],signature.world_normal[1],signature.world_normal[2])
  if absf(normal.x)<=.99:geometry_reason='short_end_or_corner_normal';fits=false
  if z_low<solver.barrier_min.z+.1 or z_high>solver.barrier_max.z-.1:geometry_reason='partial_wall_width';fits=false
  if y_high>solver.barrier_max.y:geometry_reason='partial_wall_height';fits=false
 solver.points=before
 var basic: String=basic_reason()
 if not basic.is_empty():result.reason=basic
 elif not fits:result.reason=geometry_reason
 else:result.reason='matching'
 var max_damage:=0.0;var damage_kinds: Array=[]
 for link in solver.links:
  max_damage=maxf(max_damage,link.damage)
  if link.damage>.03 and link.kind not in damage_kinds:damage_kinds.append(link.kind)
 result['max_link_damage']=max_damage;result['damage_kinds']=damage_kinds
 var wide_results: Dictionary={}
 for band in wide_signatures:
  var ranked: Dictionary=_choose_speed_bin(wide_signatures[band])
  wide_results[band]={'accepted':ranked.get('accepted',false),'clip':ranked.get('id',''),'overlap':ranked.get('zone_overlap',0),'zones':wide_signatures[band].get('zones',[])}
 result['wide_bands']=wide_results
 if not signature.is_empty():
  var speed: float=signature.closing_speed_mps*3.6
  var normal:=Vector3(signature.world_normal[0],signature.world_normal[1],signature.world_normal[2])
  var tangent: float=(motion-normal*motion.dot(normal)).length()
  result['closing_kmh']=speed;result['tangent_ratio']=tangent/maxf(.0001,signature.closing_speed_mps)
  var selection: Dictionary=_choose_speed_bin(signature)
  result['ranked_clip']=selection.get('id','');result['ranked_score']=selection.get('score',0)
  result['zone_overlap']=selection.get('zone_overlap',0)
  if fits and basic.is_empty():
   if speed<35 or speed>175:result.reason='speed_range'
   elif tangent>maxf(4.0,signature.closing_speed_mps*.65):result.reason='tangential_velocity'
   elif not selection.get('accepted',false):result.reason='bank_match'
   else:result.reason='accepted';result.accepted=true
 return result

func _contact_event(horizon: float) -> Dictionary:
 var began: int=Time.get_ticks_usec()
 var record: Dictionary=diagnose(horizon)
 if record.possible:
  if events.is_empty() or events[-1].reason!=record.reason:events.append(record)
 for lookahead in [.033,.066,.100]:
  var key: String=str(lookahead)
  if not forecast_events.has(key):
   var prediction: Dictionary=diagnose(lookahead,true)
   if prediction.possible and (prediction.accepted or prediction.reason not in ['remote','no_swept_contact']):forecast_events[key]=prediction
 detector_cpu_us+=Time.get_ticks_usec()-began
 return super._contact_event(horizon)
