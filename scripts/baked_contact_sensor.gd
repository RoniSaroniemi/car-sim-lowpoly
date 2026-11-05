extends RefCounted
## Cheap baked-contact prediction; owns no dynamics, clip selection or graph state.
const Grid=preload('res://scripts/impact_zone_grid.gd')
var grid:=Grid.new()
var lookahead_s:=.066
var forecast_interval_s:=1.0/30.0
var arm_lifetime_s:=.100
var clear_hysteresis_s:=.025
var heading_invalidation_deg:=10.0
var motion_invalidation_deg:=12.0
var acceleration_bound:=18.0
var fallback_bands: Array[float]=[.050,.100]
var armed:=false
var arm_started_s:=0.0
var arm_expires_s:=0.0
var arm_normal:=Vector3.ZERO
var arm_motion:=Vector3.ZERO
var arm_forward:=Vector3.RIGHT
var arm_box_min:=Vector3.ZERO
var arm_box_max:=Vector3.ZERO
var next_forecast_s:=0.0
var clear_since_s:=-1.0
var last_clock_s:=-1.0
var last_status: String='clear'
var last_rejection: String=''
var last_cancel: String=''
var broadphase_checks:=0
var actual_sweeps:=0
var forecast_checks:=0
var forecast_nodes:=0
var arm_count:=0
var cancel_count:=0
var manifold_queries:=0
var sensor_cpu_us:=0
var forecast_cpu_us:=0

func reset() -> void:
 armed=false;arm_started_s=0;arm_expires_s=0;next_forecast_s=0;clear_since_s=-1;last_clock_s=-1
 last_status='clear';last_rejection='';last_cancel=''
 broadphase_checks=0;actual_sweeps=0;forecast_checks=0;forecast_nodes=0
 arm_count=0;cancel_count=0;manifold_queries=0;sensor_cpu_us=0;forecast_cpu_us=0

func cancel(reason: String='cancelled') -> void:
 if armed:cancel_count+=1
 armed=false;clear_since_s=-1;next_forecast_s=0
 last_cancel=reason;last_status=reason

func note_rejection(reason: String) -> void:
 # The owner supplies coverage/eligibility/bank reasons; prediction never
 # overrides them or turns an invalid full-wall recording into a corner clip.
 last_rejection=reason;last_status=reason

func nearby(g: RefCounted,motion: Vector3) -> bool:
 broadphase_checks+=1
 if not g.barrier_enabled:return false
 var center: Vector3=g.compact.center if g.compact!=null and g.compact_active else g.station_center(2)
 var offset: Vector3=(g.barrier_min-center).max(center-g.barrier_max).max(Vector3.ZERO)
 var angular: float=g.compact.angular_velocity.length() if g.compact!=null and g.compact_active else 0.0
 var reach: float=3.5+motion.length()*lookahead_s+3.5*angular*lookahead_s
 return offset.length_squared()<=reach*reach

func _body_forward(g: RefCounted) -> Vector3:
 var x: Vector3=g.station_center(6)-g.station_center(0)
 x.y=0
 return x.normalized()

func _basis(points: PackedVector3Array) -> Basis:
 var x: Vector3=(points[24]+points[25]+points[26]+points[27]-points[0]-points[1]-points[2]-points[3])*.25
 x.y=0;x=x.normalized()
 var z: Vector3=x.cross(Vector3.UP).normalized()
 return Basis(x,z.cross(x).normalized(),z)

func _sphere_contact_toi(g: RefCounted,index: int,start: float,end: float) -> float:
 # Expanded-box entry is only a broad phase at a box corner. Conservative
 # advancement confirms the unpadded structural sphere's real distance before
 # replay can start. Planar entries normally complete in one query.
 var time: float=maxf(0,start)
 var velocity: Vector3=g.velocities[index]
 for iteration in 12:
  var hit: Dictionary=g.barrier_distance(g.points[index]+velocity*time)
  var gap: float=float(hit.distance)-g.radii[index]
  if gap<=.00001:return time
  var closing: float=-velocity.dot(hit.normal)
  if closing<=.00001:return INF
  time+=gap/closing
  if time>end+1e-8:return INF
 return INF

func _sweep(g: RefCounted,horizon: float,padding: float=0) -> Dictionary:
 var earliest:=INF;var first:=-1
 for i in g.points.size():
  if g.wheels.by_node.has(i) and g.wheels.wheels[g.wheels.by_node[i]].detached:continue
  var radius: float=g.radii[i]+padding
  var low: Vector3=g.barrier_min-Vector3.ONE*radius
  var high: Vector3=g.barrier_max+Vector3.ONE*radius
  var entry:=0.0;var exit:=horizon;var hit:=true
  for axis in 3:
   var velocity: float=g.velocities[i][axis]
   if absf(velocity)<1e-7:
    if g.points[i][axis]<low[axis] or g.points[i][axis]>high[axis]:hit=false
   else:
    var a: float=(low[axis]-g.points[i][axis])/velocity
    var b: float=(high[axis]-g.points[i][axis])/velocity
    entry=maxf(entry,minf(a,b));exit=minf(exit,maxf(a,b))
   if entry>exit:hit=false
  if hit and exit>=0 and entry<=horizon:
   var contact: float=maxf(0,entry)
   if padding==0:contact=_sphere_contact_toi(g,i,contact,minf(exit,horizon))
   if contact<earliest:earliest=contact;first=i
 return {'toi':earliest,'node':first}

func _invalidate(g: RefCounted,motion: Vector3,now: float) -> void:
 if not armed:return
 if g.barrier_min!=arm_box_min or g.barrier_max!=arm_box_max:
  cancel('obstacle_changed');return
 if now>arm_expires_s:
  cancel('forecast_expired');return
 if motion.length()<.1 or motion.dot(arm_normal)>=-.1:
  cancel('moving_away');return
 if motion.normalized().dot(arm_motion)<cos(deg_to_rad(motion_invalidation_deg)):
  cancel('motion_changed');return
 if _body_forward(g).dot(arm_forward)<cos(deg_to_rad(heading_invalidation_deg)):cancel('steering_changed')

func _forecast(g: RefCounted,motion: Vector3,now: float) -> void:
 if now+1e-8<next_forecast_s:return
 next_forecast_s=now+forecast_interval_s
 var began: int=Time.get_ticks_usec()
 var angular: float=g.compact.angular_velocity.length() if g.compact!=null and g.compact_active else 0.0
 # Current node velocity contains omega×r. This extra bound covers curvature
 # and bounded acceleration for arming only; actual contact uses no padding.
 var padding: float=.5*(acceleration_bound+3.5*angular*angular)*lookahead_s*lookahead_s
 var prediction: Dictionary=_sweep(g,lookahead_s,padding)
 forecast_checks+=1;forecast_nodes+=g.points.size()
 forecast_cpu_us+=Time.get_ticks_usec()-began
 if is_finite(prediction.toi):
  var index: int=prediction.node
  var future: Vector3=g.points[index]+g.velocities[index]*float(prediction.toi)
  var hit: Dictionary=g.barrier_distance(future)
  if motion.dot(hit.normal)<-.1:
   if not armed:arm_started_s=now;arm_count+=1
   armed=true;arm_expires_s=now+arm_lifetime_s;clear_since_s=-1
   arm_box_min=g.barrier_min;arm_box_max=g.barrier_max
   arm_normal=hit.normal;arm_motion=motion.normalized();arm_forward=_body_forward(g)
   last_status='forecast_armed'
   return
 if armed:
  if clear_since_s<0:clear_since_s=now
  if now-clear_since_s>=clear_hysteresis_s:cancel('forecast_cleared')

func _signature(g: RefCounted,motion: Vector3,records: Array,basis: Basis,band: float) -> Dictionary:
 var weights:=PackedFloat32Array();weights.resize(45)
 var total:=0.0;var normal:=Vector3.ZERO;var centroid:=Vector3.ZERO
 var hit_nodes: Array=[]
 for record in records:
  var index: int=record.node
  if float(record.gap)>band or motion.dot(record.normal)>=-.1:continue
  var mass: float=g.masses[index]
  var id: int=grid.zone(g.rest[index]-(basis.transposed()*record.normal)*g.radii[index])
  weights[id]+=mass;total+=mass;normal+=record.normal
  centroid+=record.surface*mass;hit_nodes.append(index)
 if total<=0:return {}
 normal=normal.normalized()
 var local_normal: Vector3=basis.transposed()*normal
 var speed: float=maxf(0,-motion.dot(normal))
 var impulse: float=float(g.config.mass_kg)*speed
 var energy: float=.5*float(g.config.mass_kg)*speed*speed
 var zones: Array=[]
 for id in 45:
  if weights[id]<=0:continue
  var weight: float=weights[id]/total
  zones.append({'id':id,'weight':weight,'incident_impulse_proxy_ns':impulse*weight,'incident_energy_proxy_j':energy*weight})
 centroid/=total
 return {'zones':zones,'normal':[local_normal.x,local_normal.y,local_normal.z],'world_normal':[normal.x,normal.y,normal.z],'velocity':[motion.x,motion.y,motion.z],'closing_speed_mps':speed,'incident_impulse_proxy_ns':impulse,'incident_energy_proxy_j':energy,'hit_nodes':hit_nodes,'grid':[5,3,3],'contact_centroid_world':[centroid.x,centroid.y,centroid.z],'classification_band_m':band}

func _event(g: RefCounted,motion: Vector3,dt: float) -> Dictionary:
 var now: float=g.simulated_time
 if now+1e-8<last_clock_s:reset()
 last_clock_s=now
 if not g.barrier_enabled:
  cancel('barrier_disabled');return {}
 _invalidate(g,motion,now)
 if not nearby(g,motion):
  if armed:cancel('outside_broadphase')
  else:last_status='clear'
  return {}
 _forecast(g,motion,now)
 actual_sweeps+=1
 var actual: Dictionary=_sweep(g,dt)
 if not is_finite(actual.toi):
  last_status='forecast_armed' if armed else 'near_obstacle'
  return {}
 var toi: float=actual.toi
 var points: PackedVector3Array=g.points.duplicate()
 var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
 var records: Array=[]
 for i in points.size():
  points[i]+=g.velocities[i]*toi
  if g.wheels.by_node.has(i) and g.wheels.wheels[g.wheels.by_node[i]].detached:continue
  low=low.min(points[i]-Vector3.ONE*g.radii[i]);high=high.max(points[i]+Vector3.ONE*g.radii[i])
  var hit: Dictionary=g.barrier_distance(points[i])
  records.append({'node':i,'gap':float(hit.distance)-g.radii[i],'normal':hit.normal,'surface':points[i]-hit.normal*float(hit.distance)})
 var frame: Basis=_basis(points)
 var signature: Dictionary=_signature(g,motion,records,frame,.025)
 var fallback: Array=[]
 if armed:
  for band in fallback_bands:fallback.append({'band_m':band,'signature':_signature(g,motion,records,frame,band)})
 manifold_queries+=1
 last_status='contact_manifold';last_rejection=''
 return {'toi':toi,'signature':signature,'fallback_signatures':fallback,'bounds_min':low,'bounds_max':high,'armed':armed,'forecast_lead_s':maxf(0,now-arm_started_s) if armed else 0.0,'first_probe_node':actual.node}

func event(g: RefCounted,motion: Vector3,dt: float) -> Dictionary:
 var began: int=Time.get_ticks_usec()
 var result: Dictionary=_event(g,motion,dt)
 sensor_cpu_us+=Time.get_ticks_usec()-began
 return result

func statistics() -> Dictionary:
 return {'armed':armed,'status':last_status,'last_rejection':last_rejection,'last_cancel':last_cancel,'broadphase_checks':broadphase_checks,'actual_sweeps':actual_sweeps,'forecast_checks':forecast_checks,'forecast_nodes':forecast_nodes,'arm_count':arm_count,'cancel_count':cancel_count,'manifold_queries':manifold_queries,'sensor_cpu_ms':sensor_cpu_us/1000.0,'forecast_cpu_ms':forecast_cpu_us/1000.0,'library_rankings':0}
