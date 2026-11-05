extends Control
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Track=preload('res://probes/bake_sampling/packed_track.gd')
const Stream=preload('res://probes/bake_sampling/packet_player.gd')
const SkinView=preload('res://scripts/damage_skin.gd')
var cars: Array=[]
var skins: Array=[]
var players: Array=[]
var cameras: Array=[]
var running:=true
var time:=0.0
var slider: HSlider
var label: Label
var capture:=false
var capture_index:=0
var pending:=false
var video:=false
var video_frame:=0
var orbit:=.76
const CAPTURE_TIMES=[2./120,.12,.40,1.4]
func _ready() -> void:
 DisplayServer.window_set_title('Crash sampling probe /120 vs30 vs15Hz / interpolated')
 get_tree().root.content_scale_size=Vector2i(2000,650)
 capture='--capture-sampling' in OS.get_cmdline_user_args()
 video='--record-sampling' in OS.get_cmdline_user_args()
 if video:DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification/bake_sampling/video'))
 var root:=VBoxContainer.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(root)
 label=Label.new();label.text='120 Hz reference / 30 Hz and 15 Hz interpolated · all failure events retain120Hz timing';root.add_child(label)
 var row:=HBoxContainer.new();root.add_child(row)
 var button:=Button.new();button.text='Play / pause';button.pressed.connect(func():running=not running);row.add_child(button)
 var reset:=Button.new();reset.text='Restart';reset.pressed.connect(func():time=0;running=true);row.add_child(reset)
 var plain:=CheckButton.new();plain.text='Plain geometry';plain.toggled.connect(func(v):
  for skin in skins:skin.set_mode(1 if v else 2)
 );row.add_child(plain)
 var slow:=Label.new();slow.text='Quarter speed · one frontal120km/h clip · wheel phase unwrapped · drag to orbit';row.add_child(slow)
 slider=HSlider.new();slider.min_value=0;slider.max_value=2.5;slider.step=.001;root.add_child(slider)
 slider.value_changed.connect(func(v):time=v;running=false)
 var columns:=HBoxContainer.new();columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;root.add_child(columns)
 for hz in [120,30,15,0]:
  var tag: String=str(hz) if hz>0 else 'adaptive'
  var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;columns.add_child(column)
  var title:=Label.new();title.text='Adaptive · streamed blocks' if hz==0 else '%d Hz'%hz+(' reference' if hz==120 else ' + interpolation');title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;column.add_child(title)
  var container:=SubViewportContainer.new();container.stretch=true;container.size_flags_vertical=Control.SIZE_EXPAND_FILL;container.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_child(container)
  var view:=SubViewport.new();view.size=Vector2i(600,650);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;container.add_child(view)
  var world:=Node3D.new();view.add_child(world)
  var env:=WorldEnvironment.new();var environment:=Environment.new();environment.background_mode=Environment.BG_SKY;var sky:=Sky.new();sky.sky_material=ProceduralSkyMaterial.new();environment.sky=sky;environment.ambient_light_source=Environment.AMBIENT_SOURCE_SKY;environment.ambient_light_color=Color('#d9e7ed');environment.ambient_light_energy=.8;env.environment=environment;world.add_child(env)
  var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-35,0);sun.light_energy=1.1;sun.shadow_enabled=true;world.add_child(sun)
  var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-20,145,0);fill.light_energy=.35;world.add_child(fill)
  var floor_:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(100,.1,100);floor_.mesh=box;floor_.position.y=-.05;var mat:=StandardMaterial3D.new();mat.albedo_color=Color('#6b777c');mat.roughness=.95;floor_.material_override=mat;world.add_child(floor_)
  var car:=Vehicle.new();car.setup('res://vehicles/niva.json',false);cars.append(car)
  var skin:=Node3D.new();skin.set_script(SkinView);world.add_child(skin);skin.setup(car.solver);skin.show_frame=false;skin.set_mode(2);skins.append(skin)
  var player: RefCounted
  if hz==0:player=Stream.new();player.setup('adaptive')
  else:
   var file:=FileAccess.open_compressed('res://verification/bake_sampling/packed_%s.track'%tag,FileAccess.READ,FileAccess.COMPRESSION_ZSTD);player=Track.new();player.setup(file.get_var(false));file.close()
  players.append(player)
  floor_.position.y=-float(player.data.metadata.origin[1])-.05
  var camera:=Camera3D.new();camera.current=true;camera.fov=45;camera.keep_aspect=Camera3D.KEEP_WIDTH;world.add_child(camera);cameras.append(camera)
 print('SAMPLING_VIEWER_READY 120/30/15Hz same source, zero solves')
func show_time() -> void:
 for i in cars.size():
  var state: Dictionary=players[i].sample(time);cars[i].solver.restore(state);skins[i].update_pose()
  var center: Vector3=cars[i].solver.station_center(2)
  cameras[i].position=center+Vector3(cos(orbit)*6,2.5,sin(orbit)*6);cameras[i].look_at(center+Vector3(0,.25,0))
 slider.set_value_no_signal(time);label.text='Time %.3fs · 120Hz reference /30Hz /15Hz with interpolation · failure events keep120Hz timing'%time
func _process(dt: float) -> void:
 if pending or (capture and capture_index>=CAPTURE_TIMES.size()) or (video and video_frame>=301):return
 if video:time=float(video_frame)/120
 elif capture:
  time=CAPTURE_TIMES[capture_index]
 elif running:time=fmod(time+dt*.25,2.5)
 show_time()
 if capture or video:take_shot()
func take_shot() -> void:
 pending=true
 for n in (1 if video else 3):await get_tree().process_frame
 await RenderingServer.frame_post_draw
 var path: String='res://verification/bake_sampling/video/%04d.png'%video_frame if video else 'res://verification/bake_sampling/comparison_%d.png'%capture_index
 get_viewport().get_texture().get_image().save_png(path)
 if video:video_frame+=1
 else:capture_index+=1
 pending=false
 if (capture and capture_index>=CAPTURE_TIMES.size()) or (video and video_frame>=301):
  FileAccess.open('res://verification/bake_sampling/stream_viewer_'+('video' if video else 'capture')+'_loads.json',FileAccess.WRITE).store_string(JSON.stringify(players[-1].loads,'\t'))
  get_tree().quit()
func _input(event: InputEvent) -> void:
 if event is InputEventMouseMotion and event.position.y>100 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):orbit+=event.relative.x*.007
