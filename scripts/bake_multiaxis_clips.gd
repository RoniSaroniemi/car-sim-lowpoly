extends SceneTree
const Recorder=preload('res://scripts/multiaxis_crash_recorder.gd')
const Cases=preload('res://scripts/multiaxis_crash_cases.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var speeds: Array=[60,120];var quality:=4;var only: Array=[];var no_index:=false;var index_only:=false;var list_only:=false;var skip_valid:=false;var output: String='res://bakes/multiaxis'
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with('--speed='):
   speeds=[]
   for speed in argument.trim_prefix('--speed=').split(','):speeds.append(float(speed))
  elif argument.begins_with('--quality='):quality=int(argument.trim_prefix('--quality='))
  elif argument.begins_with('--only='):only=Array(argument.trim_prefix('--only=').split(','))
  elif argument.begins_with('--output='):output=argument.trim_prefix('--output=').trim_suffix('/')
  elif argument=='--no-index':no_index=true
  elif argument=='--index-only':index_only=true
  elif argument=='--list':list_only=true
  elif argument=='--skip-valid':skip_valid=true
 if quality not in [1,2,4]:push_error('Quality must be 1, 2 or 4');quit(2);return
 var specs: Array=[]
 for spec in Cases.specifications(speeds):
  if only.is_empty() or spec.key in only or spec.id in only:specs.append(spec)
 if specs.is_empty():push_error('No matching multiaxis cases');quit(2);return
 if list_only:
  print(JSON.stringify({'family':'multiaxis_floor','count':specs.size(),'cases':specs},'\t'));quit();return
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
 if not index_only:
  for spec in specs:
   var path: String=output+'/'+spec.id+'.crashclip'
   if skip_valid and FileAccess.file_exists(path):
    var existing: Dictionary=Clip.read(path)
    if existing.frames.size()==301 and existing.metadata.get('physics_hz',0)==480*quality and Clip.input_compatibility(existing).compatible:
     print('MULTIAXIS_CLIP_REUSED ',spec.id);continue
   var recorder:=Recorder.new();recorder.start(spec.key,spec.speed_kmh,quality)
   while not recorder.completed:recorder.step()
   if not recorder.error.is_empty():quit(1);return
   Clip.save(recorder.result,path,false)
   print('MULTIAXIS_CLIP_BAKED ',spec.id,' frames=',recorder.frames.size(),' physics_hz=',recorder.result.metadata.physics_hz,' first_gap_m=',recorder.first_gap,' contact=',JSON.stringify(recorder.signature.first_contacts),' authoring_wall_ms=',recorder.result.metadata.authoring_step_wall_ms,' simulation_wall_ms=',recorder.result.metadata.simulation_call_wall_ms,' total_wall_ms=',recorder.result.metadata.total_wall_ms)
 if not no_index:write_catalog(output)
 quit()
static func write_catalog(output: String) -> void:
 var records: Array=[];var directory:=DirAccess.open(output);var names:=directory.get_files();names.sort()
 for name in names:
  if not name.ends_with('.json') or name=='library.json':continue
  var metadata: Variant=JSON.parse_string(FileAccess.get_file_as_string(output+'/'+name))
  if metadata is Dictionary and metadata.get('family','')=='multiaxis_floor':
   records.append({'id':metadata.id,'family':metadata.family,'path':output+'/'+metadata.id+'.crashclip','direction_key':metadata.direction_key,'fixture_descriptor':metadata.fixture_descriptor,'speed_kmh':metadata.speed_kmh,'physics_hz':metadata.physics_hz,'material_profile':metadata.material_profile,'contact_rotation_xyzw':metadata.contact_rotation_xyzw,'signature':metadata.signature,'total_wall_ms':metadata.total_wall_ms})
 FileAccess.open(output+'/library.json',FileAccess.WRITE).store_string(JSON.stringify({'version':1,'family':'multiaxis_floor','coverage':'18 directions x 60/120 km/h, separate explicit selection; not the horizontal runtime matcher','records':records},'\t'))
