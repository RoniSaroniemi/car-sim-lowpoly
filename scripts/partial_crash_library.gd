extends RefCounted
## Separate bounded one-edge family; no implicit full-wall fallback.
const Clip=preload('res://scripts/baked_crash_clip.gd')
const DIRECTORY='res://bakes/partial'
static func case_id(angle: float,speed: float,side: String,overlap: float) -> String:
 return 'partial_%03d_%d_%s_%02d'%[roundi(fposmod(angle,360)),roundi(speed),side,roundi(overlap*100)]
static func specifications() -> Array:
 var cases: Array=[]
 for speed in [60.0,120.0]:
  for angle in [0.0,30.0,-30.0]:
   for side in ['left','right']:
    for overlap in [.25,.50,.75]:cases.append({'angle':angle,'speed':speed,'side':side,'overlap':overlap})
 # Measured first-corner changes at10° cannot safely use either the0° or30°
 # 75% clip without breaking the voxel or18°normal gate. Add only these4.
 for speed in [60.0,120.0]:
  cases.append({'angle':10.0,'speed':speed,'side':'right','overlap':.75})
  cases.append({'angle':-10.0,'speed':speed,'side':'left','overlap':.75})
 for speed in [60.0,120.0]:
  for spec in [[10.0,'left',.25],[-10.0,'right',.25],[20.0,'right',.50],[-20.0,'left',.50]]:
   cases.append({'angle':spec[0],'speed':speed,'side':spec[1],'overlap':spec[2]})
 return cases
static func read_library(directory: String=DIRECTORY) -> Array:
 var result: Array=[]
 var folder:=DirAccess.open(directory)
 if folder==null:return result
 var files:=folder.get_files();files.sort()
 for name in files:
  if not name.ends_with('.crashclip'):continue
  var data: Dictionary=Clip.read(directory+'/'+name)
  if not data.is_empty() and data.metadata.has('contact_coverage'):result.append(data)
 return result
static func write_catalog(directory: String=DIRECTORY) -> void:
 var records: Array=[]
 var folder:=DirAccess.open(directory)
 if folder==null:return
 var files:=folder.get_files();files.sort()
 for name in files:
  if not name.ends_with('.json') or name=='library.json':continue
  var metadata: Variant=JSON.parse_string(FileAccess.get_file_as_string(directory+'/'+name))
  if metadata is Dictionary and metadata.has('contact_coverage'):
   records.append({'id':metadata.id,'path':directory+'/'+metadata.id+'.crashclip','heading_deg':metadata.heading_deg,'speed_kmh':metadata.speed_kmh,'contact_coverage':metadata.contact_coverage,'frames':metadata.frame_count,'clip_bytes':metadata.clip_bytes})
 FileAccess.open(directory+'/library.json',FileAccess.WRITE).store_string(JSON.stringify({'schema':1,'family':'one_edge_barrier_box','records':records},'\t'))
