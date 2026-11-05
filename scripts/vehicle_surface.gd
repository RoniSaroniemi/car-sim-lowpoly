extends RefCounted
## Cosmetic rest-space state. Never changes graph, mass, contacts or constraints.
const VERSION=1
const CAP=8
var graph: WeakRef
var enabled:=true
var parameters: Dictionary={}
var damage:=PackedFloat32Array()
var contact:=PackedFloat32Array()
var compression:=PackedFloat32Array()
var marks: Array=[]
var revision:=0
var observations:=0
var accumulator:=0.
var active_mark: String=''
var next_id:=0
var last_change: float=-INF
var serial_prefix: String='live'

func setup(owner: RefCounted,options: Dictionary={}) -> void:
 graph=weakref(owner);enabled=options.get('enabled',true)
 var path: String=options.get('preset','res://vehicles/niva_surface.json')
 if FileAccess.file_exists(path):parameters=JSON.parse_string(FileAccess.get_file_as_string(path))
 reset()

func reset() -> void:
 damage.resize(38);damage.fill(0);contact.resize(38);contact.fill(0);compression.resize(38);compression.fill(0)
 marks.clear();revision+=1;accumulator=0;active_mark='';next_id=0;last_change=-INF;serial_prefix='live'

func resume_live() -> void:
 active_mark='';last_change=-INF;serial_prefix='live'

func step_live(dt: float) -> void:
 if not enabled:return
 accumulator+=dt
 if accumulator+1e-8<1./120.:return
 accumulator=fmod(accumulator,1./120.)
 observe()

func observe() -> void:
 var g: RefCounted=graph.get_ref()
 if g==null or not enabled:return
 var lengths:=PackedFloat32Array()
 for edge in g.links:lengths.append(edge.length)
 var direction:=Vector3.ZERO
 for node in 28:
  if g.contact_wall[node]:direction-=g.wall_normals[node]
  if g.contact_floor[node]:direction-=g.floor_normals[node]
 if direction.length()>.001:
  var x: Vector3=(g.station_center(6)-g.station_center(0)).normalized()
  var z: Vector3=(g.points[13]-g.points[12]).normalized();z=(z-x*x.dot(z)).normalized()
  if x.length()>.5 and z.length()>.5:direction=Basis(x,z.cross(x).normalized(),z).transposed()*direction.normalized()
 else:direction=Vector3.RIGHT
 observe_frame({'damage':g.node_damage,'contact':g.node_contact,'lengths':lengths,'points':g.points,'time':g.simulated_time},direction)

func observe_frame(frame: Dictionary,direction: Vector3,hits: Array=[]) -> void:
 var g: RefCounted=graph.get_ref()
 var changed:=false
 for node in 38:
  var d: float=maxf(damage[node],frame.damage[node]);var c: float=maxf(contact[node],frame.contact[node])
  changed=changed or d>damage[node]+.00001 or c>contact[node]+.00001
  damage[node]=d;contact[node]=c
 for i in g.links.size():
  var edge= g.links[i]
  if edge.a>=28 or edge.b>=28:continue
  var strain: float=maxf(0.,1.-float(frame.lengths[i])/maxf(.001,edge.original))
  for node in [edge.a,edge.b]:
   changed=changed or strain>compression[node]+.00001;compression[node]=maxf(compression[node],strain)
 observations+=1
 if not changed:return
 var center:=Vector3.ZERO;var total:=0.
 for node in 28:
  var w: float=pow(contact[node],2.)*pow(damage[node],1.5)*(.12+compression[node])
  center+=g.rest[node]*w;total+=w
 if total>.00001:center/=total
 else:
  var count:=0
  for node in hits:
   if int(node)<28:center+=g.rest[int(node)];count+=1
  if count>0:center/=count
  else:
   for node in 28:
    var w: float=damage[node]*compression[node];center+=g.rest[node]*w;total+=w
   if total>.00001:center/=total
 var variance:=Vector3.ZERO
 if total>.00001:
  for node in 28:
   var w: float=pow(contact[node],2.)*pow(damage[node],1.5)*(.12+compression[node])
   var delta: Vector3=g.rest[node]-center;variance+=delta*delta*w
  variance/=total
 var radii:=Vector3(sqrt(variance.x),sqrt(variance.y),sqrt(variance.z))*1.35+Vector3(.58,.56,.58)
 var p: PackedVector3Array=frame.points
 var front: float=(_station(g.rest,6)-_station(g.rest,3)).length()-(_station(p,6)-_station(p,3)).length()
 var cabin: float=(_station(g.rest,3)-_station(g.rest,1)).length()-(_station(p,3)-_station(p,1)).length()
 var width: float=((g.rest[9]-g.rest[8]).length()+(g.rest[13]-g.rest[12]).length()-(p[9]-p[8]).length()-(p[13]-p[12]).length())*.5
 var roof: float=1.2-((p[10]+p[11])-(p[8]+p[9])).length()*.5
 var strength: float=clampf((maxf(maxf(front,cabin),maxf(width,roof))-.015)/.40,0.,1.)
 if strength<.005 or Array(damage).max()<.01:
  revision+=1;return
 var clock: float=frame.get('time',0.)
 if active_mark=='' or clock-last_change>.25:
  next_id+=1;active_mark=serial_prefix+':'+str(next_id)
 var mark: Dictionary={'id':active_mark,'center':center,'radii':radii,'strength':strength,'direction':direction.normalized()}
 _merge_mark(mark)
 last_change=clock;revision+=1

static func _station(p: PackedVector3Array,i: int) -> Vector3:
 return (p[i*4]+p[i*4+1]+p[i*4+2]+p[i*4+3])*.25

func _merge_mark(incoming: Dictionary) -> void:
 for existing in marks:
  if existing.id!=incoming.id:continue
  # Keep the seed/centre fixed. Expanding radii and peak strength cannot heal
  # an earlier part of this footprint, even while the impact centre develops.
  existing.radii=existing.radii.max((incoming.center-existing.center).abs()+incoming.radii)
  existing.strength=maxf(existing.strength,incoming.strength)
  return
 if marks.size()<CAP:marks.append(incoming.duplicate(true));return
 # Bound the shader cost without dropping old marks. Merge an overflow into
 # the nearest fixed centre, growing its support monotonically.
 var nearest: int=0
 for index in marks.size():
  if marks[index].center.distance_squared_to(incoming.center)<marks[nearest].center.distance_squared_to(incoming.center):nearest=index
 var existing: Dictionary=marks[nearest]
 existing.radii=existing.radii.max((incoming.center-existing.center).abs()+incoming.radii)
 existing.strength=maxf(existing.strength,incoming.strength)

func capture() -> Dictionary:
 return {'version':VERSION,'damage':damage.duplicate(),'contact':contact.duplicate(),'compression':compression.duplicate(),'marks':marks.duplicate(true),'next_id':next_id,'active_mark':active_mark,'last_change':last_change,'serial_prefix':serial_prefix}

static func valid_state(state: Dictionary) -> bool:
 if int(state.get('version',0))!=VERSION:return false
 for key in ['damage','contact','compression']:
  if not state.get(key) is PackedFloat32Array or state[key].size()!=38:return false
  for value in state[key]:
   if not is_finite(value) or value<0. or value>1.0001:return false
 if not state.get('marks') is Array or state.marks.size()>CAP:return false
 for mark in state.marks:
  if not mark is Dictionary:return false
  for key in ['center','radii','direction']:
   if not mark.get(key) is Vector3 or not mark[key].is_finite():return false
  if mark.radii.x<=0. or mark.radii.y<=0. or mark.radii.z<=0.:return false
  if not mark.has('id') or not is_finite(float(mark.get('strength',NAN))):return false
 return true

func restore(state: Dictionary) -> void:
 if not valid_state(state):return
 damage=state.damage.duplicate();contact=state.contact.duplicate();compression=state.compression.duplicate();marks=state.marks.duplicate(true)
 next_id=state.get('next_id',0);active_mark=state.get('active_mark','');last_change=state.get('last_change',-INF);serial_prefix=state.get('serial_prefix','live')
 revision+=1

func retain(prior: Dictionary) -> void:
 if int(prior.get('version',0))!=VERSION:return
 for node in 38:
  damage[node]=maxf(damage[node],prior.damage[node]);contact[node]=maxf(contact[node],prior.contact[node]);compression[node]=maxf(compression[node],prior.compression[node])
 for mark in prior.marks:_merge_mark(mark)
 revision+=1

static func build_track(owner: RefCounted,clip: Dictionary) -> Array:
 var field=load('res://scripts/vehicle_surface.gd').new();field.setup(owner,{'enabled':true})
 field.serial_prefix='clip:'+str(clip.metadata.id)
 var normal: Array=clip.metadata.get('signature',{}).get('normal',[-1,0,0])
 var direction: Vector3=-Vector3(normal[0],normal[1],normal[2])
 var track: Array=[]
 for frame in clip.frames:
  var saved: Dictionary=frame.get('effects',{}).get('surface',{})
  if not saved.is_empty():
   if not valid_state(saved):return []
   field.restore(saved)
  else:field.observe_frame(frame,direction,clip.metadata.get('signature',{}).get('hit_nodes',[]))
  track.append(field.capture())
 return track
