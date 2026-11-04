extends RefCounted
## Small mass-bearing XPBD graph. Plastic rest lengths persist after unloading.

const WheelPhysics=preload('res://scripts/wheel_physics.gd')

class Edge:
 var a: int
 var b: int
 var kind: String
 var original: float
 var length: float
 var stiffness_n_per_m: float
 var yield_n: float
 var max_compression: float
 var max_extension: float
 var damping_ns_per_m: float
 var lambda: float=0.0
 var damage: float=0.0
 var plastic: float=0.0
 var compliance: float
 var weight_sum: float
 var damping_fraction: float
 var wheel_index: int=-1
 var wheel_anchor:=Vector3.ZERO
 var break_force:=INF
 var break_delay:=.012
 var break_plastic:=1.0
 var overload_time:=0.0
 var peak_force:=0.0
 var broken:=false

var wheels: RefCounted
var impact_mode:=0
var barrier_min:=Vector3(0,0,-2.25)
var barrier_max:=Vector3(.5,3.5,2.25)
var config: Dictionary
var hardening: float=0.35
var rest := PackedVector3Array()
var points := PackedVector3Array()
var velocities := PackedVector3Array()
var masses := PackedFloat32Array()
var inverse_masses := PackedFloat32Array()
var radii := PackedFloat32Array()
var links: Array[Edge] = []
var node_damage := PackedFloat32Array()
var node_contact := PackedFloat32Array()
var old_points := PackedVector3Array()
var contact_wall := PackedByteArray()
var contact_floor := PackedByteArray()
var wall_normals:=PackedVector3Array()
var wall_impulse := 0.0
var plastic_work := 0.0
var impact_started := false
var impact_time := -1.0
var initial_energy := 0.0
var maximum_energy := 0.0
var simulated_time := 0.0
var weak_rail := false
var step_count := 0
var total_step_us := 0
var max_step_us := 0
var last_impulse := 0.0

func setup() -> void:
 config=JSON.parse_string(FileAccess.get_file_as_string('res://structure.json'))
 for n in config.nodes:
  rest.append(Vector3(n.position[0],n.position[1],n.position[2]))
  masses.append(n.mass_kg)
  inverse_masses.append(1.0/float(n.mass_kg))
  radii.append(n.radius_m)
 wheels=WheelPhysics.new()
 wheels.setup(self)
 for raw in config.links:
  var l:=Edge.new()
  l.a=raw.a
  l.b=raw.b
  l.kind=raw.kind
  if raw.has('wheel_anchor'):
   l.wheel_index=wheels.by_node[l.a]
   l.wheel_anchor=Vector3(raw.wheel_anchor[0],raw.wheel_anchor[1],raw.wheel_anchor[2])
   l.break_force=raw.break_force_n
   l.break_delay=raw.break_delay_s
   l.break_plastic=raw.break_plastic
  l.original=(rest[l.a]+l.wheel_anchor).distance_to(rest[l.b])
  l.length=l.original
  l.stiffness_n_per_m=raw.stiffness_n_per_m
  l.yield_n=raw.yield_n
  l.max_compression=raw.max_compression
  l.max_extension=raw.max_extension
  l.damping_ns_per_m=raw.damping_ns_per_m
  l.compliance=1.0/l.stiffness_n_per_m
  l.weight_sum=inverse_masses[l.a]+inverse_masses[l.b]
  l.damping_fraction=1.0-exp(-l.damping_ns_per_m*l.weight_sum*float(config.fixed_step_s))
  links.append(l)
  if l.wheel_index>=0:wheels.wheels[l.wheel_index].links.append(l)
 hardening=config.hardening
 node_damage.resize(rest.size())
 node_contact.resize(rest.size())
 contact_wall.resize(rest.size())
 contact_floor.resize(rest.size())
 wall_normals.resize(rest.size())
 reset(0)

func reset(speed_kmh: float,start: Vector3=Vector3(-9,0,0),weaken: bool=false) -> void:
 points=rest.duplicate()
 velocities.resize(rest.size())
 old_points.resize(rest.size())
 for i in points.size():
  points[i]+=start
  velocities[i]=Vector3(speed_kmh/3.6,0,0)
  node_damage[i]=0
  node_contact[i]=0
 for l in links:
  l.length=l.original
  l.lambda=0.0
  l.damage=0.0
  l.plastic=0.0
  l.broken=false
  l.overload_time=0
  l.peak_force=0
 weak_rail=weaken
 plastic_work=0
 wall_impulse=0
 last_impulse=0
 impact_started=false
 impact_time=-1
 simulated_time=0
 wheels.reset(speed_kmh/3.6)
 initial_energy=kinetic_energy()
 maximum_energy=initial_energy
 step_count=0
 total_step_us=0
 max_step_us=0

func step(dt: float) -> void:
 var began: int=Time.get_ticks_usec()
 simulated_time+=dt
 last_impulse=0
 wheels.predict(dt)
 for i in points.size():
  old_points[i]=points[i]
  velocities[i].y-=float(config.gravity_mps2)*dt
  points[i]+=velocities[i]*dt
  contact_wall[i]=0
  contact_floor[i]=0
  wall_normals[i]=Vector3.ZERO
 for l in links:
  l.lambda=0.0
  l.peak_force=0
 for iteration in int(config.iterations):
  # Reverse the sweep every iteration to limit directional solver bias.
  for offset in links.size():
   var index: int=offset if iteration%2==0 else links.size()-1-offset
   _solve_link(links[index],dt)
  wheels.constrain_knuckles(dt)
  _contacts()
  wheels.contacts(dt)
  if bool(config.enforce_symmetry) and not weak_rail and impact_mode==0:
   _symmetry()
 for i in points.size():
  velocities[i]=(points[i]-old_points[i])/dt
  if config.nodes[i].group=='wheel':continue
  if contact_wall[i]:
   var inward: float=velocities[i].dot(wall_normals[i])
   if inward<0:
    last_impulse-=masses[i]*inward
    velocities[i]-=wall_normals[i]*inward
  if contact_floor[i] and velocities[i].y<0:
   velocities[i].y=0
  if contact_floor[i]:
   var is_wheel: bool=config.nodes[i].group=='wheel'
   var friction: float=0.03 if is_wheel else 0.7
   var flat:=Vector2(velocities[i].x,velocities[i].z)
   flat=flat.move_toward(Vector2.ZERO,friction*float(config.gravity_mps2)*dt)
   velocities[i].x=flat.x
   velocities[i].z=flat.y
 wheels.finish_step(dt)
 _damping(dt)
 _break_links(dt)
 wall_impulse+=last_impulse
 maximum_energy=maxf(maximum_energy,kinetic_energy())
 step_count+=1
 var duration: int=Time.get_ticks_usec()-began
 total_step_us+=duration
 max_step_us=maxi(max_step_us,duration)

func _solve_link(l: Edge,dt: float) -> void:
 if l.broken:return
 var a: int=l.a
 var b: int=l.b
 var anchor:=Vector3.ZERO
 if l.wheel_index>=0:anchor=wheels.anchor(l.wheel_index,l.wheel_anchor)
 var d: Vector3=points[b]-points[a]-anchor
 var distance: float=d.length()
 if distance<0.00001:
  return
 var normal: Vector3=d/distance
 var w: float=l.weight_sum
 if l.wheel_index>=0:w+=wheels.rotational_weight(l.wheel_index,anchor,normal)
 var alpha: float=l.compliance/(dt*dt)
 var c: float=distance-l.length
 var dl: float=(-c-alpha*l.lambda)/(w+alpha)
 var trial: float=l.lambda+dl
 var force: float=absf(trial)/(dt*dt)
 l.peak_force=maxf(l.peak_force,force)
 var max_plastic: float=l.max_compression if trial>0 else l.max_extension
 var amount: float=absf(l.length-l.original)/maxf(0.001,l.original*max_plastic)
 var yield_n: float=l.yield_n*(1.0+hardening*amount)
 if trial<0:
  yield_n*=2.0
 if weak_rail and l.kind in ['front_rail','front_brace','sill'] and rest[a].z>0 and rest[b].z>0:
  yield_n*=0.55
 if force>yield_n and max_plastic>0:
  var capped: float=signf(trial)*yield_n*dt*dt
  var wanted: float=distance+alpha*capped
  var new_length: float=clampf(wanted,l.original*(1.0-l.max_compression),l.original*(1.0+l.max_extension))
  var delta: float=new_length-l.length
  if absf(delta)>0.0000001:
   l.length=new_length
   l.plastic+=absf(delta)
   plastic_work+=yield_n*absf(delta)
   l.damage=maxf(l.damage,absf(new_length-l.original)/maxf(0.001,l.original*maxf(0.05,max_plastic)))
   node_damage[a]=maxf(node_damage[a],minf(1.0,l.damage))
   node_damage[b]=maxf(node_damage[b],minf(1.0,l.damage))
   c=distance-new_length
   dl=(-c-alpha*l.lambda)/(w+alpha)
 l.lambda+=dl
 points[a]-=normal*(inverse_masses[a]*dl)
 points[b]+=normal*(inverse_masses[b]*dl)
 if l.wheel_index>=0:wheels.correct_rotation(l.wheel_index,anchor,normal,-dl)

func set_impact_mode(value: int) -> void:
 impact_mode=value
 barrier_min=Vector3(0,0,.48) if value==1 else Vector3(0,0,-2.25)
 barrier_max=Vector3(.65,1.35,1.10) if value==1 else Vector3(.5,3.5,2.25)

func barrier_distance(p: Vector3) -> Dictionary:
 var closest: Vector3=p.clamp(barrier_min,barrier_max)
 var delta: Vector3=p-closest
 var distance: float=delta.length()
 if distance>1e-8:return {'distance':distance,'normal':delta/distance}
 var distances: Array=[p.x-barrier_min.x,barrier_max.x-p.x,p.y-barrier_min.y,barrier_max.y-p.y,p.z-barrier_min.z,barrier_max.z-p.z]
 var normals: Array=[Vector3.LEFT,Vector3.RIGHT,Vector3.DOWN,Vector3.UP,Vector3.FORWARD,Vector3.BACK]
 var face:=0
 for i in 6:
  if distances[i]<distances[face]:face=i
 return {'distance':-distances[face],'normal':normals[face]}

func mark_impact(i: int) -> void:
 if not impact_started:
  impact_started=true
  impact_time=simulated_time
 node_contact[i]=maxf(node_contact[i],clampf(velocities[i].length()/24.0,0,1))

func _contacts() -> void:
 for i in points.size():
  if config.nodes[i].group=='wheel':continue
  var p: Vector3=points[i]
  if p.x>=barrier_min.x-radii[i]:
   var hit: Dictionary=barrier_distance(p)
   if float(hit.distance)<radii[i]:
    mark_impact(i)
    contact_wall[i]=1
    wall_normals[i]=hit.normal
    p+=hit.normal*(radii[i]-float(hit.distance))
  if p.y<radii[i]:
   contact_floor[i]=1
   p.y=radii[i]
  points[i]=p

func _break_links(dt: float) -> void:
 for l in links:
  if l.wheel_index<0 or l.broken:continue
  var overload: bool=l.peak_force>l.break_force or l.damage>l.break_plastic
  l.overload_time=maxf(0,l.overload_time+(dt if overload else -dt*2))
  if l.overload_time>=l.break_delay:
   l.broken=true
   l.lambda=0
   l.damage=1.0
 for wheel in wheels.wheels:
  if wheel.links.all(func(l):return l.broken):
   wheel.joint_broken=true
   wheel.detached=true

func _damping(dt: float) -> void:
 for l in links:
  if l.broken:continue
  var a: int=l.a
  var b: int=l.b
  var anchor:=Vector3.ZERO
  var anchor_velocity:=Vector3.ZERO
  if l.wheel_index>=0:
   anchor=wheels.anchor(l.wheel_index,l.wheel_anchor)
   anchor_velocity=wheels.anchor_velocity(l.wheel_index,anchor)
  var normal: Vector3=(points[b]-points[a]-anchor).normalized()
  var w: float=l.weight_sum
  if l.wheel_index>=0:w+=wheels.rotational_weight(l.wheel_index,anchor,normal)
  var relative: float=(velocities[b]-velocities[a]-anchor_velocity).dot(normal)
  var fraction: float=l.damping_fraction
  var impulse: float=-relative*fraction/w
  velocities[a]-=normal*(inverse_masses[a]*impulse)
  velocities[b]+=normal*(inverse_masses[b]*impulse)
  if l.wheel_index>=0:wheels.damp_rotation(l.wheel_index,anchor,-normal*impulse)

func kinetic_energy() -> float:
 var total:=0.0
 for i in velocities.size():
  total+=0.5*masses[i]*velocities[i].length_squared()
 return total+wheels.kinetic_energy()

func center_of_mass() -> Vector3:
 var centre:=Vector3.ZERO
 for i in points.size():
  centre+=points[i]*masses[i]
 return centre/float(config.mass_kg)

func station_center(s: int) -> Vector3:
 return (points[s*4]+points[s*4+1]+points[s*4+2]+points[s*4+3])*0.25

func station_damage(s: int) -> float:
 return (node_damage[s*4]+node_damage[s*4+1]+node_damage[s*4+2]+node_damage[s*4+3])*0.25

func metrics() -> Dictionary:
 var rest_front: Vector3=(rest[24]+rest[25]+rest[26]+rest[27]-rest[12]-rest[13]-rest[14]-rest[15])*0.25
 var rest_cabin: Vector3=(rest[12]+rest[13]+rest[14]+rest[15]-rest[4]-rest[5]-rest[6]-rest[7])*0.25
 var cabin_intrusion: float=maxf(0,rest_cabin.length()-(station_center(3)-station_center(1)).length())
 var roof_span: float=((points[10]+points[11])-(points[8]+points[9])).length()*0.5
 var roof_drop: float=maxf(0,1.2-roof_span)
 var yielded:=0
 for l in links:
  if l.damage>0.002:
   yielded+=1
 return {'wheels':wheels.metrics(),'broken_suspension_links':links.filter(func(l):return l.broken).size(),'impact_mode':impact_mode,'front_shortening_m':maxf(0,rest_front.length()-(station_center(6)-station_center(3)).length()),'cabin_shortening_m':cabin_intrusion,'roof_drop_m':roof_drop,'yielded_links':yielded,'plastic_work_kj':plastic_work/1000.0,'kinetic_kj':kinetic_energy()/1000.0,'initial_energy_kj':initial_energy/1000.0,'maximum_kinetic_kj':maximum_energy/1000.0,'nodes':points.size(),'links':links.size(),'mass_kg':config.mass_kg,'mean_step_us':float(total_step_us)/maxi(1,step_count),'max_step_us':max_step_us,'impact_time_s':impact_time}

func capture() -> Dictionary:
 var lengths:=PackedFloat32Array()
 var damage:=PackedFloat32Array()
 var broken:=PackedByteArray()
 for l in links:
  lengths.append(l.length)
  damage.append(l.damage)
  broken.append(1 if l.broken else 0)
 return {'wheels':wheels.capture(),'broken':broken,'velocities':velocities.duplicate(),'points':points.duplicate(),'damage':node_damage.duplicate(),'contact':node_contact.duplicate(),'lengths':lengths,'link_damage':damage,'time':simulated_time,'plastic_work':plastic_work}

func restore(frame: Dictionary) -> void:
 points=frame.points.duplicate()
 velocities=frame.velocities.duplicate()
 wheels.restore(frame.wheels)
 node_damage=frame.damage.duplicate()
 node_contact=frame.contact.duplicate()
 for i in links.size():
  links[i].length=frame.lengths[i]
  links[i].damage=frame.link_damage[i]
  links[i].broken=bool(frame.broken[i])
 simulated_time=frame.time
 plastic_work=frame.plastic_work

func _symmetry() -> void:
 # Symmetric full-width frontal test boundary condition. Disabled for the
 # weakened-rail experiment, which is free to twist and yaw.
 for i in range(0,30,2):
  _symmetric_pair(i,i+1)
 _symmetric_pair(30,31)
 points[32].z=0
 points[33].z=0
 # Detached / partly failed assemblies must not retain an invisible mirror tether.
 for pair in [[34,35],[36,37]]:
  var intact: bool=true
  for node in pair:
   for l in wheels.wheels[wheels.by_node[node]].links:
    intact=intact and not l.broken
  if intact:_symmetric_pair(pair[0],pair[1])

func _symmetric_pair(a: int,b: int) -> void:
 var x: float=(points[a].x+points[b].x)*0.5
 var y: float=(points[a].y+points[b].y)*0.5
 var z: float=(absf(points[a].z)+absf(points[b].z))*0.5
 points[a]=Vector3(x,y,-z)
 points[b]=Vector3(x,y,z)
