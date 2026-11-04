extends SceneTree
func _initialize() -> void:call_deferred('_start')
func _start() -> void:
 var viewport:=SubViewport.new()
 viewport.size=Vector2i(1440,900)
 viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 root.add_child(viewport)
 viewport.add_child(load('res://driving.tscn').instantiate())
