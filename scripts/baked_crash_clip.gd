extends RefCounted
const PATH='res://bakes/frontal_120.crashclip'
const ANGLES=[0.0,20.0,-20.0]
static func case_id(angle: float,speed: float=120) -> String:
 var signed: float=wrapf(angle,-180,180)
 if absf(speed-120)<.001:
  if absf(signed)<.001:return 'frontal_120'
  if absf(signed-20)<.001:return 'front_left_20_120'
  if absf(signed+20)<.001:return 'front_right_20_120'
 return 'impact_%03d_%d' %[roundi(fposmod(angle,360)),roundi(speed)]
static func specifications(three_only: bool=false) -> Array:
 var cases: Array=[]
 for angle in ANGLES:cases.append({'angle':angle,'speed':120.0})
 if not three_only:
  for speed in [60.0,120.0]:
   for angle in range(0,360,30):
    if speed==120 and angle==0:continue
    cases.append({'angle':wrapf(angle,-180,180),'speed':speed})
  # Settled low-speed suspension rotates the 60° contact frame slightly.
  # Record the observed 75° coverage gap while preserving the zone/angle gates.
  cases.append({'angle':75.0,'speed':60.0})
 return cases
static func case_path(angle: float,speed: float=120) -> String:return 'res://bakes/'+case_id(angle,speed)+'.crashclip'
static func read_library() -> Array:
 var library: Array=[]
 for spec in specifications():
  var data: Dictionary=read(case_path(spec.angle,spec.speed))
  if not data.is_empty():library.append(data)
 var directory:=DirAccess.open('res://bakes')
 var extra_files: PackedStringArray=directory.get_files() if directory!=null else PackedStringArray()
 extra_files.sort()
 var ids: Array=library.map(func(clip):return clip.metadata.id)
 for name in extra_files:
  if name.ends_with('.crashclip') and name.get_basename() not in ids:
   var data: Dictionary=read('res://bakes/'+name)
   if not data.is_empty():library.append(data)
 return library

static func write_catalog() -> void:
 var records: Array=[]
 var directory:=DirAccess.open('res://bakes')
 var files:=directory.get_files();files.sort()
 for name in files:
  if not name.ends_with('.json') or name=='library.json':continue
  var meta: Variant=JSON.parse_string(FileAccess.get_file_as_string('res://bakes/'+name))
  if meta is Dictionary and meta.has('id'):
   records.append({'id':meta.id,'path':'res://bakes/'+meta.id+'.crashclip','heading_deg':meta.heading_deg,'speed_kmh':meta.speed_kmh,'contact_speed_mps':meta.signature.closing_speed_mps,'frames':meta.frame_count,'duration_s':meta.duration_s,'bytes':meta.clip_bytes,'zones':meta.signature.zones})
 FileAccess.open('res://bakes/library.json',FileAccess.WRITE).store_string(JSON.stringify({'version':1,'records':records},'\t'))

static func save(data: Dictionary,path: String='',update_catalog: bool=true) -> void:
 if path=='':path='res://bakes/'+str(data.metadata.id)+'.crashclip'
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
 var file:=FileAccess.open_compressed(path,FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD)
 assert(file!=null,'Cannot write crash clip')
 file.store_var(data)
 file.close()
 var metadata: Dictionary=data.metadata.duplicate(true)
 metadata['frame_count']=data.frames.size()
 metadata['clip_bytes']=FileAccess.get_file_as_bytes(path).size()
 FileAccess.open(path.get_basename()+'.json',FileAccess.WRITE).store_string(JSON.stringify(metadata,'\t'))
 if update_catalog:write_catalog()

static func read(path: String=PATH) -> Dictionary:
 if not FileAccess.file_exists(path):return {}
 var file:=FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_ZSTD)
 if file==null:return {}
 var value: Variant=file.get_var(false)
 return value if value is Dictionary else {}

static func local_frame(g: RefCounted,origin: Vector3) -> Dictionary:
 var state: Dictionary=g.capture()
 var positions: PackedVector3Array=state.points
 for i in positions.size():positions[i]-=origin
 state.points=positions
 return state

static func apply(g: RefCounted,data: Dictionary,time: float,origin: Vector3,rotation: Basis=Basis.IDENTITY) -> void:
 var frames: Array=data.frames
 var n: float=clampf(time*float(data.metadata.sample_hz),0,frames.size()-1)
 if absf(n-roundf(n))<1e-7:n=roundf(n)
 var a: Dictionary=frames[floori(n)]
 var b: Dictionary=frames[mini(ceili(n),frames.size()-1)]
 var t: float=n-floorf(n)
 var state: Dictionary=a.duplicate(true)
 var positions: PackedVector3Array=a.points.duplicate()
 var velocities: PackedVector3Array=a.velocities.duplicate()
 var damage: PackedFloat32Array=a.damage.duplicate()
 var contact: PackedFloat32Array=a.contact.duplicate()
 for i in positions.size():
  positions[i]=rotation*a.points[i].lerp(b.points[i],t)+origin
  velocities[i]=rotation*a.velocities[i].lerp(b.velocities[i],t)
  damage[i]=lerpf(a.damage[i],b.damage[i],t)
  contact[i]=lerpf(a.contact[i],b.contact[i],t)
 state.points=positions;state.velocities=velocities;state.damage=damage;state.contact=contact
 for i in state.wheels.size():
  state.wheels[i].rotation=(rotation.get_rotation_quaternion()*a.wheels[i].rotation.slerp(b.wheels[i].rotation,t)).normalized()
  state.wheels[i].angular_velocity=rotation*a.wheels[i].angular_velocity.lerp(b.wheels[i].angular_velocity,t)
  state.wheels[i].spin=lerp_angle(a.wheels[i].spin,b.wheels[i].spin,t)
 state.time=lerpf(a.time,b.time,t)
 g.restore(state,false)
 if g.effects!=null:g.effects.restore_interpolated(a.get('effects',{}),b.get('effects',{}),t)
