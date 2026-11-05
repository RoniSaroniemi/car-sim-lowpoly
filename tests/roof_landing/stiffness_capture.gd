extends SceneTree
var scene: Node
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 scene=load('res://arena/colosseum.tscn').instantiate();root.add_child(scene)
 scene.set_physics_process(false);scene.set_process(false)
 scene.car.set_roof_stiffness(3);scene.roof_control.value=3
 scene._start_roof_landing(0,4)
 for tick in 200:scene.car.advance(1./120)
 scene._process(0)
 var center: Vector3=scene.car.solver.station_center(2)
 scene.camera.position=center+Vector3(-5,2,5.5);scene.camera.look_at(center)
 for tick in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png('res://docs/images/roof_stiffness_control.png')
 print('ROOF_STIFFNESS_NATIVE value=',scene.car.roof_stiffness,' impacts=',scene.car.baked_count,' full_steps=',scene.car.full_steps)
 quit()
