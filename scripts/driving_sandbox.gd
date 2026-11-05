extends Node3D
## World/input/camera only. Vehicle physics is shared with the crash bench.
const Terrain=preload('res://scripts/practice_terrain.gd')
var terrain: RefCounted
const Simulation=preload('res://scripts/driving_vehicle.gd')
const BodyFixture=preload('res://scripts/body_impact_fixture.gd')
const MountDemo=preload('res://scripts/wheel_mount_demo.gd')
var mount_demo: RefCounted
var capture_mounts:=false
var mount_capture_stage:=0
const SkinView=preload('res://scripts/damage_skin.gd')
@export_file('*.json') var vehicle_profile: String='res://vehicles/niva.json'
var vehicle: RefCounted
var view: Node3D
var camera: Camera3D
var readout: Label
var bake_toggle: CheckButton
var body_fixture_active:=false
var body_case:=''
var body_previous_baked:=true
var experimental_body: CheckButton
var quality_control: OptionButton
var reverse:=false
var camera_mode:=0
var orbit:=0.0
var elapsed:=0.0
var capture_mode:=false
var capture_stage:=0
var head_on_case:=false
var capture_adaptive:=false
var adaptive_capture_stage:=0
var capture_jumps:=false
var jump_capture_index:=0
var jump_air_saved:=false
var capture_baked_driving:=false
var baked_capture_stage:=0

func _ready() -> void:
 DisplayServer.window_set_title('Niva sandbox — baked crashes and live tuning')
 capture_baked_driving='--capture-driving-baked' in OS.get_cmdline_user_args()
 capture_mode='--capture-driving' in OS.get_cmdline_user_args()
 capture_mounts='--capture-mounts' in OS.get_cmdline_user_args()
 capture_adaptive='--capture-adaptive' in OS.get_cmdline_user_args()
 capture_jumps='--capture-jumps' in OS.get_cmdline_user_args()
 terrain=Terrain.new()
 _world()
 vehicle=Simulation.new()
 vehicle.setup(vehicle_profile,true)
 if capture_adaptive or '--live' in OS.get_cmdline_user_args():vehicle.baked_enabled=false
 vehicle.solver.terrain=terrain
 mount_demo=MountDemo.new()
 vehicle.before_step.connect(mount_demo.step)
 vehicle.solver.barrier_min=Vector3(40,0,-8)
 vehicle.solver.barrier_max=Vector3(41,3,8)
 vehicle.reset(0,Vector3(-25,0,0))
 view=Node3D.new()
 view.set_script(SkinView)
 add_child(view)
 view.setup(vehicle.solver,vehicle.profile.model)
 view.show_frame=false
 view.set_mode(2)
 camera=Camera3D.new()
 camera.fov=55
 camera.far=1000
 camera.current=true
 add_child(camera)
 var fill:=DirectionalLight3D.new()
 fill.light_energy=.5
 camera.add_child(fill)
 _hud()
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with('--quality='):
   var factor: int=int(argument.trim_prefix('--quality='))
   vehicle.set_simulation_quality(factor)
   quality_control.selected=[1,2,4].find(factor) if factor in [1,2,4] else 0
 if capture_mounts or '--mount-test' in OS.get_cmdline_user_args():call_deferred('_start_mount_test')
 if capture_jumps:call_deferred('_capture_jump_start')
 if capture_adaptive or '--head-on' in OS.get_cmdline_user_args():call_deferred('_start_head_on')
 if capture_baked_driving:call_deferred('_start_head_on',120.0,20.0)
 if '--baked-sequence' in OS.get_cmdline_user_args() or '--capture-baked-sequence' in OS.get_cmdline_user_args():call_deferred('_start_baked_sequence')
 print('DRIVING_SANDBOX_READY shared vehicle=',vehicle.profile.name)

func _material(color: String) -> StandardMaterial3D:
 var mat:=StandardMaterial3D.new()
 mat.albedo_color=Color(color).srgb_to_linear()
 mat.roughness=.9
 return mat

func _box(size: Vector3,position_: Vector3,color: String) -> void:
 var mesh:=MeshInstance3D.new()
 var shape:=BoxMesh.new()
 shape.size=size
 mesh.mesh=shape
 mesh.position=position_
 mesh.material_override=_material(color)
 add_child(mesh)

func _world() -> void:
 var environment:=WorldEnvironment.new()
 var sky:=Environment.new()
 sky.background_mode=Environment.BG_COLOR
 sky.background_color=Color('#a2b9c7')
 sky.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 sky.ambient_light_color=Color('#dce8f0')
 sky.ambient_light_energy=.5
 sky.tonemap_mode=Environment.TONE_MAPPER_FILMIC
 environment.environment=sky
 add_child(environment)
 var sun:=DirectionalLight3D.new()
 sun.rotation_degrees=Vector3(-42,-30,0)
 sun.light_energy=.8
 sun.shadow_enabled=true
 add_child(sun)
 _box(Vector3(1500,.2,1500),Vector3(0,-.1,0),'#738078')
 _box(Vector3(180,.01,120),Vector3(0,-.004,0),'#444e53')
 _box(Vector3(1,3,16),Vector3(40.5,1.5,0),'#b1aaa0')
 _ramps()
 for z in [-8.0,8.0]:
  _box(Vector3(1.08,.15,.15),Vector3(40.5,3,z),'#dfae4c')
 for x in range(-80,81,10):
  _box(Vector3(.045,.006,110),Vector3(x,.005,0),'#788284')
 for z in range(-50,51,10):
  _box(Vector3(170,.006,.045),Vector3(0,.005,z),'#788284')
 for x in range(-60,38,4):
  _box(Vector3(1.5,.009,.09),Vector3(x,.01,0),'#d1c79b')
 for z in [-9.0,9.0]:
  _box(Vector3(95,.009,.10),Vector3(-8,.01,z),'#d1c79b')

func _ramps() -> void:
 for i in terrain.ramps.size():
  var ramp: Dictionary=terrain.ramps[i]
  var surface:=MeshInstance3D.new()
  surface.mesh=terrain.mesh(ramp)
  surface.material_override=_material('#708991')
  add_child(surface)
  var label:=Label3D.new()
  label.text=('J / ' if i==0 else 'K / ')+str(ramp.name)
  label.position=Vector3(ramp.start-3,2.7,ramp.z)
  label.font_size=48
  label.pixel_size=.012
  label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
  add_child(label)
  for x in range(int(ramp.start)-20,int(ramp.start+ramp.length)+15,3):
   var p:=Vector3(x,0,ramp.z)
   p.y=terrain.sample(p).w+.014
   _box(Vector3(.7,.015,.10),p,'#d1c79b')

func _jump_start(index: int) -> void:
 _reset()
 var ramp: Dictionary=terrain.ramps[index]
 vehicle.reset(0,Vector3(float(ramp.start)-30,0,ramp.z))
 camera_mode=0
 orbit=0

func _capture_jump_start() -> void:
 _jump_start(jump_capture_index)
 var ramp: Dictionary=terrain.ramps[jump_capture_index]
 vehicle.reset(60,Vector3(float(ramp.start)-18,0,ramp.z))
 camera_mode=2
 jump_air_saved=false

func _hud() -> void:
 var canvas:=CanvasLayer.new()
 add_child(canvas)
 var panel:=PanelContainer.new()
 panel.position=Vector2(24,22)
 var style:=StyleBoxFlat.new()
 style.bg_color=Color(.05,.09,.11,.88)
 style.content_margin_left=16
 style.content_margin_right=16
 style.content_margin_top=12
 style.content_margin_bottom=12
 panel.add_theme_stylebox_override('panel',style)
 canvas.add_child(panel)
 panel.size=Vector2(490,get_viewport().get_visible_rect().size.y-44)
 get_viewport().size_changed.connect(func():panel.size.y=get_viewport().get_visible_rect().size.y-44)
 var scroll:=ScrollContainer.new()
 scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
 panel.add_child(scroll)
 var column:=VBoxContainer.new()
 column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 scroll.add_child(column)
 var title:=Label.new()
 title.text=vehicle.profile.name.to_upper()+' / DRIVE & CRASH'
 title.add_theme_font_size_override('font_size',22)
 column.add_child(title)
 readout=Label.new()
 readout.add_theme_font_size_override('font_size',17)
 readout.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 column.add_child(readout)
 var controls:=Label.new()
 controls.text='W throttle · S brake · A/D steer · Space handbrake\nQ forward/reverse · R repair/reset · C camera\nH 60 / Y 120 km/h wall starts · U/I ±20° starts\nB baked/live crashes · T wheel test · J/K jump starts\n1 structure · 3 textured car · Drag: orbit · Esc: close'
 controls.add_theme_font_size_override('font_size',13)
 column.add_child(controls)
 var reset:=Button.new()
 reset.text='Repair and reset'
 reset.pressed.connect(_reset)
 column.add_child(reset)
 var arena_button:=Button.new()
 arena_button.text='Open colosseum arena'
 arena_button.pressed.connect(func():get_tree().change_scene_to_file('res://arena/colosseum.tscn'))
 column.add_child(arena_button)
 var test_button:=Button.new()
 test_button.text='Test wheel mount'
 test_button.pressed.connect(_start_mount_test)
 column.add_child(test_button)
 for row in [[['60 km/h wall start',60.0,0.0],['120 km/h wall start',120.0,0.0]],[['+20° wall start',120.0,20.0],['−20° wall start',120.0,-20.0]]]:
  var buttons:=HBoxContainer.new();column.add_child(buttons)
  for item in row:
   var button:=Button.new();button.text=item[0]
   button.pressed.connect(_start_head_on.bind(item[1],item[2]));buttons.add_child(button)
 bake_toggle=CheckButton.new();bake_toggle.text='Use baked wall crashes';bake_toggle.button_pressed=vehicle.baked_enabled
 bake_toggle.toggled.connect(_baked_toggled);column.add_child(bake_toggle)
 var sequence_buttons:=HBoxContainer.new();column.add_child(sequence_buttons)
 for item in [['Three baked impacts',_start_baked_sequence],['Stage next impact',_stage_next_impact]]:
  var button:=Button.new();button.text=item[0];button.pressed.connect(item[1]);sequence_buttons.add_child(button)
 var body_buttons:=HBoxContainer.new();column.add_child(body_buttons)
 for item in [['Live flat roof','roof_flat'],['Live angled roof','roof_corner'],['Live side hit','side_wall']]:
  var button:=Button.new();button.text=item[0];button.pressed.connect(_start_body_test.bind(item[1]));body_buttons.add_child(button)
 experimental_body=CheckButton.new();experimental_body.text='Promoted roof / side materials for live test';experimental_body.button_pressed=true;column.add_child(experimental_body)
 var quality_row:=HBoxContainer.new();column.add_child(quality_row)
 var quality_label:=Label.new();quality_label.text='Live precision';quality_row.add_child(quality_label)
 quality_control=OptionButton.new()
 for item in [['480 Hz',1],['960 Hz',2],['1,920 Hz',4]]:quality_control.add_item(item[0],item[1])
 quality_control.item_selected.connect(func(index):vehicle.set_simulation_quality(quality_control.get_item_id(index)))
 quality_row.add_child(quality_control)
 var grip_label:=Label.new();column.add_child(grip_label)
 var grip:=HSlider.new();grip.min_value=.10;grip.max_value=1.50;grip.step=.01;grip.value=vehicle.dynamics.parameters.tire_friction;column.add_child(grip)
 grip_label.text='Tyre grip: %.2f'%grip.value
 grip.value_changed.connect(func(value):
  vehicle.set_tire_friction(value)
  grip_label.text='Tyre grip: %.2f'%value)
 var power_label:=Label.new();column.add_child(power_label)
 var power:=HSlider.new();power.min_value=55;power.max_value=660;power.step=5;power.value=vehicle.dynamics.parameters.power_w/1000;column.add_child(power)
 power_label.text='Engine power: %.0f kW'%power.value
 power.value_changed.connect(func(value):
  vehicle.set_engine_power_kw(value)
  power_label.text='Engine power: %.0f kW'%value)
 var tuning_note:=Label.new();tuning_note.text='Tuning affects live driving. Crash bakes keep their recorded motion.';tuning_note.add_theme_font_size_override('font_size',11);column.add_child(tuning_note)
 var panel_controls:=VBoxContainer.new();panel_controls.set_script(load('res://scripts/panel_controls.gd'));column.add_child(panel_controls);panel_controls.setup(vehicle)


func _baked_toggled(value: bool) -> void:
 vehicle.baked_enabled=value
 if body_fixture_active and value:
  BodyFixture.restore(vehicle);body_fixture_active=false;body_case=''

func _start_body_test(case_name: String) -> void:
 _reset()
 body_previous_baked=vehicle.baked_enabled
 bake_toggle.button_pressed=false
 BodyFixture.start(vehicle,case_name,1.0,experimental_body.button_pressed)
 vehicle.set_simulation_quality(quality_control.get_selected_id())
 body_fixture_active=true;body_case=case_name
 camera_mode=2;orbit=0
 if vehicle.solver.effects!=null:vehicle.solver.effects.synchronize()

func _start_head_on(speed_kmh: float=60,heading_deg: float=0) -> void:
 _reset()
 head_on_case=true
 camera_mode=2
 orbit=0
 vehicle.reset_wall_approach(speed_kmh,heading_deg)

func _start_baked_sequence() -> void:
 _reset()
 bake_toggle.button_pressed=true
 camera_mode=2;orbit=0
 vehicle.start_baked_sequence()

func _stage_next_impact() -> void:
 if vehicle.mode=='BAKED':return
 bake_toggle.button_pressed=true
 camera_mode=2;orbit=0
 vehicle.stage_next_supported()

func _start_mount_test() -> void:
 _reset()
 bake_toggle.button_pressed=false
 camera_mode=1
 orbit=0
 mount_demo.start(vehicle.solver)

func _reset() -> void:
 BodyFixture.restore(vehicle)
 if body_fixture_active:
  body_fixture_active=false;body_case=''
  bake_toggle.button_pressed=body_previous_baked
 mount_demo.stop()
 head_on_case=false
 reverse=false
 elapsed=0
 vehicle.reset(0,Vector3(-25,0,0))

func _physics_process(dt: float) -> void:
 elapsed+=dt
 var throttle: float=1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0
 var brake: float=1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0
 var steering: float=(1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)-(1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0)
 var handbrake: float=1.0 if Input.is_physical_key_pressed(KEY_SPACE) else 0.0
 if capture_mode:
  throttle=1.0 if elapsed<6 else 0.0
  brake=1.0 if elapsed>=6 else 0.0
 if vehicle.sequence_active:
  vehicle.set_controls(0,0,0,0)
  vehicle.advance(dt,.5)
 elif body_fixture_active:
  vehicle.set_controls(0,0,0,0)
  vehicle.advance(dt,.25)
 elif capture_jumps:
  vehicle.set_controls(.1,0,0,0)
  vehicle.advance(dt)
 elif mount_demo.active:
  vehicle.set_controls(0,0,0,0)
  vehicle.advance(dt,.5)
 else:
  vehicle.set_controls(-throttle if reverse else throttle,brake,steering,handbrake)
  vehicle.advance(dt)

func _process(_dt: float) -> void:
 var g: RefCounted=vehicle.solver
 var center: Vector3=g.station_center(2)+Vector3(0,-.15,0)
 var f: Vector3=vehicle.forward()
 var heading: float=atan2(f.z,f.x)+orbit
 if capture_mode and elapsed>6:camera_mode=2
 var angle: float=heading+([PI,0.60,PI/2][camera_mode])
 var offset:=Vector3(cos(angle)*7,3.2,sin(angle)*7)
 camera.position=center+offset
 # Keep the inspection camera on the car's side of the opaque test wall.
 if g.barrier_min.z-1<camera.position.z and camera.position.z<g.barrier_max.z+1:
  if center.x<(g.barrier_min.x+g.barrier_max.x)*.5:camera.position.x=minf(camera.position.x,minf(center.x-absf(offset.x),g.barrier_min.x-.8))
  else:camera.position.x=maxf(camera.position.x,maxf(center.x+absf(offset.x),g.barrier_max.x+.8))
 camera.look_at(center+Vector3(0,.3,0))
 view.update_pose()
 var speed: float=vehicle.velocity().length()*3.6
 var damage: Dictionary=g.metrics()
 readout.text='%3.0f km/h   %s\nSuspension failures: %d   Yielded members: %d' %[speed,'R' if reverse else 'D',damage.broken_suspension_links,damage.yielded_links]
 var performance: Dictionary=vehicle.statistics()
 var mode_name: Dictionary={'DRIVE':'Light driving','FULL':'Live deformation','SLEEP':'Parked / sleeping','BAKED':'Baked crash playback'}
 readout.text+='\nPhysics: '+mode_name[vehicle.mode]
 readout.text+='\nBaked wall crashes: '+('ON' if vehicle.baked_enabled else 'OFF')
 if vehicle.sequence_notice!='':readout.text+='\n'+vehicle.sequence_notice
 if vehicle.baked_count>0:readout.text+='\nBaked impacts: %d'%vehicle.baked_count
 if body_fixture_active:
  var body_metrics: Dictionary=BodyFixture.metrics(g)
  readout.text+='\nLive %s · ¼ speed · R returns to driving'%body_case.replace('_',' ')
  readout.text+='\nCabin height %.2f m · width %.2f m' %[body_metrics.cabin_height_m,body_metrics.cabin_width_m]
 elif vehicle.baked_enabled and vehicle.contact_sensor.last_rejection!='':
  readout.text+='\nRigid contact: '+vehicle.contact_sensor.last_rejection.replace('_',' ')

 if not vehicle.last_bake.is_empty():
  readout.text+='\nClip: '+str(vehicle.last_bake.id)
  readout.text+='\nImpact %.0f km/h → %.0f km/h recording' %[vehicle.last_bake.actual_impact_kmh,vehicle.last_bake.recorded_speed_kmh]
  if vehicle.mode=='BAKED':readout.text+='\nPlayback %.1f / 2.5 s · live solver paused'%vehicle.crash_player.time
  else:readout.text+='\nReplay complete · R repairs the damaged car'

 readout.text+='\nFull structural steps: %d   Average: %.2f ms / 120 Hz frame' %[vehicle.full_steps,performance.cpu_ms_per_sim_second/120.0]
 if '--capture-baked-sequence' in OS.get_cmdline_user_args():
  if vehicle.mode=='BAKED' and vehicle.crash_player.time>.7 and vehicle.baked_count>baked_capture_stage:
   baked_capture_stage=vehicle.baked_count
   _capture('sandbox_sequence_hit_%d.png'%baked_capture_stage)
  elif vehicle.baked_count==3 and vehicle.last_bake.get('completed',false):
   _capture('sandbox_sequence_complete.png');get_tree().quit()
 if capture_baked_driving:
  if vehicle.mode=='BAKED' and vehicle.crash_player.time>.25 and baked_capture_stage==0:
   _capture('driving_baked_impact.png');baked_capture_stage=1
  elif vehicle.last_bake.get('completed',false) and baked_capture_stage==1:
   _capture('driving_baked_resumed.png');get_tree().quit()
 if capture_adaptive:
  if vehicle.solver.simulated_time>1 and adaptive_capture_stage==0:
   adaptive_capture_stage=1
   _capture('adaptive_drive.png')
  elif vehicle.mode=='FULL' and not g.impact_started and adaptive_capture_stage==1:
   adaptive_capture_stage=2
   _capture('adaptive_forecast.png')
  elif g.impact_started and g.simulated_time>g.impact_time+.7 and adaptive_capture_stage==2:
   _capture('adaptive_impact.png')
   get_tree().quit()
 if vehicle.mode=='FULL':
  readout.text+='\nLive solve: %.0f Hz'%(1.0/float(g.config.fixed_step_s))
  readout.text+='\nTrigger: '+vehicle.last_wake_reason.replace('_',' ')
  readout.text+='\nInternal motion: %.2f J · quiet cutoff %.1f J' %[vehicle.deformation_energy_j,vehicle.deformation_sleep_energy_j]
 if capture_jumps:
  var gap:=INF
  for w in g.wheels.wheels:
   var p: Vector3=g.points[w.node]
   gap=minf(gap,p.y+g.wheels.support(w,Vector3.DOWN).y-terrain.sample(p).w)
  if gap>.25 and not jump_air_saved:
   jump_air_saved=true
   _capture('ramp_%d_air.png'%jump_capture_index)
  elif jump_air_saved and gap<.025:
   _capture('ramp_%d_landing.png'%jump_capture_index)
   if jump_capture_index==0:
    jump_capture_index=1
    _capture_jump_start()
   else:get_tree().quit()
 if mount_demo.phase!='':
  readout.text+='\n'+mount_demo.phase
  readout.text+='\nFront-left permanent bend: %.1f°'%damage.wheels[3].permanent_alignment_deg
 if capture_mounts:
  if mount_demo.time>.85 and mount_capture_stage==0:
   mount_capture_stage=1
   _capture('mount_aligned.png')
  elif mount_demo.time>1.8 and mount_capture_stage==1:
   mount_capture_stage=2
   _capture('mount_bent.png')
  elif mount_demo.time>2.65 and mount_capture_stage==2:
   _capture('mount_detached.png')
   get_tree().quit()
 if capture_mode:
  if elapsed>2.5 and capture_stage==0:
   capture_stage=1
   _capture('driving_preview.png')
  elif elapsed>7 and capture_stage==1:
   _capture('driving_crash_preview.png')
   get_tree().quit()

func _capture(filename: String) -> void:
 RenderingServer.force_draw(false)
 get_viewport().get_texture().get_image().save_png('res://verification/'+filename)
 print('DRIVING_PREVIEW_SAVED ',filename,' ',JSON.stringify(view.binding_quality()))

func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):orbit+=event.relative.x*.008
 if event is InputEventKey and event.pressed and not event.echo:
  match event.physical_keycode:
   KEY_R:_reset()
   KEY_T:_start_mount_test()
   KEY_H:_start_head_on()
   KEY_Y:_start_head_on(120)
   KEY_U:_start_head_on(120,20)
   KEY_I:_start_head_on(120,-20)
   KEY_B:bake_toggle.button_pressed=not bake_toggle.button_pressed
   KEY_J:_jump_start(0)
   KEY_K:_jump_start(1)
   KEY_Q:reverse=not reverse
   KEY_C:
    camera_mode=(camera_mode+1)%3
    orbit=0
   KEY_1:view.set_mode(0)
   KEY_3:view.set_mode(2)
   KEY_ESCAPE:get_tree().quit()
