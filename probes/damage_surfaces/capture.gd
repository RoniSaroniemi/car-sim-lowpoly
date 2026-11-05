extends SceneTree
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 root.size=Vector2i(1920,1080)
 root.add_child(load('res://probes/damage_surfaces/probe.tscn').instantiate())
