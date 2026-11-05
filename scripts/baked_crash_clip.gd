extends RefCounted
const PanelState=preload('res://scripts/panel_snapshot.gd')
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
 if not data.frames.is_empty() and data.frames[0].has('panels'):data.metadata['panels_schema']=PanelState.SCHEMA
 if not data.frames.is_empty() and data.frames[0].get('effects',{}).has('surface'):
  data.metadata['surface_schema']=1
  var fingerprints: Dictionary={}
  for source in ['scripts/vehicle_surface.gd','scripts/damage_layers.gdshader','scripts/damage_skin.gd','scripts/layered_damage_skin.gd','vehicles/niva_surface.json']:
   fingerprints[source]=FileAccess.get_sha256('res://'+source)
  data.metadata['surface_input_sha256']=fingerprints
 var file:=FileAccess.open_compressed(path,FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD)
 assert(file!=null,'Cannot write crash clip')
 # Derived playback tracks are memory caches, never part of the saved clip.
 file.store_var({'metadata':data.metadata,'frames':data.frames})
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
 if not value is Dictionary:return {}
 if int(value.get('metadata',{}).get('surface_schema',0))>1:
  push_warning('Unsupported surface schema: '+path);return {}
 if int(value.get('metadata',{}).get('panels_schema',0))>PanelState.SCHEMA:return {}
 return value

static func local_frame(g: RefCounted,origin: Vector3) -> Dictionary:
 var state: Dictionary=g.capture()
 var positions: PackedVector3Array=state.points
 for i in positions.size():positions[i]-=origin
 state.points=positions
 if state.has('panels'):state.panels=PanelState.transformed(state.panels,Basis.IDENTITY,-origin)
 return state

static func apply(g: RefCounted,data: Dictionary,time: float,origin: Vector3,rotation: Basis=Basis.IDENTITY) -> void:
 if g.panels_runtime_enabled and not data.frames[0].has('panels'):
  if g.panels.panels.any(func(p):return p.active or not p.latched or p.plastic_work>.01 or p.anchors.any(func(a):return a.broken)):
   push_warning('Historical closed-body clip cannot replace independent/damaged panels');return
  g.panels.playback=false
 if g.effects!=null and not prepare_surfaces(g,data):return
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
 if a.has('panels') and g.panels_runtime_enabled:
  state.panels=PanelState.transformed(PanelState.interpolated(a.panels,b.panels,t),rotation,origin)
  g.panels.playback=true
 g.restore(state,false)
 if g.effects!=null:
  g.effects.restore_interpolated(a.get('effects',{}),b.get('effects',{}),t)
  # Discrete cumulative cosmetic events are sampled at the earlier frame.
  # This is deterministic for backward/random seeking and never runs physics.
  g.effects.surface.restore(data._surface_track[floori(n)])

static func prepare_surfaces(g: RefCounted,data: Dictionary) -> bool:
 if not data.has('_surface_track'):
  data['_surface_track']=load('res://scripts/vehicle_surface.gd').build_track(g,data)
 return data._surface_track.size()==data.frames.size()

static func input_compatibility(data: Dictionary) -> Dictionary:
 # Retain historical provenance. Only exact reviewed cosmetic adapter revisions
 # are compatible; all physical/source inputs otherwise require exact hashes.
 var path: String='res://bakes/surface_adapter_compatibility.json'
 var receipt: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
 var changes: Array=[];var rejected: Array=[]
 for source in data.metadata.get('input_sha256',{}):
  var recorded: String=data.metadata.input_sha256[source]
  var current: String=FileAccess.get_sha256('res://'+source)
  if recorded==current:continue
  changes.append(source)
  var entry: Dictionary=receipt.get('adapters',{}).get(source,{})
  if entry.get('current','')!=current or recorded not in entry.get('recorded',[]):rejected.append(source)
 return {'compatible':rejected.is_empty() and data.metadata.has('input_sha256'),'exact':changes.is_empty(),'cosmetic_adapter_changes':changes,'rejected':rejected}
