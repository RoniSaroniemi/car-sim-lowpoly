extends RefCounted
const Probes=preload('res://scripts/multiaxis_crash_recorder.gd')
const Roof=preload('res://scripts/roof_crash_recorder.gd')
const Grid=preload('res://scripts/impact_zone_grid.gd')
static func probes(g: RefCounted) -> Array:return Probes.probes(g)
static func basis(g: RefCounted) -> Basis:return Roof.full_chassis_basis(g)
static func minimum_gap(g: RefCounted) -> float:
 var gap:=INF
 for p in probes(g):gap=minf(gap,p.position.y-p.radius-g.floor_sample(p.position).w)
 return gap
static func signature(g: RefCounted,time: float=0,band: float=.003) -> Dictionary:
 var frame:=basis(g);var gravity: float=g.config.gravity_mps2
 var weights: Dictionary={};var total:=0.0;var speed_sum:=0.0;var hits: Array=[]
 for p in probes(g):
  var point: Vector3=p.position+p.velocity*time+Vector3.DOWN*gravity*time*time
  var floor_: Vector4=g.floor_sample(point)
  var velocity: Vector3=p.velocity+Vector3.DOWN*gravity*time
  var speed: float=-velocity.y
  if point.y-p.radius-floor_.w>band or speed<.1:continue
  var local_normal: Vector3=frame.transposed()*Vector3.UP
  var rest: Vector3=p.rest-local_normal*float(p.radius)
  if p.source=='wheel':rest=p.rest+frame.transposed()*p.support
  var id: int=Grid.new().zone(rest)
  weights[id]=float(weights.get(id,0))+p.mass;total+=p.mass;speed_sum+=speed*p.mass
  hits.append({'source':p.source,'node':p.node,'panel':p.get('panel',''),'zone':id})
 if total<=0:return {}
 var closing: float=speed_sum/total;var zones: Array=[]
 var ids: Array=weights.keys();ids.sort()
 for id in ids:
  var weight: float=weights[id]/total
  zones.append({'id':id,'weight':weight,'incident_impulse_proxy_ns':g.config.mass_kg*closing*weight,'incident_energy_proxy_j':.5*g.config.mass_kg*closing*closing*weight})
 var n: Vector3=frame.transposed()*Vector3.UP
 return {'zones':zones,'normal':[n.x,n.y,n.z],'world_normal':[0,1,0],'velocity':[0,-closing,0],'closing_speed_mps':closing,'incident_impulse_proxy_ns':g.config.mass_kg*closing,'incident_energy_proxy_j':.5*g.config.mass_kg*closing*closing,'first_contacts':hits,'grid':[5,3,3],'contact_source':'roof_landing_floor'}
static func pose(g: RefCounted) -> Dictionary:
 var frame:=basis(g);var velocity:=Vector3.ZERO;var center:=Vector3.ZERO;var mass:=0.0
 for i in g.points.size():
  if g.wheels.by_node.has(i):continue
  velocity+=g.velocities[i]*g.masses[i];center+=g.points[i]*g.masses[i];mass+=g.masses[i]
 velocity/=mass;center/=mass
 var xx:=0.0;var yy:=0.0;var zz:=0.0;var xy:=0.0;var xz:=0.0;var yz:=0.0;var momentum:=Vector3.ZERO
 for i in g.points.size():
  if g.wheels.by_node.has(i):continue
  var arm: Vector3=g.points[i]-center;var m: float=g.masses[i]
  xx+=m*(arm.y*arm.y+arm.z*arm.z);yy+=m*(arm.x*arm.x+arm.z*arm.z);zz+=m*(arm.x*arm.x+arm.y*arm.y)
  xy-=m*arm.x*arm.y;xz-=m*arm.x*arm.z;yz-=m*arm.y*arm.z
  momentum+=arm.cross((g.velocities[i]-velocity)*m)
 var inertia:=Basis(Vector3(xx,xy,xz),Vector3(xy,yy,yz),Vector3(xz,yz,zz))
 var omega: Vector3=inertia.inverse()*momentum
 return {'basis':frame,'velocity':velocity,'center':center,'omega':omega,'forward_mps':velocity.dot(frame.x),'side_mps':velocity.dot(frame.z),'roll_rate':omega.dot(frame.x),'pitch_rate':omega.dot(frame.z),'yaw_rate':omega.dot(frame.y),'roof_down':-frame.y.dot(Vector3.UP),'pitch':absf(frame.x.y)}
