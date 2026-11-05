extends SceneTree
const Recorder=preload('res://scripts/crash_bake_recorder.gd')
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var recorder:=Recorder.new();recorder.start(0,20)
 while not recorder.completed:recorder.step()
 var path: String='res://probes/damage_surfaces/data/light_20.crashclip'
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
 var file:=FileAccess.open_compressed(path,FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD)
 file.store_var(recorder.result);file.close()
 print('LIGHT_CASE_RECORDED ',JSON.stringify(recorder.vehicle.solver.metrics()))
 quit()
