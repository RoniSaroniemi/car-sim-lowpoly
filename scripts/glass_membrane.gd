extends RefCounted
## Small stiff PBD interlayer: cracked glass can bow; the frame remains mounted.
## Thresholds are art-directed, not measured PVB/glass material properties.
const NX=12
const NY=8
const STEP=1.0/120.0
const SWEEPS=6
var rest:=PackedVector3Array()
var points:=PackedVector3Array()
var velocity:=PackedVector3Array()
var anchored:=PackedByteArray()
var released:=PackedByteArray()
var bonds: Array=[]
var bends: Array=[]
var adjacency: Array=[]
var bond_lookup: Dictionary={}
var clock:=0.0
var accumulator:=0.0
var energy:=.6
var puncture:=false
var seed_value:=271
var solve_steps:=0
var total_solve_us:=0
var release_events: Array=[]
var history: Array=[]
var max_strain:=0.0
var loaded_nodes:=PackedByteArray()
var next_sample:=0.0
var pane_width:=2.55
var pane_height:=1.55
var attachment:=Transform3D.IDENTITY
var boundary_targets:=PackedVector3Array()
var hit_uv:=Vector2(.5,.5)
var scale_factor:=1.0
var bounds_initialized:=false
var tool_clock:=0.0
var active_until:=2.0
var cracked:=true
var record_history:=false

func setup_pane(width: float,height: float,transform: Transform3D,targets: PackedVector3Array,initial_velocity: Vector3,impact_energy: float,sharp: bool,uv: Vector2=Vector2(.5,.5),seed_id: int=271) -> void:
 pane_width=width;pane_height=height;attachment=transform;boundary_targets=targets.duplicate();hit_uv=uv
 scale_factor=minf(width/2.55,height/1.55)
 setup(impact_energy,sharp,seed_id)
 if targets.size()==points.size():points=targets.duplicate()
 else:
  for i in points.size():points[i]=attachment*points[i]
 velocity.fill(initial_velocity)
 history.clear();_sample()
 bounds_initialized=true

func setup(impact_energy: float,sharp: bool,seed_id: int=271) -> void:
 energy=impact_energy;puncture=sharp;seed_value=seed_id
 var rng:=RandomNumberGenerator.new();rng.seed=seed_value
 for y in NY+1:
  for x in NX+1:
   var u: float=float(x)/NX;var v: float=float(y)/NY
   rest.append(Vector3((u-.5)*pane_width,(v-.5)*pane_height,0))
   anchored.append(1 if x==0 or x==NX or y==0 or y==NY else 0)
   released.append(0);adjacency.append([])
 points=rest.duplicate();velocity.resize(rest.size());velocity.fill(Vector3.ZERO);loaded_nodes.resize(rest.size())
 var structural: Dictionary={}
 for y in NY+1:
  for x in NX+1:
   var index: int=y*(NX+1)+x
   if x<NX:structural['%d_%d'%[index,index+1]]=_bond(index,index+1,'stretch',rng)
   if y<NY:structural['%d_%d'%[index,index+NX+1]]=_bond(index,index+NX+1,'stretch',rng)
   if x<NX and y<NY:
    _bond(index,index+NX+2,'shear',rng);_bond(index+1,index+NX+1,'shear',rng)
 for y in NY+1:
  for x in NX+1:
   var index: int=y*(NX+1)+x
   if x>0 and x<NX:
    bends.append({'a':index-1,'b':index,'c':index+1,'edges':[structural['%d_%d'%[index-1,index]],structural['%d_%d'%[index,index+1]]]})
   if y>0 and y<NY:
    bends.append({'a':index-NX-1,'b':index,'c':index+NX+1,'edges':[structural['%d_%d'%[index-NX-1,index]],structural['%d_%d'%[index,index+NX+1]]]})
 _sample();next_sample=1.0/60
func _bond(a: int,b: int,kind: String,rng: RandomNumberGenerator) -> int:
 var center: Vector3=(rest[a]+rest[b])*.5
 var core: float=exp(-Vector2(center.x,center.y).length_squared()/.12)
 var threshold: float=(.22 if puncture else .45)*rng.randf_range(.9,1.1)
 bonds.append({'a':a,'b':b,'rest':rest[a].distance_to(rest[b]),'kind':kind,'broken':false,'tear_strain':threshold,'peak_strain':0.0,'strength_scale':threshold/(.22 if puncture else .45)})
 adjacency[a].append(bonds.size()-1);adjacency[b].append(bonds.size()-1)
 bond_lookup['%d_%d'%[mini(a,b),maxi(a,b)]]=bonds.size()-1
 return bonds.size()-1
func load_again(impact_energy: float,sharp: bool,uv: Vector2) -> void:
 energy=impact_energy;puncture=sharp;hit_uv=uv;tool_clock=0;active_until=clock+2
 for bond in bonds:
  bond.tear_strain=(.22 if puncture else .45)*float(bond.get('strength_scale',1.0))

func advance(dt: float) -> void:
 accumulator+=dt
 while accumulator+1e-10>=STEP and clock<active_until-1e-8:
  _step(STEP);accumulator-=STEP
func _step(dt: float) -> void:
 var began: int=Time.get_ticks_usec();clock+=dt;tool_clock+=dt;loaded_nodes.fill(0)
 var old: PackedVector3Array=points.duplicate()
 if boundary_targets.size()==points.size():
  for i in points.size():
   if anchored[i]:points[i]=boundary_targets[i]
 for i in points.size():
  if anchored[i] or released[i]:continue
  velocity[i].y-=9.81*dt
  velocity[i]*=exp(-2.5*dt)
  points[i]+=velocity[i]*dt
 for iteration in SWEEPS:
  for bond in bonds:
   if bond.broken or released[bond.a] or released[bond.b]:continue
   var delta: Vector3=points[bond.b]-points[bond.a]
   var distance: float=delta.length()
   if distance<1e-8:continue
   var strain: float=absf(distance/float(bond.rest)-1)
   bond.peak_strain=maxf(bond.peak_strain,strain);max_strain=maxf(max_strain,strain)
   var tear_limit: float=float(bond.tear_strain)*(.08 if puncture and (loaded_nodes[bond.a] or loaded_nodes[bond.b]) else 1.0)
   if clock>.025 and (strain if puncture and (loaded_nodes[bond.a] or loaded_nodes[bond.b]) else maxf(0,distance/float(bond.rest)-1))>tear_limit:bond.broken=true;continue
   var a_weight: float=0 if anchored[bond.a] else 1
   var b_weight: float=0 if anchored[bond.b] else 1
   var weight: float=a_weight+b_weight
   if weight==0:continue
   # Small compliance leaves stiff stretching after the glass cracks.
   var compliance: float=(2e-7 if bond.kind=='stretch' else 6e-7) if cracked else 1e-10
   var amount: float=(distance-float(bond.rest))/(weight+compliance/(dt*dt))
   var normal: Vector3=delta/distance
   points[bond.a]+=normal*amount*a_weight;points[bond.b]-=normal*amount*b_weight
  for bend in bends:
   if bonds[bend.edges[0]].broken or bonds[bend.edges[1]].broken:continue
   if released[bend.a] or released[bend.b] or released[bend.c]:continue
   var error: Vector3=points[bend.b]-(points[bend.a]+points[bend.c])*.5
   var weights: Array=[0.0 if anchored[bend.a] else .5,0.0 if anchored[bend.b] else 1.0,0.0 if anchored[bend.c] else .5]
   var weight: float=float(weights[1])+.5*(float(weights[0])+float(weights[2]))
   if weight>0:
    # Interlayer bends much more readily than it stretches after cracking.
    var correction: Vector3=error*((.10 if cracked else .8)/weight)
    points[bend.a]+=correction*float(weights[0]);points[bend.b]-=correction*float(weights[1]);points[bend.c]+=correction*float(weights[2])
  _indenter()
 for i in points.size():
  if not anchored[i] and not released[i]:velocity[i]=(points[i]-old[i])/dt
 if solve_steps%4==0:_release_islands()
 solve_steps+=1
 if clock+1e-9>=next_sample:_sample();next_sample+=1.0/60
 total_solve_us+=Time.get_ticks_usec()-began
func _indenter() -> void:
 if tool_clock>.32 or energy<=0:return
 var radius: float=.19+maxf(0,energy-.7)*.10 if puncture else .40
 var travel: float=(.62+energy*.27) if puncture else (.13+energy*.10)
 var z: float=-radius-.08+travel*smoothstep(0,.24,tool_clock)
 var center: Vector3=attachment*Vector3((hit_uv.x-.5)*pane_width,(hit_uv.y-.5)*pane_height,z*scale_factor)
 radius*=scale_factor
 for i in points.size():
  if anchored[i] or released[i]:continue
  var delta: Vector3=points[i]-center
  var distance: float=delta.length()
  if distance<radius:
   loaded_nodes[i]=1
   var normal: Vector3=delta/distance if distance>.0001 else Vector3.BACK
   points[i]=center+normal*radius
func _release_islands() -> void:
 var connected:=PackedByteArray();connected.resize(points.size())
 var queue: Array=[]
 for i in points.size():
  if anchored[i]:connected[i]=1;queue.append(i)
 var cursor:=0
 while cursor<queue.size():
  var a: int=queue[cursor];cursor+=1
  for index in adjacency[a]:
   var bond: Dictionary=bonds[index]
   if bond.broken:continue
   var b: int=bond.b if bond.a==a else bond.a
   if not connected[b] and not released[b]:connected[b]=1;queue.append(b)
 var newly: Array=[]
 for i in points.size():
  if not connected[i] and not released[i]:newly.append(i);released[i]=1
 if not newly.is_empty():
  var position:=Vector3.ZERO;var motion:=Vector3.ZERO
  for i in newly:position+=points[i];motion+=velocity[i]
  release_events.append({'id':release_events.size(),'time':clock,'nodes':newly,'position':position/newly.size(),'velocity':motion/newly.size(),'size':clampf(sqrt(float(newly.size()))*.07*scale_factor,.02,.15)})
func _sample() -> void:
 if not record_history:return
 var broken:=PackedByteArray()
 for bond in bonds:broken.append(1 if bond.broken else 0)
 history.append({'time':clock,'points':points.duplicate(),'released':released.duplicate(),'broken':broken})
func displacement(rest_point: Vector3) -> Vector3:
 var v: float=clampf(rest_point.y/maxf(.001,pane_height)+.5,0,1)
 var half_width: float=pane_width*.5
 var u: float=clampf(rest_point.x/(2*half_width)+.5,0,1)
 var x: float=u*NX;var y: float=v*NY
 var ix: int=mini(floori(x),NX-1);var iy: int=mini(floori(y),NY-1)
 var a: int=iy*(NX+1)+ix;var tx: float=x-ix;var ty: float=y-iy
 return points[a].lerp(points[a+1],tx).lerp(points[a+NX+1].lerp(points[a+NX+2],tx),ty)
func visible(rest_point: Vector3) -> bool:
 var v: float=clampf(rest_point.y/maxf(.001,pane_height)+.5,0,1)
 var u: float=clampf(rest_point.x/maxf(.001,pane_width)+.5,0,1)
 var x: float=u*NX;var y: float=v*NY
 var ix: int=clampi(floori(x),0,NX-1);var iy: int=clampi(floori(y),0,NY-1)
 var a: int=iy*(NX+1)+ix
 var nodes: Array=[a,a+1,a+NX+1] if (x-ix)+(y-iy)<1 else [a+1,a+NX+2,a+NX+1]
 for node in nodes:
  if released[node]:return false
 for j in 3:
  var n0: int=nodes[j];var n1: int=nodes[(j+1)%3]
  var key: String='%d_%d'%[mini(n0,n1),maxi(n0,n1)]
  if bond_lookup.has(key) and bonds[bond_lookup[key]].broken:return false
 return true
func apply_frame(a: Dictionary,b: Dictionary,fraction: float) -> void:
 for i in points.size():points[i]=a.points[i].lerp(b.points[i],fraction)
 released=a.released.duplicate()
 for i in bonds.size():bonds[i].broken=bool(a.broken[i])
 clock=lerpf(a.time,b.time,fraction)
func broken_count() -> int:return bonds.filter(func(b):return b.broken).size()
