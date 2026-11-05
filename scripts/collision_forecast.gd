extends RefCounted
## Conservative swept bounds for the benchmark's analytic box and floor.
var horizon:=.18
var margin:=.12
var acceleration_bound:=12.0
var obstacle_velocity:=Vector3.ZERO
var checks:=0

func predict(g: RefCounted,linear: Vector3,angular: Vector3) -> Dictionary:
 checks+=1
 var low:=Vector3(INF,INF,INF)
 var high:=Vector3(-INF,-INF,-INF)
 var body_floor:=INF
 for i in g.points.size():
  if g.wheels.by_node.has(i) and g.wheels.wheels[g.wheels.by_node[i]].detached:continue
  var r: float=g.radii[i]
  low=low.min(g.points[i]-Vector3.ONE*r)
  high=high.max(g.points[i]+Vector3.ONE*r)
  if not g.wheels.by_node.has(i):body_floor=minf(body_floor,g.points[i].y-g.floor_sample(g.points[i]).w-r)
 var future_body_floor:=INF
 var future_wheel_floor:=INF
 for i in g.points.size():
  if g.wheels.by_node.has(i) and g.wheels.wheels[g.wheels.by_node[i]].detached:continue
  var future: Vector3=g.points[i]+linear*horizon+angular.cross(g.points[i]-(low+high)*.5)*horizon
  future.y-=.5*float(g.config.gravity_mps2)*horizon*horizon
  var clearance: float=future.y-g.floor_sample(future).w-g.radii[i]
  if g.wheels.by_node.has(i):future_wheel_floor=minf(future_wheel_floor,clearance)
  else:future_body_floor=minf(future_body_floor,clearance)
 var extent: Vector3=(high-low)*.5
 var center: Vector3=(high+low)*.5
 var angular_padding: float=extent.length()*angular.length()*horizon
 var padding: float=margin+angular_padding+.5*acceleration_bound*horizon*horizon
 var result: Dictionary={'risk':false,'reason':'clear','time_to_contact_s':-1.0,'clearance_m':-1.0}
 if g.barrier_enabled:
  var expanded_min: Vector3=g.barrier_min-extent-Vector3.ONE*padding
  var expanded_max: Vector3=g.barrier_max+extent+Vector3.ONE*padding
  var relative: Vector3=linear-obstacle_velocity
  var entry:=0.0
  var exit:=horizon
  var possible:=true
  for axis in 3:
   if absf(relative[axis])<.00001:
    if center[axis]<expanded_min[axis] or center[axis]>expanded_max[axis]:possible=false
   else:
    var a: float=(expanded_min[axis]-center[axis])/relative[axis]
    var b: float=(expanded_max[axis]-center[axis])/relative[axis]
    entry=maxf(entry,minf(a,b))
    exit=minf(exit,maxf(a,b))
   if entry>exit:possible=false
  if possible and exit>=0 and entry<=horizon:
   result.risk=true
   result.reason='forecast_box'
   result.time_to_contact_s=maxf(0,entry)
   var separation: Vector3=(g.barrier_min-high).max(low-g.barrier_max).max(Vector3.ZERO)
   result.clearance_m=separation.length()
 if g.static_contact_provider!=null:
  var world_risk: Dictionary=g.static_contact_provider.forecast(center,extent,linear,angular,horizon,padding)
  if world_risk.get('risk',false):result=world_risk
 # Tire support on the road is routine; body-floor strikes/hard landings are not.
 # Yaw rotates in the ground plane. It cannot make the car fall downward.
 var vertical_angular_speed: float=Vector2(angular.x,angular.z).length()
 var down: float=linear.y-vertical_angular_speed*Vector2(extent.x,extent.z).length()
 if body_floor<.04 or (down<-.5 and future_body_floor<.04):
  result.risk=true
  result.reason='forecast_body_floor'
 if down< -2.5 and future_wheel_floor<0:
  result.risk=true
  result.reason='forecast_hard_landing'
 return result
