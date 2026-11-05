extends SceneTree
const Cases=preload('res://scripts/roof_landing_cases.gd')
const Recorder=preload('res://scripts/roof_landing_recorder.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var only: String='';var quality:=4
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with('--only='):only=arg.trim_prefix('--only=')
  if arg.begins_with('--quality='):quality=int(arg.trim_prefix('--quality='))
 for spec in Cases.specifications():
  if not only.is_empty() and spec.id!=only:continue
  var began:=Time.get_ticks_usec();var author:=Recorder.new();author.start_landing(spec,quality)
  while not author.completed:author.step()
  if not author.error.is_empty():quit(1);return
  Clip.save(author.result,Cases.DIRECTORY+'/'+spec.id+'.crashclip',false)
  print('ROOF_LANDING_BAKED ',spec.id,' frames=',author.frames.size(),' wall_s=',(Time.get_ticks_usec()-began)/1000000.0,' energy=',author.result.metadata.final_outcome.body_metrics.kinetic_kj)
 quit()
