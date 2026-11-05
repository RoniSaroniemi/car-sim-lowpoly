extends Node3D
const Drive=preload('res://probes/panels/drive_runtime.gd')
const PanelSkin=preload('res://probes/panels/panel_skin.gd')
var runtime: RefCounted
var skin: Node3D
var camera: Camera3D
var label: Label
var speed_label: Label
var accumulator:=0.0
var paused:=false
var replay:=false
var replay_clock:=0.0
var replay_frames: Array=[]
var mode_:='closed'
var reverse:=false
var capture_mode:=false
var capture_names: Array=[['closed',2.65,'driving_closed'],['right_free',.5,'driving_right_free_open'],['right_free',2.65,'driving_right_free'],['right_free',1.5,'driving_right_braking','early_brake'],['right_sag',2.65,'driving_right_sag']]
var capture_index:=0
var capture_wait:=0
var saved:=false
var target_slider: HSlider
var hud: Control
var orbit:=0.0

func _ready() -> void:
 DisplayServer.window_set_title('Niva / lightweight driving and swinging damaged door')
 _world();_hud();camera=Camera3D.new();camera.current=true;camera.fov=53;add_child(camera)
 var fill:=DirectionalLight3D.new();fill.light_energy=.7;camera.add_child(fill)
 capture_mode='--capture-drive-panels' in OS.get_cmdline_user_args()
 _start('closed')
 print('PANEL_DRIVE_READY W throttle S brake A/D steer Space handbrake Q reverse R repair 120Hz compact drive')
func material(color_: String) -> StandardMaterial3D:
 var m:=StandardMaterial3D.new();m.albedo_color=Color(color_).srgb_to_linear();m.roughness=.9;return m
func _world() -> void:
 var environment_=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color('#91abbc');env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color('#e4eff7');env.ambient_light_energy=.7;env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;environment_.environment=env;add_child(environment_)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-35,0);sun.light_energy=1;sun.shadow_enabled=true;add_child(sun)
 var floor_=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(120,.2,120);floor_.mesh=box;floor_.position.y=-.1;floor_.material_override=material('#5d7774');add_child(floor_)
 var wall_=MeshInstance3D.new();box=BoxMesh.new();box.size=Vector3(.5,3.5,24);wall_.mesh=box;wall_.position=Vector3(45.25,1.75,0);wall_.material_override=material('#c29f77');add_child(wall_)
 for z in range(-40,41,5):
  var line:=MeshInstance3D.new();box=BoxMesh.new();box.size=Vector3(90,.006,.05);line.mesh=box;line.position=Vector3(-10,.005,z);line.material_override=material('#a9b0a1');add_child(line)
func _hud() -> void:
 var layer:=CanvasLayer.new();add_child(layer);var panel:=PanelContainer.new();panel.position=Vector2(16,16);panel.custom_minimum_size=Vector2(405,0);layer.add_child(panel);hud=panel
 var style:=StyleBoxFlat.new();style.bg_color=Color(.03,.06,.08,.88);style.content_margin_left=12;style.content_margin_top=10;style.content_margin_right=12;style.content_margin_bottom=10;panel.add_theme_stylebox_override('panel',style)
 var col:=VBoxContainer.new();col.add_theme_constant_override('separation',7);panel.add_child(col)
 var title:=Label.new();title.text='NIVA / LIGHTWEIGHT DOOR DYNAMICS';title.add_theme_font_size_override('font_size',19);col.add_child(title)
 speed_label=Label.new();speed_label.add_theme_font_size_override('font_size',24);col.add_child(speed_label)
 label=Label.new();label.add_theme_font_size_override('font_size',14);col.add_child(label)
 for item in [['Intact / closed','closed'],['Measured damage / free right door','right_free'],['Measured damage / one hinge sag','right_sag']]:
  var b:=Button.new();b.text=item[0];b.pressed.connect(_start.bind(item[1]));col.add_child(b)
 var caption:=Label.new();caption.text='Undamaged right door control';col.add_child(caption)
 target_slider=HSlider.new();target_slider.min_value=0;target_slider.max_value=82;target_slider.value_changed.connect(func(v):runtime.reduced.set_open('door_right',v));col.add_child(target_slider)
 var row:=HBoxContainer.new();col.add_child(row)
 var b:=Button.new();b.text='Replay';b.pressed.connect(_replay);row.add_child(b)
 b=Button.new();b.text='Pause';b.pressed.connect(func():paused=not paused);row.add_child(b)
 var help:=Label.new();help.text='W throttle · S brake · A/D steer · Space handbrake\nQ forward/reverse · R repair · P pause · Tab replay · Esc close\nDrag orbit. Beige wall at +X is solid.\nMeasured strike damage; no commanded failures.\nFull deformation wakes only at a fresh impact.';help.add_theme_font_size_override('font_size',12);col.add_child(help)
func _start(kind: String) -> void:
 mode_=kind;replay=false;paused=false;accumulator=0
 runtime=Drive.new();runtime.start(kind)
 if skin!=null:remove_child(skin);skin.queue_free()
 skin=Node3D.new();skin.set_script(PanelSkin);skin.panel_system=runtime.graph.panels;add_child(skin);skin.setup(runtime.graph);skin.show_frame=false;skin.set_mode(2)
 target_slider.set_value_no_signal(0)
func _replay() -> void:
 replay_frames=runtime.frames.duplicate(true);replay=true;replay_clock=0
func _physics_process(dt: float) -> void:
 if paused:return
 if replay:
  replay_clock+=dt
  runtime.restore(replay_frames[mini(replay_frames.size()-1,floori(replay_clock*60))]);return
 var throttle: float=float(Input.is_physical_key_pressed(KEY_W))*(-1 if reverse else 1)
 var steering: float=float(Input.is_physical_key_pressed(KEY_A))-float(Input.is_physical_key_pressed(KEY_D))
 var brake: float=float(Input.is_physical_key_pressed(KEY_S))
 var parking: float=float(Input.is_physical_key_pressed(KEY_SPACE))
 if capture_mode:
  parking=0
  throttle=1 if runtime.time<2 else 0;brake=1 if runtime.time>2.3 else 0;steering=.5 if runtime.time>1.2 else 0
  if capture_names[capture_index].size()>3:
   throttle=1 if runtime.time<.4 else 0;brake=1 if runtime.time>=.4 else 0;steering=0
 runtime.controls(throttle,brake,steering,parking)
 accumulator+=dt
 while accumulator>=runtime.h:
  if capture_mode and runtime.time>=float(capture_names[capture_index][1]):break
  runtime.step();accumulator-=runtime.h
func _process(_dt: float) -> void:
 if runtime==null:return
 skin.update_pose()
 var center: Vector3=runtime.compact.center
 var forward: Vector3=runtime.dynamics.body_forward();forward.y=0;forward=forward.normalized()
 var frame:=Basis(forward,Vector3.UP,forward.cross(Vector3.UP))
 var target: Vector3=center+Vector3(0,.35,0)
 var right: Vector3=frame*Vector3(-4.5,2.6,-5.2).rotated(Vector3.UP,orbit)
 var side: Vector3=Vector3(right.z,0,-right.x).normalized()
 target-=side*1.4
 camera.position=target+right;camera.look_at(target)
 var p: Dictionary=runtime.graph.panels.find('door_right')
 speed_label.text='%.1f km/h · %s' %[runtime.speed,'REPLAY / zero solves' if replay else 'LIVE']
 var modes: Array=[]
 for part in runtime.graph.panels.panels:modes.append(part.id+': '+part.get('reduced_mode','full_impact'))
 label.text='%s\n120 Hz compact drive · impact authoring 960 Hz\nFull body calls %d · full cage calls %d\nReduced panel steps %d · mass %.0f kg\nRight door %.0f° · latch %s · hinges %d/2\nFrame seats %d/2 · plastic work %.0f J\nMesh rebuilds 0' %['\n'.join(modes),runtime.full_steps,runtime.graph.panels.active_steps,runtime.reduced.reduced_steps,runtime.graph.panels.total_mass(),rad_to_deg(p.angle),'broken' if p.anchors[2].broken else 'latched' if p.latched else 'released',2-int(p.anchors[0].broken)-int(p.anchors[1].broken),runtime.graph.panels.closing_topology(p).frame_seats,p.plastic_work]
 if capture_mode and runtime.time>=float(capture_names[capture_index][1]):
  capture_wait+=1
  if capture_wait==5:
   var path: String='res://probes/panels/evidence/'+capture_names[capture_index][2]+'.png'
   RenderingServer.force_draw(false);get_viewport().get_texture().get_image().save_png(path)
   print('PANEL_DRIVE_CAPTURE ',mode_,' ',JSON.stringify(runtime.stats()))
   capture_index+=1;capture_wait=0
   if capture_index>=capture_names.size():get_tree().quit()
   else:_start(capture_names[capture_index][0])
func _unhandled_input(event: InputEvent) -> void:
 if capture_mode:return
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):orbit+=event.relative.x*.008
 if event is InputEventKey and event.pressed and not event.echo:
  match event.physical_keycode:
   KEY_Q:reverse=not reverse
   KEY_R:_start('closed')
   KEY_TAB:_replay()
   KEY_P:paused=not paused
   KEY_ESCAPE:get_tree().quit()
