extends SceneTree
# Render actual probe frames in a GPU SubViewport with the main window minimised.
func _initialize() -> void:
 call_deferred('_start')

func _start() -> void:
 DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
 var viewport := SubViewport.new()
 viewport.size = Vector2i(1440,960)
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 root.add_child(viewport)
 var scene: Node = load('res://main.tscn').instantiate()
 viewport.add_child(scene)
