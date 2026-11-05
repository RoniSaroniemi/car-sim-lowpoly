extends RefCounted
## Planar condensed mass/contact island proof. No graph/full/cloth solver is evaluated.
const Car=preload('res://probes/multicar/car.gd')
const Grid=preload('res://scripts/impact_zone_grid.gd')
var cars: Array=[]
var h:=1.0/120
var time:=0.0
var tick:=0
var pairs_checked:=0
var broadphase_passes:=0
var contacts_count:=0
var contact_batches: Array=[]
var pair_impulses: Array=[]
var recorded: Array=[]
var costs: Array=[]
var active_pair_keys: Dictionary={}
var restitution:=.03
var solver_iterations:=12
var selected_case:='head_on'
var record_enabled:=true
var replay_steps:=0
func add_car(position_: Vector3,yaw: float,motion: Vector3) -> RefCounted:
 var car:=Car.new();car.setup(cars.size(),position_,yaw,motion);cars.append(car);return car
func start(case_name: String='head_on') -> void:
 selected_case=case_name;cars.clear();contact_batches.clear();pair_impulses.clear();active_pair_keys.clear();costs.clear();recorded.clear()
 time=0;tick=0;pairs_checked=0;broadphase_passes=0;contacts_count=0
 if case_name=='head_on':
  add_car(Vector3(-7,0,0),0,Vector3(60.0/3.6,0,0));add_car(Vector3(7,0,0),PI,Vector3(-60.0/3.6,0,0))
 elif case_name=='parked':
  add_car(Vector3(-10,0,0),0,Vector3(120.0/3.6,0,0));add_car(Vector3(4,0,0),PI,Vector3.ZERO)
 elif case_name=='triple':
  var middle=add_car(Vector3.ZERO,0,Vector3.ZERO)
  var radius: float=middle.half.x
  # Align both initial manifold gaps exactly despite asymmetric source COM/bounds.
  var left=add_car(Vector3(-10,0,0),0,Vector3(84.8528137/3.6,0,0))
  var right=add_car(Vector3(10,0,0),PI,Vector3(-84.8528137/3.6,0,0))
  var gap:=6.0
  left.center.x=middle.bounds_center.x-middle.half.x-left.half.x-left.bounds_center.x-gap
  right.center.x=middle.bounds_center.x+middle.half.x+right.half.x+right.bounds_center.x+gap
  left.publish(0);right.publish(0)
 elif case_name=='drive':
  var player=add_car(Vector3(-35,0,0),0,Vector3.ZERO);player.floor_drag=true
  add_car(Vector3(5,0,0),PI,Vector3.ZERO)
  add_car(Vector3(12,0,5),-PI*.5,Vector3.ZERO)
 elif case_name=='corner':
  add_car(Vector3(-9,0,.90),0,Vector3(120.0/3.6,0,0));add_car(Vector3(4,0,0),PI,Vector3.ZERO)
 elif case_name=='low':
  add_car(Vector3(-3,0,0),0,Vector3(2,0,0));add_car(Vector3(3,0,0),PI,Vector3.ZERO)
 if record_enabled:recorded.append(capture())
func axes(car: RefCounted) -> Array:return [car.basis().x,car.basis().z]
func shape_center(car: RefCounted) -> Vector3:return car.center+car.basis()*car.bounds_center
func radius(car: RefCounted,axis: Vector3) -> float:
 return absf(car.basis().x.dot(axis))*car.half.x+absf(car.basis().z.dot(axis))*car.half.y
func broadphase(a: RefCounted,b: RefCounted,horizon: float) -> bool:
 pairs_checked+=1
 var reach: float=a.half.length()+b.half.length()+(a.velocity-b.velocity).length()*horizon+.03
 var delta: Vector3=shape_center(b)-shape_center(a);delta.y=0
 if delta.length_squared()>reach*reach:return false
 broadphase_passes+=1;return true
func swept_time(a: RefCounted,b: RefCounted,horizon: float) -> float:
 if not broadphase(a,b,horizon):return INF
 var delta: Vector3=shape_center(b)-shape_center(a);delta.y=0
 var relative: Vector3=b.velocity-a.velocity
 var entry:=0.0;var exit:=horizon
 for axis in axes(a)+axes(b):
  var reach: float=radius(a,axis)+radius(b,axis)
  var distance: float=delta.dot(axis);var speed: float=relative.dot(axis)
  if absf(speed)<1e-8:
   if absf(distance)>reach:return INF
  else:
   var p: float=(-reach-distance)/speed;var q: float=(reach-distance)/speed
   entry=maxf(entry,minf(p,q));exit=minf(exit,maxf(p,q))
  if entry>exit:return INF
 return entry if exit>=0 and entry<=horizon else INF
func manifold(a: RefCounted,b: RefCounted,tolerance: float=.006) -> Dictionary:
 var ca: Vector3=shape_center(a);var cb: Vector3=shape_center(b);var delta: Vector3=cb-ca;delta.y=0
 var penetration:=INF;var normal:=Vector3.RIGHT
 for axis in axes(a)+axes(b):
  var overlap: float=radius(a,axis)+radius(b,axis)-absf(delta.dot(axis))
  if overlap< -tolerance:return {}
  if overlap<penetration:
   penetration=overlap;normal=axis*(1 if delta.dot(axis)>=0 else -1)
 var tangent: Vector3=Vector3.UP.cross(normal)
 var low: float=maxf(ca.dot(tangent)-radius(a,tangent),cb.dot(tangent)-radius(b,tangent))
 var high: float=minf(ca.dot(tangent)+radius(a,tangent),cb.dot(tangent)+radius(b,tangent))
 var point_: Vector3=normal*((ca.dot(normal)+radius(a,normal)+cb.dot(normal)-radius(b,normal))*.5)+tangent*((low+high)*.5)
 point_.y=(a.center.y+b.center.y)*.5
 var ra: Vector3=point_-a.center;var rb: Vector3=point_-b.center
 var relative: Vector3=b.velocity+Vector3.UP.cross(rb)*b.omega-a.velocity-Vector3.UP.cross(ra)*a.omega
 return {'a':a.id,'b':b.id,'normal':normal,'point':point_,'depth':maxf(0,penetration),'closing':maxf(0,-relative.dot(normal)),'overlap_width':maxf(0,high-low),'impulse':0.0,'pre_relative':relative}
func impulse(car: RefCounted,point_: Vector3,value: Vector3) -> void:
 car.velocity+=value/car.mass;car.omega+=(point_-car.center).cross(value).y/car.inertia
func momentum() -> Vector3:
 var result:=Vector3.ZERO
 for car in cars:result+=car.velocity*car.mass
 return result
func angular_momentum() -> float:
 var result:=0.0
 for car in cars:result+=car.center.cross(car.velocity*car.mass).y+car.inertia*car.omega
 return result
func energy() -> float:
 var result:=0.0
 for car in cars:result+=car.root_energy()
 return result
func contact_islands(contacts: Array) -> Array:
 var remaining: Array=contacts.duplicate();var groups: Array=[]
 while not remaining.is_empty():
  var group: Array=[remaining.pop_front()]
  var members: Array=[group[0].a,group[0].b]
  var changed:=true
  while changed:
   changed=false
   for index in range(remaining.size()-1,-1,-1):
    var item: Dictionary=remaining[index]
    if item.a in members or item.b in members:
     group.append(item)
     if item.a not in members:members.append(item.a)
     if item.b not in members:members.append(item.b)
     remaining.remove_at(index);changed=true
  groups.append(group)
 return groups
func _solve(contacts: Array) -> Dictionary:
 var p0:=momentum();var l0:=angular_momentum();var e0:=energy()
 for iteration in solver_iterations:
  var ordered: Array=contacts if iteration%2==0 else contacts.duplicate()
  if iteration%2==1:ordered.reverse()
  for contact in ordered:
   var a= cars[contact.a];var b=cars[contact.b];var n: Vector3=contact.normal
   var ra: Vector3=contact.point-a.center;var rb: Vector3=contact.point-b.center
   var relative: Vector3=b.velocity+Vector3.UP.cross(rb)*b.omega-a.velocity-Vector3.UP.cross(ra)*a.omega
   var speed: float=relative.dot(n)
   var weight: float=1/a.mass+1/b.mass+pow(ra.cross(n).y,2)/a.inertia+pow(rb.cross(n).y,2)/b.inertia
   var desired: float=restitution*contact.closing
   var value: float=maxf(0,(desired-speed)/weight)
   if value<=0:continue
   impulse(a,contact.point,-n*value);impulse(b,contact.point,n*value);contact.impulse+=value
 var report: Dictionary={'time':time,'contacts':contacts.duplicate(true),'momentum_error_ns':momentum().distance_to(p0),'angular_error_nms':absf(angular_momentum()-l0),'energy_before_j':e0,'energy_after_j':energy(),'removed_energy_j':maxf(0,e0-energy())}
 pair_impulses.append(report)
 return report
func _signature(car: RefCounted,contact: Dictionary,assigned_kmh: float) -> Dictionary:
 var outward: Vector3=contact.normal if contact.a==car.id else -contact.normal
 var local: Vector3=car.basis().transposed()*(-outward)
 var weights:=PackedFloat32Array();weights.resize(45)
 var extreme: float=-INF
 for i in 28:extreme=maxf(extreme,car.rest_local[i].dot(car.basis().transposed()*outward))
 var total:=0.0;var hits: Array=[];var grid:=Grid.new()
 for i in 28:
  if extreme-car.rest_local[i].dot(car.basis().transposed()*outward)>.12:continue
  var zone: int=grid.zone(car.graph.rest[i]-local*car.graph.radii[i]);weights[zone]+=car.graph.masses[i];total+=car.graph.masses[i];hits.append(i)
 var zones: Array=[]
 for i in 45:
  if weights[i]>0:zones.append({'id':i,'weight':weights[i]/total})
 return {'normal':[local.x,local.y,local.z],'zones':zones,'closing_speed_mps':assigned_kmh/3.6,'incident_impulse_proxy_ns':car.mass*assigned_kmh/3.6,'hit_nodes':hits,'world_normal':[-outward.x,0,-outward.z]}
func _select(batch: Dictionary) -> void:
 var incident: Dictionary={};var total_weight:=0.0
 for c in batch.contacts:
  var weight: float=(cars[c.a].mass*cars[c.b].mass/(cars[c.a].mass+cars[c.b].mass))*c.closing*c.closing
  total_weight+=weight
  for index in [c.a,c.b]:
   if not incident.has(index):incident[index]=[]
   incident[index].append({'contact':c,'weight':weight*.5})
 for index in incident:
  var car=cars[index];var list: Array=incident[index]
  var assigned_energy:=0.0
  for item in list:assigned_energy+=batch.removed_energy_j*item.weight/maxf(.001,total_weight)
  var equivalent: float=sqrt(2*assigned_energy/car.mass)*3.6
  var packet: Dictionary={'time':time,'contact_count':list.size(),'assigned_energy_j':assigned_energy,'equivalent_wall_kmh':equivalent,'relative_closing_kmh':list.map(func(item):return item.contact.closing*3.6),'per_contact_equivalent_kmh':list.map(func(item):return sqrt(2*batch.removed_energy_j*item.weight/maxf(.001,total_weight)/car.mass)*3.6),'policy':'island lost energy, pair incident weight, equal compliance halves','accepted':false}
  if car.played>0:
   car.unsupported_contacts+=1;packet.reason='history_not_covered';car.last_selection=packet;continue
  if equivalent<35:packet.reason='low_energy_no_bake';car.last_selection=packet;continue
  var eligible:=true
  for item in list:
   var c: Dictionary=item.contact
   if c.overlap_width<1.4:eligible=false
   var local: Vector3=car.basis().transposed()*(c.normal if c.a==index else -c.normal)
   if absf(local.x)<cos(deg_to_rad(18)):eligible=false
  if not eligible:packet.reason='partial_or_oblique_not_authored';car.last_selection=packet;continue
  if list.size()>2:
   packet.reason='simultaneous_signature_not_authored';car.last_selection=packet;continue
  if list.size()==2:
   var n0: Vector3=list[0].contact.normal if list[0].contact.a==index else -list[0].contact.normal
   var n1: Vector3=list[1].contact.normal if list[1].contact.a==index else -list[1].contact.normal
   if n0.dot(n1)<-.98 and packet.per_contact_equivalent_kmh.all(func(speed):return absf(speed/60.-1)<.15):
    packet.reason='authored_opposed_composite';car.begin_clip('opposed_front_rear_60',packet)
   else:packet.reason='simultaneous_signature_not_authored';car.last_selection=packet
  else:
   var c: Dictionary=list[0].contact
   var local: Vector3=car.basis().transposed()*(c.normal if c.a==index else -c.normal)
   var chosen_speed: int=60 if equivalent<90 else 120
   var chosen: String=('impact_000_60' if chosen_speed==60 else 'frontal_120') if local.x>0 else ('impact_180_60' if chosen_speed==60 else 'impact_180_120')
   packet['signature']=_signature(car,c,chosen_speed);packet['recorded_speed_kmh']=chosen_speed
   var data: Dictionary=Car.Library.get_clip(chosen,car.graph)
   packet['zone_match']=Grid.new().match_signature(packet.signature,data.metadata.signature)
   if not packet.zone_match.accepted:
    packet.reason='zone_signature_not_authored';car.last_selection=packet;continue
   packet.reason='bounded_front_or_rear_shape';car.begin_clip(chosen,packet)
func step() -> void:
 var began: int=Time.get_ticks_usec()
 for car in cars:car.controls_step(h)
 var earliest:=INF
 for i in cars.size():
  for j in range(i+1,cars.size()):earliest=minf(earliest,swept_time(cars[i],cars[j],h))
 var travel: float=earliest if is_finite(earliest) else h
 for car in cars:car.move_root(travel)
 var contacts: Array=[]
 if is_finite(earliest):
  for i in cars.size():
   for j in range(i+1,cars.size()):
    var contact: Dictionary=manifold(cars[i],cars[j])
    if not contact.is_empty():contacts.append(contact)
 if not contacts.is_empty():
  contacts_count+=contacts.size()
  for island in contact_islands(contacts):
   var solved: Dictionary=_solve(island)
   var fresh: Array=[]
   for contact in island:
    var key: String=str(contact.a)+'_'+str(contact.b)
    if contact.closing>1 and not active_pair_keys.has(key):fresh.append(contact)
    active_pair_keys[key]=tick
   if not fresh.is_empty():
    var batch: Dictionary=solved.duplicate(true);batch.contacts=fresh
    contact_batches.append(batch);_select(batch)
  # Position-only correction is capped and not counted as another impact impulse.
  for contact in contacts:
   var a=cars[contact.a];var b=cars[contact.b]
   var correction: float=maxf(0,contact.depth-.002)*.7
   a.center-=contact.normal*correction*b.mass/(a.mass+b.mass);b.center+=contact.normal*correction*a.mass/(a.mass+b.mass)
 for car in cars:
  car.move_root(h-travel);car.advance_shape(h)
 for key in active_pair_keys.keys():
  if tick-int(active_pair_keys[key])>8:active_pair_keys.erase(key)
 time+=h;tick+=1;costs.append(Time.get_ticks_usec()-began)
 if record_enabled:
  recorded.append(capture())
  if recorded.size()>721:recorded.pop_front()
func capture() -> Dictionary:return {'time':time,'tick':tick,'cars':cars.map(func(car):return car.capture()),'batches':contact_batches.duplicate(true)}
func restore(state: Dictionary) -> void:
 time=state.time;tick=state.tick;contact_batches=state.batches.duplicate(true)
 for i in cars.size():cars[i].restore(state.cars[i])
 replay_steps+=1
func stats() -> Dictionary:
 var sorted: Array=costs.duplicate();sorted.sort();var total:=0.0
 for value in costs:total+=value
 return {'car_count':cars.size(),'mass_kg':cars.reduce(func(sum,car):return sum+car.mass,0.0),'steps':tick,'pairs':pairs_checked,'broadphase_passes':broadphase_passes,'contacts':contacts_count,'batches':contact_batches,'momentum':momentum(),'energy_j':energy(),'mean_us':total/maxi(1,sorted.size()),'p95_us':sorted[mini(sorted.size()-1,floori(sorted.size()*.95))] if not sorted.is_empty() else 0,'p99_us':sorted[mini(sorted.size()-1,floori(sorted.size()*.99))] if not sorted.is_empty() else 0,'full_structure_steps':cars.reduce(func(sum,car):return sum+car.graph.step_count,0)}
