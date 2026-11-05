extends Node3D
const World=preload('res://probes/multicar/world.gd')
const SkinView=preload('res://scripts/damage_skin.gd')
const Library=preload('res://probes/multicar/library.gd')
var sim: RefCounted
var skins: Array=[]
var labels: Array=[]
var camera: Camera3D
var readout: Label
var paused:=false
var slow:=true
var accumulator:=0.0
var orbit:=1.30
var replaying:=false
var replay_time:=0.0
var playback: Array=[]
var capture_mode:=false
var capture_case:=0
var capture_stage:=0
var captures: Array=[]
var capture_pending:=false
var camera_distance:=1.0
func _ready() -> void:
 DisplayServer.window_set_title('Niva / multi-car baked deformation and coupled contacts')
 capture_mode='--capture-multicar' in OS.get_cmdline_user_args()
 if capture_mode:set_process_unhandled_input(false)
 _environment();_hud();_start('head_on')
 print('MULTICAR_PROBE_READY root motion physical / shape recorded / 120Hz planar')
func _environment() -> void:
 var world:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color('#9fb4c3')
 env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color('#e3e9e9');env.ambient_light_energy=.7;env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
 world.environment=env;add_child(world)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-35,0);sun.light_energy=1.1;sun.shadow_enabled=true;add_child(sun)
 var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-20,140,0);fill.light_energy=.35;add_child(fill)
 var floor_:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(220,.12,100);floor_.mesh=box;floor_.position.y=-.06
 var mat:=StandardMaterial3D.new();mat.albedo_color=Color('#57666c').srgb_to_linear();mat.roughness=.9;floor_.material_override=mat;add_child(floor_)
 for x in range(-50,51,5):
  var line:=MeshInstance3D.new();var shape:=BoxMesh.new();shape.size=Vector3(.025,.01,40);line.mesh=shape;line.position=Vector3(x,.006,0)
  var m:=StandardMaterial3D.new();m.albedo_color=Color('#83918f').srgb_to_linear();line.material_override=m;add_child(line)
 camera=Camera3D.new();camera.current=true;camera.fov=48;add_child(camera)
func _hud() -> void:
 var canvas:=CanvasLayer.new();add_child(canvas)
 var panel:=PanelContainer.new();panel.position=Vector2(18,18);panel.custom_minimum_size.x=440;canvas.add_child(panel)
 var style:=StyleBoxFlat.new();style.bg_color=Color(.03,.065,.08,.94);style.content_margin_left=14;style.content_margin_right=14;style.content_margin_top=12;style.content_margin_bottom=12;panel.add_theme_stylebox_override('panel',style)
 var col:=VBoxContainer.new();panel.add_child(col)
 var title:=Label.new();title.text='NIVA / MULTI-CAR BAKED CRASHES';title.add_theme_font_size_override('font_size',21);col.add_child(title)
 readout=Label.new();readout.add_theme_font_size_override('font_size',14);col.add_child(readout)
 for item in [['Two cars / head-on 60 + 60','head_on'],['120 km/h into parked car','parked'],['Three cars / simultaneous front + rear','triple'],['Drive into other cars','drive'],['Partial corner / explicit fallback','corner'],['Low speed / no deformation bake','low']]:
  var b:=Button.new();b.text=item[0];b.pressed.connect(_start.bind(item[1]));col.add_child(b)
 var row:=HBoxContainer.new();col.add_child(row)
 var replay:=Button.new();replay.text='Replay';replay.pressed.connect(_replay);row.add_child(replay)
 var pause:=Button.new();pause.text='Pause';pause.pressed.connect(func():paused=not paused);row.add_child(pause)
 var save:=Button.new();save.text='Save';save.pressed.connect(_save_recording);row.add_child(save)
 var load_button:=Button.new();load_button.text='Load / replay';load_button.pressed.connect(_load_recording);row.add_child(load_button)
 var slow_button:=CheckButton.new();slow_button.text='Quarter speed';slow_button.button_pressed=true;slow_button.toggled.connect(func(value):slow=value);col.add_child(slow_button)
 var help:=Label.new();help.text='W/S throttle/brake · A/D steer · R reset · P pause\nSpace replay · Drag orbit · Wheel zoom · Esc close\nPlanar single-mass/contact-island proof.\nWall root trajectories are NOT replayed.';help.add_theme_font_size_override('font_size',12);col.add_child(help)
func _start(name_: String) -> void:
 for skin in skins:remove_child(skin);skin.queue_free()
 for label in labels:remove_child(label);label.queue_free()
 skins.clear();labels.clear();sim=World.new();sim.start(name_)
 for car in sim.cars:
  var skin:=Node3D.new();skin.set_script(SkinView);add_child(skin);skin.setup(car.graph);skin.show_frame=false;skin.set_mode(2);skins.append(skin)
  var label:=Label3D.new();label.text='CAR '+str(car.id+1);label.font_size=42;label.pixel_size=.012;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.modulate=[Color('#ffcf66'),Color('#76daed'),Color('#e99fe8')][car.id%3];add_child(label);labels.append(label)
  Library.get_clip('impact_000_60',car.graph);Library.get_clip('impact_180_60',car.graph)
  if FileAccess.file_exists('res://probes/multicar/data/opposed_front_rear_60.crashclip'):Library.get_clip('opposed_front_rear_60',car.graph)
 paused=false;replaying=false;accumulator=0
 print('MULTICAR_CASE ',name_)
func _replay() -> void:
 if sim.recorded.size()<2:return
 playback=sim.recorded.duplicate(true);replaying=true;replay_time=0;paused=false
func _save_recording() -> void:
 var file:=FileAccess.open_compressed('res://verification/multicar_recording.bin',FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD)
 file.store_var({'version':1,'case':sim.selected_case,'frames':sim.recorded});file.close()
 print('MULTICAR_RECORDING_SAVED frames=',sim.recorded.size())
func _load_recording() -> void:
 if not FileAccess.file_exists('res://verification/multicar_recording.bin'):return
 var file:=FileAccess.open_compressed('res://verification/multicar_recording.bin',FileAccess.READ,FileAccess.COMPRESSION_ZSTD)
 var data: Dictionary=file.get_var(false);file.close()
 if data.get('version',0)!=1 or data.get('frames',[]).is_empty():return
 _start(data.case);playback=data.frames;sim.recorded=playback.duplicate(true);replaying=true;replay_time=0;paused=false
func _physics_process(dt: float) -> void:
 if paused:return
 var elapsed: float=dt*(.25 if slow and not capture_mode else 1)
 if replaying:
  replay_time=minf((playback.size()-1)*sim.h,replay_time+elapsed)
  sim.restore(playback[mini(roundi(replay_time/sim.h),playback.size()-1)])
  if replay_time>=(playback.size()-1)*sim.h:paused=true
  return
 accumulator+=elapsed
 while accumulator>=sim.h:
  if sim.selected_case=='drive':
   var player=sim.cars[0]
   player.throttle=1 if Input.is_physical_key_pressed(KEY_W) else 0
   player.brake=1 if Input.is_physical_key_pressed(KEY_S) else 0
   player.steering=(1 if Input.is_physical_key_pressed(KEY_A) else 0)-(1 if Input.is_physical_key_pressed(KEY_D) else 0)
  sim.step();accumulator-=sim.h
func _process(_dt: float) -> void:
 if sim==null:return
 var center:=Vector3.ZERO;var extent:=3.0
 for car in sim.cars:center+=car.center
 center/=sim.cars.size()
 for car in sim.cars:extent=maxf(extent,absf(car.center.x-center.x)+2)
 if sim.selected_case=='drive':center=sim.cars[0].center+sim.cars[0].forward()*3;extent=6
 var distance: float=maxf(19,extent*2.5)*camera_distance
 camera.position=center+Vector3(cos(orbit)*distance,distance*.52,sin(orbit)*distance)
 camera.look_at(center+Vector3(-sin(orbit),0,cos(orbit))*distance*.17+Vector3(0,.25,0))
 var text_: String='%s · %.2f s · %s\nMass %.0f kg · full structural solves %d\nContacts %d · root impulse batches %d' %[sim.selected_case.replace('_',' '),sim.time,'REPLAY' if replaying else 'LIVE',sim.cars.reduce(func(total,car):return total+car.mass,0.0),sim.cars.reduce(func(total,car):return total+car.graph.step_count,0),sim.contacts_count,sim.contact_batches.size()]
 for i in sim.cars.size():
  var car=sim.cars[i];skins[i].update_pose();labels[i].position=car.center+Vector3(0,2.0,0)
  text_+='\nCar%d: %.0f km/h · '%[i+1,car.velocity.length()*3.6]
  text_+=car.clip_id if not car.clip_id.is_empty() else 'no bake'
  if not car.last_selection.is_empty():text_+='\n  '+str(car.last_selection.get('reason',''))
  if car.last_selection.has('equivalent_wall_kmh'):text_+='\n  Closing %s / assigned %.0f km/h' %[str(car.last_selection.relative_closing_kmh.map(func(value):return roundi(value))),car.last_selection.equivalent_wall_kmh]
 readout.text=text_
 if capture_mode:_capture_tick()
func _capture_tick() -> void:
 if capture_pending or capture_case>=3 or capture_stage>=3:return
 var names: Array=['head_on','parked','triple']
 var label: String=['before','impact','after'][capture_stage]
 var threshold: float=[.02,.55,2.8][capture_stage]
 if sim.time<threshold or capture_pending:return
 capture_pending=true;paused=true
 await RenderingServer.frame_post_draw
 var file: String='res://probes/multicar/evidence/'+names[capture_case]+'_'+label+'.png'
 get_viewport().get_texture().get_image().save_png(file)
 captures.append({'case':names[capture_case],'stage':label,'path':file,'stats':sim.stats()})
 print('MULTICAR_CAPTURE ',file)
 capture_pending=false;paused=false
 capture_stage+=1
 if capture_stage>=3:
  capture_stage=0;capture_case+=1
  if capture_case>=names.size():
   FileAccess.open('res://probes/multicar/evidence/native_states.json',FileAccess.WRITE).store_string(JSON.stringify(captures,'\t'));capture_mode=false;paused=true;get_tree().quit();return
  _start(names[capture_case])
func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):orbit+=event.relative.x*.008
 if event is InputEventMouseButton and event.pressed:
  if event.button_index==MOUSE_BUTTON_WHEEL_UP:camera_distance=maxf(.5,camera_distance-.1)
  if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:camera_distance=minf(2,camera_distance+.1)
 if event is InputEventKey and event.pressed and not event.echo:
  match event.physical_keycode:
   KEY_R:_start(sim.selected_case)
   KEY_P:paused=not paused
   KEY_SPACE:_replay()
   KEY_ESCAPE:get_tree().quit()
