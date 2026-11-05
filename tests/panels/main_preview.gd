extends 'res://scripts/driving_sandbox.gd'
var recorded_inspection:=false
var inside_inspection:=false
func _ready() -> void:
 super._ready()
 DisplayServer.window_set_title('Niva MAIN panel integration — preview')
 vehicle.set_panel_open('door_left',70);vehicle.set_panel_open('door_right',55)
 vehicle.set_panel_open('bonnet',45);vehicle.set_panel_open('tailgate',70)
 camera_mode=1
 if '--capture-panel-crash' in OS.get_cmdline_user_args():
  recorded_inspection=true
  var clip: Dictionary=load('res://scripts/baked_crash_clip.gd').read('user://main_panel_author.crashclip')
  assert(not clip.is_empty())
  load('res://scripts/baked_crash_clip.gd').apply(vehicle.solver,clip,1.2,Vector3(0,clip.metadata.origin[1],0))
  vehicle.mode='BAKED';camera_mode=1
  await get_tree().create_timer(.5).timeout
  RenderingServer.force_draw(false)
  get_viewport().get_texture().get_image().save_png('res://tests/panels/main_deformed.png')
  print('PANEL_MAIN_DEFORMED_RENDER ',view.panel_quality())
  get_tree().quit()
 if '--capture-panels' in OS.get_cmdline_user_args():
  await get_tree().create_timer(4).timeout
  RenderingServer.force_draw(false)
  get_viewport().get_texture().get_image().save_png('res://tests/panels/main_open.png')
  print('PANEL_MAIN_RENDER ',view.panel_quality(),' full=',vehicle.full_steps,' cage=',vehicle.solver.panels.active_steps)
  get_tree().quit()
 if '--capture-panel-inside' in OS.get_cmdline_user_args():
  await get_tree().create_timer(3).timeout
  inside_inspection=true
  await get_tree().create_timer(.3).timeout
  RenderingServer.force_draw(false)
  get_viewport().get_texture().get_image().save_png('res://tests/panels/main_inside.png')
  get_tree().quit()
func _physics_process(dt: float) -> void:
 if not recorded_inspection:super._physics_process(dt)
func _process(dt: float) -> void:
 super._process(dt)
 if recorded_inspection:
  var center: Vector3=vehicle.solver.station_center(2)
  camera.position=center+Vector3(5,3,-5);camera.look_at(center+Vector3(.2,.4,0))
 if inside_inspection:
  camera.position=vehicle.solver.station_center(2)+Vector3(.15,0,0);camera.position.y=1.35
  camera.look_at(vehicle.panel_state('door_right').points[4]+Vector3(0,.2,0));camera.near=.025
