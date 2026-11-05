extends SceneTree
## Native evidence of the combined arena/widget/player, using actual car state.
var scene: Node
func _initialize() -> void:call_deferred('_run')
func _capture(name_: String) -> void:
 scene._process(0)
 var target: Vector3=scene.car.solver.station_center(2)+Vector3.UP*.35
 scene.camera.position=target+(Vector3(-6,3,5) if scene.car.baked_count>0 else Vector3(6,3,5));scene.camera.look_at(target)
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png('res://docs/images/'+name_+'.png')
func _run() -> void:
 scene=load('res://arena/colosseum.tscn').instantiate();root.add_child(scene)
 scene.set_physics_process(false);scene.set_process(false)
 await _capture('panels_arena_closed')
 for item in [['door_left',70],['door_right',70],['bonnet',65],['tailgate',85]]:
  scene.panel_controls._command(item[0],item[1])
 for tick in 120:scene.car.advance(1.0/120)
 await _capture('panels_arena_open')
 scene._start_head_on(120,20)
 for tick in 600:
  scene.car.advance(1.0/120)
  if scene.car.mode=='BAKED' and scene.car.crash_player.time>=.45:break
 assert(scene.car.baked_count==1 and scene.car.full_steps==0)
 await _capture('panels_arena_baked')
 print('ARENA_PANEL_PREVIEW_PASS actual_widget_and_bake=1 full_steps=',scene.car.full_steps)
 quit()
