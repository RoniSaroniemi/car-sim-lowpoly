extends SceneTree
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var scene:=Node3D.new();scene.set_script(load('res://scripts/probe_vehicle_glass.gd'))
 if '--capture-glass-car' in OS.get_cmdline_user_args():
  var viewport:=SubViewport.new();viewport.size=Vector2i(1440,900);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport);viewport.add_child(scene)
 else:root.add_child(scene)
