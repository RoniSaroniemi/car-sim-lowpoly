extends SceneTree
const Recorder=preload('res://scripts/crash_bake_recorder.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 if '--index-only' in OS.get_cmdline_user_args():
  Clip.write_catalog();print('CRASH_LIBRARY_INDEXED');quit();return
 for spec in Clip.specifications('--three-only' in OS.get_cmdline_user_args()):
  var recorder=Recorder.new()
  recorder.start(spec.angle,spec.speed)
  while not recorder.completed:recorder.step()
  Clip.save(recorder.result)
  print('CRASH_CLIP_BAKED id=',recorder.result.metadata.id,' frames=',recorder.frames.size(),' steps=',recorder.full_steps,' cpu_ms=',recorder.cpu_us/1000.0,' zones=',JSON.stringify(recorder.signature.zones))
 quit()
