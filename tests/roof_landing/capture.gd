extends SceneTree
var scene: Node
var manifest: Array=[]
func _initialize() -> void:call_deferred('_run')
func _shot(label_: String) -> void:
 scene._process(0)
 var center: Vector3=scene.car.solver.station_center(2)
 var target: Vector3=center+Vector3.DOWN*.25
 scene.camera.position=target+Vector3(-4,1.2,5.5);scene.camera.look_at(target)
 for tick in 4:await process_frame
 await RenderingServer.frame_post_draw
 var path: String='res://docs/images/roof_landing_'+label_+'.png'
 root.get_texture().get_image().save_png(path)
 manifest.append({'label':label_,'path':path,'mode':scene.car.mode,'baked_count':scene.car.baked_count,'last_bake':scene.car.last_bake,'full_steps':scene.car.full_steps,'panel_steps':scene.car.solver.panels.active_steps,'membrane_steps':scene.car.solver.effects.glass.membrane_solve_steps,'cloth_steps':scene.car.solver.effects.interior.cloth_steps})
func _run() -> void:
 scene=load('res://arena/colosseum.tscn').instantiate();root.add_child(scene)
 scene.set_physics_process(false);scene.set_process(false)
 scene._start_roof_landing(15,7)
 await _shot('before')
 for tick in 120:
  scene.car.advance(1.0/120)
  if scene.car.mode=='BAKED' and scene.car.crash_player.time>=.35:break
 await _shot('impact')
 for tick in 230:scene.car.advance(1.0/120)
 await _shot('crushed')
 FileAccess.open('res://verification/roof_landing/captures.json',FileAccess.WRITE).store_string(JSON.stringify(manifest,'\t'))
 print('ROOF_LANDING_NATIVE_CAPTURE ',scene.car.baked_count,' full_steps=',scene.car.full_steps)
 quit()
