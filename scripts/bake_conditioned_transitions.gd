extends SceneTree
const Author=preload('res://scripts/conditioned_crash_authoring.gd')
const States=preload('res://scripts/conditioned_crash_transitions.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var prefix_path: String=Clip.case_path(0,60)
 var output: String=States.DIRECTORY
 var chain: String=Author.CHAIN_ID
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with('--prefix='):prefix_path=argument.trim_prefix('--prefix=')
  if argument.begins_with('--output='):output=argument.trim_prefix('--output=')
  if argument.begins_with('--chain='):chain=argument.trim_prefix('--chain=')
 var prefix: Dictionary=Clip.read(prefix_path)
 if prefix.is_empty():push_error('Bake the standard60km/h frontal first');quit(1);return
 var clips: Array=Author.build(prefix,chain)
 if clips.size()!=3:quit(1);return
 States.save_library(clips,output)
 print('CONDITIONED_BANK_SAVED count=',clips.size(),' directory=',output)
 quit()
