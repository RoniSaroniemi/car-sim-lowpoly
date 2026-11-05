extends SceneTree
var sandbox: Node3D
var busy:=false
var stage:=0
var ticks:=0
var live:=false
var reports: Array=[]
const OUT='res://verification/damage_surface/'
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 root.size=Vector2i(1440,900)
 auto_accept_quit=false
 Engine.max_fps=60
 live='--surface-live' in OS.get_cmdline_user_args()
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 sandbox=load('res://driving.tscn').instantiate();root.add_child(sandbox)
 sandbox.set_process_unhandled_input(false);sandbox.set_process_unhandled_key_input(false)
 if live:
  sandbox.vehicle.baked_enabled=false;sandbox._start_head_on(60.,30.)
 else:sandbox._start_baked_sequence()
func _process(_dt: float) -> bool:
 if sandbox==null or busy:return false
 ticks+=1
 var car: RefCounted=sandbox.vehicle
 if ticks>15000:push_error('Surface journey timed out');quit(1);return false
 if live:
  if sandbox.elapsed>3.5 and stage==0:
   stage=1;_finish('live_oblique')
  return false
 if car.mode=='BAKED' and car.crash_player.time>1.0 and car.baked_count>stage:
  stage=car.baked_count;_capture('baked_hit_%d'%stage)
 elif car.baked_count==3 and car.last_bake.get('completed',false):_finish('resumed_driving')
 return false
func _capture(label: String) -> void:
 busy=true;sandbox.set_physics_process(false)
 sandbox._process(0.)
 sandbox.set_process(false)
 var car: RefCounted=sandbox.vehicle;var g: RefCounted=car.solver
 var target: Vector3=g.station_center(2)+Vector3(0,.2,0)
 var front: Vector3=car.forward();var side:=Vector3(-front.z,0,front.x)
 sandbox.camera.position=target+front*4.+side*5.+Vector3(0,2.6,0)
 if sandbox.camera.position.x>g.barrier_min.x-.6 and target.x<g.barrier_min.x:sandbox.camera.position.x=g.barrier_min.x-.6
 sandbox.camera.fov=45;sandbox.camera.look_at(target)
 sandbox.view.update_pose()
 await RenderingServer.frame_post_draw
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OUT+label+'.png')
 var surface: RefCounted=car.solver.effects.surface
 reports.append({'label':label,'surface':surface.capture(),'solver_steps':car.solver.step_count,'glass_solves':car.solver.effects.glass.membrane_solve_steps,'interior_solves':car.solver.effects.interior.cloth_steps,'baked_count':car.baked_count,'triangles':sandbox.view.mesh_triangles})
 print('DAMAGE_JOURNEY_CAPTURE ',label,' marks=',surface.marks.size())
 sandbox.set_process(true);sandbox.set_physics_process(true);busy=false
func _finish(label: String) -> void:
 busy=true
 await _capture(label)
 busy=true;sandbox.set_physics_process(false)
 sandbox.set_process(false)
 sandbox.view.detail_enabled=false;sandbox.view.set_mode(2)
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OUT+label+'_geometry.png')
 sandbox.view.detail_enabled=true;sandbox.view.set_mode(2)
 sandbox._reset();sandbox.orbit=-.65;sandbox._process(0.)
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(OUT+label+'_repaired.png')
 var cleared: bool=sandbox.vehicle.solver.effects.surface.marks.is_empty()
 FileAccess.open(OUT+('live' if live else 'baked')+'_journey.json',FileAccess.WRITE).store_string(JSON.stringify({'completed_at':Time.get_unix_time_from_system(),'repair_cleared':cleared,'runs':reports},'\t'))
 print('DAMAGE_JOURNEY_COMPLETE ',('live' if live else 'baked'),' repair=',cleared)
 quit(0 if cleared else 1)
