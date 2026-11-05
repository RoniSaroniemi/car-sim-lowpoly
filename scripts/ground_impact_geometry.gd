extends RefCounted
const Geometry=preload('res://scripts/roof_landing_geometry.gd')
const Grid=preload('res://scripts/impact_zone_grid.gd')
static func motion(vehicle: RefCounted,probe: Dictionary,t: float) -> Dictionary:
 var compact: RefCounted=vehicle.compact
 var gravity: float=vehicle.solver.config.gravity_mps2
 var omega: Vector3=compact.angular_velocity
 var angle: float=omega.length()*t
 var rotation:=Basis(omega.normalized(),angle) if angle>1e-9 else Basis.IDENTITY
 var arm: Vector3=rotation*(probe.position-compact.center)
 var linear: Vector3=compact.linear_velocity+Vector3.DOWN*gravity*t
 return {'position':compact.center+compact.linear_velocity*t+Vector3.DOWN*gravity*t*t+arm,'velocity':linear+omega.cross(arm)}
static func gap(g: RefCounted,position: Vector3,radius: float) -> Dictionary:
 var surface: Vector4=g.floor_sample(position)
 var normal:=Vector3(surface.x,surface.y,surface.z).normalized()
 return {'distance':(position.y-surface.w)*normal.y-radius,'normal':normal,'point':Vector3(position.x,surface.w,position.z)}
static func packet(vehicle: RefCounted,horizon: float) -> Dictionary:
 var g: RefCounted=vehicle.solver;g.panels.synchronize_inactive()
 var probes: Array=Geometry.probes(g);var first:=INF;var first_hit: Dictionary={}
 for p in probes:
  var initial: Dictionary=gap(g,p.position,p.radius)
  var travel: Dictionary=motion(vehicle,p,horizon)
  var next: Dictionary=gap(g,travel.position,p.radius)
  if minf(initial.distance,next.distance)>.00001:continue
  if travel.velocity.dot(next.normal)>=-.005:continue
  var low:=0.0;var high:=horizon
  if initial.distance<=.00001:high=0
  else:
   for iteration in 14:
    var middle: float=(low+high)*.5
    var m: Dictionary=motion(vehicle,p,middle)
    if gap(g,m.position,p.radius).distance<=.000001:high=middle
    else:low=middle
  if high<first:first=high;first_hit=gap(g,motion(vehicle,p,high).position,p.radius)
 if not is_finite(first):return {}
 var basis: Basis=Geometry.basis(g)
 var angle: float=vehicle.compact.angular_velocity.length()*first
 if angle>1e-9:basis=Basis(vehicle.compact.angular_velocity.normalized(),angle)*basis
 var normal: Vector3=first_hit.normal
 var local: Vector3=basis.transposed()*normal
 var weights: Dictionary={};var total:=0.0;var speed_sum:=0.0;var contacts: Array=[]
 for p in probes:
  var m: Dictionary=motion(vehicle,p,first);var hit: Dictionary=gap(g,m.position,p.radius)
  var speed: float=maxf(0,-m.velocity.dot(hit.normal))
  if hit.distance>.008 or hit.normal.dot(normal)<.95:continue
  var rest: Vector3=p.rest-local*float(p.radius)
  if p.source=='wheel':rest=p.rest+basis.transposed()*p.support
  var id: int=Grid.new().zone(rest)
  weights[id]=float(weights.get(id,0))+p.mass;total+=p.mass;speed_sum+=speed*p.mass
  contacts.append({'source':p.source,'node':p.node,'panel':p.get('panel',''),'zone':id})
 if total<=0:return {}
 var closing: float=speed_sum/total;var zones: Array=[];var ids: Array=weights.keys();ids.sort()
 for id in ids:
  var weight: float=weights[id]/total
  zones.append({'id':id,'weight':weight,'incident_impulse_proxy_ns':g.config.mass_kg*closing*weight,'incident_energy_proxy_j':.5*g.config.mass_kg*closing*closing*weight})
 var signature: Dictionary={'zones':zones,'normal':[local.x,local.y,local.z],'world_normal':[normal.x,normal.y,normal.z],'velocity':[vehicle.compact.linear_velocity.x,vehicle.compact.linear_velocity.y,vehicle.compact.linear_velocity.z],'closing_speed_mps':closing,'incident_impulse_proxy_ns':g.config.mass_kg*closing,'first_contacts':contacts}
 return {'toi':first,'signature':signature,'ground_normal':normal,'ground_point':first_hit.point,'floor_contact':true}
static func advance(vehicle: RefCounted,t: float) -> void:
 var g: RefCounted=vehicle.solver;var omega: Vector3=vehicle.compact.angular_velocity
 var angle: float=omega.length()*t
 var rotation:=Basis(omega.normalized(),angle) if angle>1e-9 else Basis.IDENTITY
 for i in g.points.size():
  var m: Dictionary=motion(vehicle,{'position':g.points[i]},t)
  g.points[i]=m.position;g.velocities[i]=m.velocity
 for wheel in g.wheels.wheels:
  wheel.rotation=(rotation.get_rotation_quaternion()*wheel.rotation).normalized()
  wheel.previous_rotation=wheel.rotation
 g.panels.synchronize_inactive()
