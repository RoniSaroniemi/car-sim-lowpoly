extends SceneTree
const Orbit=preload('res://arena/orbit_camera.gd')
var checks: Dictionary={}
var poses: Array=[]
var scene: Node
var atlas: Image
func _initialize() -> void:call_deferred('_run')
func _mouse(position_: Vector2,button: int,pressed_: bool) -> void:
 var event:=InputEventMouseButton.new();event.position=position_;event.global_position=position_;event.button_index=button;event.pressed=pressed_
 root.push_input(event,true)
func _motion(position_: Vector2,relative_: Vector2=Vector2.ZERO) -> void:
 var event:=InputEventMouseMotion.new();event.position=position_;event.global_position=position_;event.relative=relative_
 root.push_input(event,true)
func _frames() -> void:
 for i in 4:await process_frame
 await RenderingServer.frame_post_draw
func _snapshot(slot: int) -> void:
 var shot: Image=root.get_texture().get_image();shot.resize(640,400,Image.INTERPOLATE_LANCZOS);shot.convert(Image.FORMAT_RGB8)
 atlas.blit_rect(shot,Rect2i(0,0,640,400),Vector2i((slot%2)*640,(slot/2)*400))
func _run() -> void:
 scene=load('res://arena/colosseum.tscn').instantiate();root.add_child(scene);scene.set_physics_process(false)
 atlas=Image.create(1280,1200,false,Image.FORMAT_RGB8)
 await _frames()
 scene.camera_mode=1
 var outside:=Vector2(1000,650)
 _motion(outside);await _frames()
 var wanted_orbit: float=-1.0
 _mouse(outside,MOUSE_BUTTON_LEFT,true);_motion(outside,Vector2(wanted_orbit/.008,0));_mouse(outside,MOUSE_BUTTON_LEFT,false)
 await _frames()
 checks['actual_drag_changes_yaw']=absf(scene.orbit-wanted_orbit)<.001
 for index in 4:
  if index>0:
   _mouse(outside,MOUSE_BUTTON_LEFT,true);_motion(outside,Vector2((PI*.5)/.008,0));_mouse(outside,MOUSE_BUTTON_LEFT,false)
  await _frames()
  var target: Vector3=scene.car.solver.station_center(2)+Vector3.UP*.4
  var offset: Vector3=scene.camera.position-target
  var forward: Vector3=scene.car.forward()
  var expected_yaw: float=atan2(forward.z,forward.x)+index*PI*.5
  checks['cardinal_%d_unfolded'%index]=absf(angle_difference(atan2(offset.z,offset.x),expected_yaw))<.001 and absf(offset.length()-8)<.001
  poses.append({'relative_to_car_deg':index*90,'camera':str(scene.camera.position),'distance_m':offset.length(),'orbit':scene.orbit})
  _snapshot(index)
 # Full-circle mouse motion returns to the first ray rather than a folded side.
 _mouse(outside,MOUSE_BUTTON_LEFT,true);_motion(outside,Vector2((PI*.5)/.008,0));_mouse(outside,MOUSE_BUTTON_LEFT,false)
 await _frames()
 checks['full_circle_returns_same_yaw']=absf(angle_difference(scene.orbit,wanted_orbit))<.001
 for i in 30:_mouse(outside,MOUSE_BUTTON_WHEEL_UP,true)
 await _frames();checks['actual_wheel_min_limit']=scene.camera_distance==Orbit.MIN_DISTANCE;_snapshot(4)
 for i in 60:_mouse(outside,MOUSE_BUTTON_WHEEL_DOWN,true)
 await _frames();checks['actual_wheel_max_limit']=scene.camera_distance==Orbit.MAX_DISTANCE;_snapshot(5)
 _mouse(outside,MOUSE_BUTTON_LEFT,true);_motion(outside,Vector2(0,10000));_mouse(outside,MOUSE_BUTTON_LEFT,false)
 checks['actual_pitch_high_limit']=scene.camera_pitch==Orbit.MAX_PITCH
 _mouse(outside,MOUSE_BUTTON_LEFT,true);_motion(outside,Vector2(0,-10000));_mouse(outside,MOUSE_BUTTON_LEFT,false)
 checks['actual_pitch_low_limit']=scene.camera_pitch==Orbit.MIN_PITCH
 var before_zoom: float=scene.camera_distance;var before_yaw: float=scene.orbit
 var ui_position: Vector2=scene.power_control.get_global_rect().get_center()
 _motion(ui_position);await _frames()
 _mouse(ui_position,MOUSE_BUTTON_WHEEL_UP,true)
 _mouse(ui_position,MOUSE_BUTTON_LEFT,true);_motion(ui_position,Vector2(100,50));_mouse(ui_position,MOUSE_BUTTON_LEFT,false)
 await _frames()
 checks['gui_slider_does_not_orbit_or_zoom']=scene.camera_distance==before_zoom and scene.orbit==before_yaw
 var camera_key:=InputEventKey.new();camera_key.physical_keycode=KEY_C;camera_key.pressed=true;root.push_input(camera_key,true)
 checks['camera_cycle_resets_orbit_defaults']=scene.camera_mode==2 and scene.orbit==0 and scene.camera_pitch==.35 and scene.camera_distance==8
 scene.orbit=1;scene.camera_pitch=.8;scene.camera_distance=15;scene._reset()
 checks['repair_resets_orbit_defaults']=scene.orbit==0 and scene.camera_pitch==.35 and scene.camera_distance==8
 var graph: RefCounted=scene.car.solver
 var target:=Vector3(37,1.4,0);var wanted:=Vector3(45,4,0)
 var clipped: Vector3=Orbit.position(target,wanted,graph)
 checks['actual_box_occlusion_shortens_same_ray']=clipped.x<40 and (clipped-target).cross(wanted-target).length()<.001
 var clear: Vector3=Orbit.position(Vector3(-12,1,0),Vector3(-4,4,0),graph)
 checks['same_z_but_clear_box_ray_not_folded']=clear.distance_to(Vector3(-4,4,0))<.001
 target=Vector3(72,1.2,20);wanted=Vector3(82,2,20);clipped=Orbit.position(target,wanted,graph)
 checks['ring_occlusion_shortens_same_ray']=clipped.distance_to(target)<wanted.distance_to(target) and (clipped-target).cross(wanted-target).length()<.001
 var passed: bool=checks.values().all(func(v):return v)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://arena/evidence'))
 atlas.save_png('res://arena/evidence/camera_orbit.png')
 FileAccess.open('res://arena/evidence/camera_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'poses':poses,'scope':'Native-rendered scene; InputEventMouseButton/MouseMotion traverse viewport GUI/input routing. Atlas rows: 0/90deg,180/270deg,min/max zoom. No car physics retuned.'},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('ARENA_CAMERA_VERIFIED ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
