extends SceneTree
const Recorder=preload('res://scripts/partial_crash_recorder.gd')
const Library=preload('res://scripts/partial_crash_library.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var directory: String=Library.DIRECTORY
 var quality:=4
 var wanted:=PackedStringArray()
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with('--directory='):directory=argument.trim_prefix('--directory=')
  if argument.begins_with('--quality='):quality=int(argument.trim_prefix('--quality='))
  if argument.begins_with('--only='):wanted=argument.trim_prefix('--only=').split(',')
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
 for spec in Library.specifications():
  var id: String=Library.case_id(spec.angle,spec.speed,spec.side,spec.overlap)
  if not wanted.is_empty() and id not in wanted:continue
  var recorder:=Recorder.new();recorder.quality_multiplier=quality
  recorder.start_partial(spec.angle,spec.speed,spec.side,spec.overlap)
  var watchdog:=0
  while not recorder.completed and watchdog<40000:recorder.step();watchdog+=1
  if recorder.result.is_empty():push_error('Partial recording failed '+id);quit(1);return
  Clip.save(recorder.result,directory+'/'+id+'.crashclip',false)
  print('PARTIAL_BAKED ',id,' coverage=',JSON.stringify(recorder.initial_coverage),' cpu_ms=',recorder.cpu_us/1000.0)
 if '--no-index' not in OS.get_cmdline_user_args():Library.write_catalog(directory)
 quit()
