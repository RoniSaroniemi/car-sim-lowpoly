extends SceneTree
const Recorder=preload('res://scripts/roof_crash_recorder.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var speed:=35.0;var quality:=4;var cases: Array=Recorder.CASES.duplicate()
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with('--speed='):speed=float(argument.trim_prefix('--speed='))
  elif argument.begins_with('--quality='):quality=int(argument.trim_prefix('--quality='))
  elif argument.begins_with('--case='):cases=[argument.trim_prefix('--case=')]
 for case_name in cases:
  var recorder:=Recorder.new();recorder.start(case_name,speed,quality)
  while not recorder.completed:recorder.step()
  var path: String='res://bakes/roof/'+recorder.result.metadata.id+'.crashclip'
  Clip.save(recorder.result,path)
  print('ROOF_CLIP_BAKED ',recorder.result.metadata.id,' frames=',recorder.frames.size(),' physics_hz=',recorder.result.metadata.physics_hz,' first_gap_m=',recorder.first_contact_gap_m,' cpu_ms=',recorder.cpu_us/1000.0)
 var catalog: Array=[]
 var directory:=DirAccess.open('res://bakes/roof')
 var names:=directory.get_files();names.sort()
 for name in names:
  if not name.ends_with('.json') or name=='library.json':continue
  var metadata: Variant=JSON.parse_string(FileAccess.get_file_as_string('res://bakes/roof/'+name))
  if metadata is Dictionary and metadata.get('family','')=='roof_floor':
   catalog.append({'id':metadata.id,'family':'roof_floor','path':'res://bakes/roof/'+metadata.id+'.crashclip','speed_kmh':metadata.speed_kmh,'physics_hz':metadata.physics_hz,'material_profile':metadata.material_profile,'contact_rotation_xyzw':metadata.contact_rotation_xyzw,'signature':metadata.signature})
 FileAccess.open('res://bakes/roof/library.json',FileAccess.WRITE).store_string(JSON.stringify({'version':1,'family':'roof_floor','records':catalog},'\t'))
 quit()
