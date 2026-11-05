extends SceneTree
const Pose=preload('res://scripts/roof_landing_geometry.gd')
const PanelState=preload('res://scripts/panel_snapshot.gd')
var scene: Node
var evidence: Array=[]
func _initialize():call_deferred('_run')
func shot(label_: String) -> void:
 scene._process(0)
 var center: Vector3=scene.car.solver.station_center(2)
 scene.camera.position=center+Vector3(-5,2,5.5);scene.camera.look_at(center)
 for tick in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png('res://docs/images/world_damage_'+label_+'.png')
 evidence.append({'label':label_,'impacts':scene.car.baked_count,'history':scene.car.impact_history,'full_steps':scene.car.full_steps,'body_steps':scene.car.solver.step_count,'cage_steps':scene.car.solver.panels.active_steps,'membrane_steps':scene.car.solver.effects.glass.membrane_solve_steps,'cloth_steps':scene.car.solver.effects.interior.cloth_steps})
func _run() -> void:
 scene=load('res://arena/colosseum.tscn').instantiate();root.add_child(scene);scene.set_process(false);scene.set_physics_process(false)
 var car: RefCounted=scene.car;car.reset(60,Vector3(69,0,0));car.solver.barrier_enabled=false
 for tick in 150:
  car.advance(1./120)
  if car.mode=='BAKED' and car.crash_player.time>.7:break
 await shot('arena_wall')
 for tick in 420:car.advance(1./120)
 var g: RefCounted=car.solver;var center: Vector3=g.station_center(2)
 var rotation:=Basis(Vector3.RIGHT,PI)*Pose.basis(g).transposed();var location:=Vector3(-30,4,0)
 var state: Dictionary=PanelState.transformed(g.panels.capture(),rotation,location-rotation*center)
 for i in g.points.size():g.points[i]=rotation*(g.points[i]-center)+location;g.velocities[i]=Vector3(20,-1.5,0)
 for wheel in g.wheels.wheels:wheel.rotation=(rotation.get_rotation_quaternion()*wheel.rotation).normalized();wheel.previous_rotation=wheel.rotation
 g.panels.restore(state);g.panels.synchronize_inactive()
 var gap: float=Pose.minimum_gap(g)
 for i in g.points.size():g.points[i].y+=.08-gap
 g.panels.synchronize_inactive();g.effects.synchronize();car.compact.capture_shape()
 for tick in 300:
  car.advance(1./120)
  if car.baked_count>=2 and car.mode=='BAKED' and car.crash_player.time>1.2:break
 await shot('wall_then_roof')
 FileAccess.open('res://verification/world_damage/captures.json',FileAccess.WRITE).store_string(JSON.stringify(evidence,'\t'))
 print('WORLD_DAMAGE_NATIVE impacts=',car.baked_count,' full=',car.full_steps)
 quit()
