extends 'res://scripts/driving_sandbox.gd'
func _ready() -> void:
 super._ready()
 DisplayServer.window_set_title('Niva MAIN panel integration — preview')
 vehicle.set_panel_open('door_left',70);vehicle.set_panel_open('door_right',55)
 vehicle.set_panel_open('bonnet',45);vehicle.set_panel_open('tailgate',70)
 camera_mode=1
 if '--capture-panels' in OS.get_cmdline_user_args():
  await get_tree().create_timer(4).timeout
  await RenderingServer.frame_post_draw
  get_viewport().get_texture().get_image().save_png('res://tests/panels/main_open.png')
  print('PANEL_MAIN_RENDER ',view.panel_quality(),' full=',vehicle.full_steps,' cage=',vehicle.solver.panels.active_steps)
  get_tree().quit()
