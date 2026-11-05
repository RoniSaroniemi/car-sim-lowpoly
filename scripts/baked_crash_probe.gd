extends Node3D
const SkinView=preload('res://scripts/damage_skin.gd')
const Recorder=preload('res://scripts/crash_bake_recorder.gd')
const Player=preload('res://scripts/baked_crash_player.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Zones=preload('res://scripts/impact_zone_grid.gd')
var data: Dictionary={}
var library: Array=[]
var angle_control: SpinBox
var speed_control: OptionButton
var playlist: Array=[]
var playlist_index:=0
var launch_angle:=0.0
var launch_speed:=120.0
var recorder: RefCounted
var player: RefCounted
var solver: RefCounted
var view: Node3D
var camera: Camera3D
var barrier_view: MeshInstance3D
var zone_lines: MeshInstance3D
var grid:=Zones.new()
var readout: Label
var slow_toggle: CheckButton
var grid_toggle: CheckButton
var replay_slider: HSlider
var mode: String='READY'
var accumulator:=0.0
var yaw:=1.45
var height:=2.5
var distance:=7.5
var guard:=false
var roundtrip:=false
var capture_mode:=false
var capture_stage:=0
var hold_time:=0.0

func _ready() -> void:
 roundtrip='--roundtrip' in OS.get_cmdline_user_args()
 capture_mode='--capture-baked' in OS.get_cmdline_user_args()
 library=Clip.read_library()
 data=library[0] if not library.is_empty() else {}
 assert(not data.is_empty(),'Run python3 tools/demo.py bake first')
 player=Player.new()
 player.setup_library(library,launch_angle,launch_speed)
 solver=player.vehicle.solver
 _stage()
 view=Node3D.new();view.set_script(SkinView);add_child(view)
 view.setup(solver,player.vehicle.profile.model)
 view.show_frame=false;view.set_mode(2)
 camera=Camera3D.new();camera.current=true;camera.fov=42;camera.far=100
 add_child(camera)
 var fill:=DirectionalLight3D.new();fill.light_energy=.6;camera.add_child(fill)
 zone_lines=MeshInstance3D.new()
 var material:=StandardMaterial3D.new()
 material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 material.vertex_color_use_as_albedo=true
 zone_lines.material_override=material
 add_child(zone_lines)
 _ui()
 if capture_mode:slow_toggle.button_pressed=false
 var user_args:=OS.get_cmdline_user_args()
 for argument in user_args:
  if argument.begins_with('--angle='):launch_angle=float(argument.trim_prefix('--angle='));angle_control.value=launch_angle
  if argument.begins_with('--speed='):launch_speed=float(argument.trim_prefix('--speed='));speed_control.selected=0 if launch_speed==60 else 1
 if '--demo-three' in OS.get_cmdline_user_args():_demo_three()
 elif '--gallery' in OS.get_cmdline_user_args():_play_library()
 elif roundtrip:_record()
 else:_replay()
 print('BAKED_PROBE_READY clips=',library.size(),' frames_per_clip=',data.frames.size())

func _mat(color: Color) -> StandardMaterial3D:
 var m:=StandardMaterial3D.new();m.albedo_color=color;m.roughness=.9
 return m
func _stage() -> void:
 var world:=WorldEnvironment.new();var env:=Environment.new()
 env.background_mode=Environment.BG_COLOR;env.background_color=Color('#33414b')
 env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color=Color('#d9e5e8');env.ambient_light_energy=.55
 env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
 world.environment=env;add_child(world)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.light_energy=.7;sun.shadow_enabled=true;add_child(sun)
 var floor_:=MeshInstance3D.new();var plane:=BoxMesh.new();plane.size=Vector3(80,.2,40)
 floor_.mesh=plane;floor_.position.y=-.1;floor_.material_override=_mat(Color('#37444b'));add_child(floor_)
 var wall:=MeshInstance3D.new();barrier_view=wall;var shape:=BoxMesh.new();shape.size=Vector3(.5,3.5,4.5)
 wall.mesh=shape;wall.position=Vector3(.25,1.75,0)
 var wall_mat:=_mat(Color(.65,.70,.7,.26));wall_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
 wall.material_override=wall_mat;add_child(wall)

func _ui() -> void:
 var canvas:=CanvasLayer.new();add_child(canvas)
 var panel:=PanelContainer.new();panel.position=Vector2(24,22);canvas.add_child(panel)
 var style:=StyleBoxFlat.new();style.bg_color=Color(.04,.08,.10,.94)
 style.content_margin_left=15;style.content_margin_right=15;style.content_margin_top=13;style.content_margin_bottom=13
 panel.add_theme_stylebox_override('panel',style)
 var column:=VBoxContainer.new();column.add_theme_constant_override('separation',9);panel.add_child(column)
 var title:=Label.new();title.text='NIVA / BAKED CRASH LIBRARY';title.add_theme_font_size_override('font_size',22);column.add_child(title)
 readout=Label.new();readout.add_theme_font_size_override('font_size',14);column.add_child(readout)
 var angle_row:=HBoxContainer.new();column.add_child(angle_row)
 var angle_label:=Label.new();angle_label.text='Impact angle';angle_row.add_child(angle_label)
 angle_control=SpinBox.new();angle_control.min_value=-180;angle_control.max_value=180;angle_control.step=1;angle_control.suffix='°';angle_control.custom_minimum_size.x=120;angle_row.add_child(angle_control)
 angle_control.value_changed.connect(func(value):launch_angle=value)
 speed_control=OptionButton.new();speed_control.add_item('60 km/h',60);speed_control.add_item('120 km/h',120);speed_control.selected=1;angle_row.add_child(speed_control)
 speed_control.item_selected.connect(func(index):launch_speed=speed_control.get_item_id(index))
 var guide:=Label.new();guide.text='0° front · ±90° sides · 180° rear';guide.add_theme_font_size_override('font_size',13);column.add_child(guide)

 for item in [['Trigger impact / select nearest bake',_manual_replay],['Record current impact',_record],['Show front and ±20°',_demo_three],['Play all saved impacts',_play_library]]:
  var button:=Button.new();button.text=item[0];button.pressed.connect(item[1]);column.add_child(button)
 slow_toggle=CheckButton.new();slow_toggle.text='Slow motion';slow_toggle.button_pressed=true;column.add_child(slow_toggle)
 grid_toggle=CheckButton.new();grid_toggle.text='Show invisible impact zones (5 × 3 × 3)';column.add_child(grid_toggle)
 var barrier_toggle:=CheckButton.new();barrier_toggle.text='Show barrier';barrier_toggle.button_pressed=true;barrier_toggle.toggled.connect(func(value):barrier_view.visible=value);column.add_child(barrier_toggle)
 var overlay:=CheckButton.new();overlay.text='Structure overlay';overlay.toggled.connect(func(value):view.show_frame=value;view.set_mode(view.mode));column.add_child(overlay)
 var help:=Label.new();help.text='Space replay · L record · Z zones · 1–4 views\nDrag orbit · Scroll zoom · Esc close';help.add_theme_font_size_override('font_size',13);column.add_child(help)
 var bottom:=VBoxContainer.new();bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
 bottom.offset_left=24;bottom.offset_right=-24;bottom.offset_top=-65;bottom.offset_bottom=-20;canvas.add_child(bottom)
 var label:=Label.new();label.text='Baked clip — inspect the recorded deformation';bottom.add_child(label)
 replay_slider=HSlider.new();replay_slider.min_value=0;replay_slider.max_value=1;replay_slider.step=.001
 replay_slider.value_changed.connect(_scrub);bottom.add_child(replay_slider)

func _record() -> void:
 yaw=1.45-deg_to_rad(launch_angle)
 playlist.clear()
 recorder=Recorder.new();recorder.start(launch_angle,launch_speed)
 _bind_graph(recorder.vehicle.solver)
 mode='LIVE RECORDING';accumulator=0;hold_time=0
 replay_slider.editable=false
func _manual_replay() -> void:
 playlist.clear();_replay()
func _demo_three() -> void:
 playlist=[{'angle':0.0,'speed':120.0},{'angle':20.0,'speed':120.0},{'angle':-20.0,'speed':120.0}]
 playlist_index=0;_playlist_start()
func _play_library() -> void:
 playlist=[]
 for clip in library:playlist.append({'angle':clip.metadata.heading_deg,'speed':clip.metadata.speed_kmh})
 playlist_index=0;_playlist_start()
func _playlist_start() -> void:
 launch_angle=playlist[playlist_index].angle;launch_speed=playlist[playlist_index].speed
 angle_control.value=launch_angle;speed_control.selected=0 if launch_speed==60 else 1
 _replay()
func _replay() -> void:
 yaw=1.45-deg_to_rad(launch_angle)
 player.setup_library(library,launch_angle,launch_speed)
 _bind_graph(player.vehicle.solver)
 mode='BAKED APPROACH';accumulator=0;hold_time=0
 replay_slider.editable=true
func _bind_graph(graph: RefCounted) -> void:
 solver=graph
 if view.solver==graph:return
 var prior_mode: int=view.mode;var prior_frame: bool=view.show_frame
 remove_child(view);view.queue_free()
 view=Node3D.new();view.set_script(SkinView);add_child(view)
 view.setup(graph,player.vehicle.profile.model)
 view.show_frame=prior_frame;view.set_mode(prior_mode)
func _scrub(value: float) -> void:
 if guard:return
 if player.match_result.is_empty() or not player.match_result.get('accepted',false):return
 playlist.clear()
 mode='BAKED INSPECTION'
 player.time=value*float(data.metadata.duration_s)
 player.state='COMPLETE'
 solver=player.vehicle.solver;view.solver=solver
 player.apply_pose(player.time)

func _physics_process(dt: float) -> void:
 var scaled: float=dt*(.25 if slow_toggle.button_pressed else 1.0)
 if mode=='LIVE RECORDING':
  accumulator+=scaled
  var step: float=solver.config.fixed_step_s
  while accumulator>=step and not recorder.completed:
   recorder.step();accumulator-=step
  if recorder.completed:
   data=recorder.result;Clip.save(data)
   var replaced:=false
   for i in library.size():
    if library[i].metadata.id==data.metadata.id:library[i]=data;replaced=true;break
   if not replaced:library.append(data)
   mode='LIVE RECORD SAVED';replay_slider.editable=true
 elif mode in ['BAKED APPROACH','BAKED REPLAY']:
  player.advance(scaled)
  data=player.data
  mode='BAKED REPLAY' if player.state=='REPLAY' else ('BAKED COMPLETE' if player.state=='COMPLETE' else ('NO MATCH' if player.state=='REJECTED' else 'BAKED APPROACH'))

func _process(dt: float) -> void:
 var target: Vector3=solver.station_center(2)+Vector3(0,.1,0)
 camera.position=target+Vector3(cos(yaw)*distance,height,sin(yaw)*distance)
 camera.look_at(target)
 view.update_pose()
 _zones()
 var signature: Dictionary=recorder.signature if mode.begins_with('LIVE') and recorder!=null else player.incoming
 var zone_count: int=signature.get('zones',[]).size()
 var full: int=recorder.full_steps if mode.begins_with('LIVE') and recorder!=null else player.vehicle.solver.step_count
 var cpu: float=recorder.cpu_us/1000.0 if mode.begins_with('LIVE') and recorder!=null else player.player_cpu_us/1000.0
 var score: float=player.match_result.get('score',0.0)
 var selected: String=player.match_result.get('id','Waiting for contact')
 readout.text='%s\nLibrary: %d recordings · Approach: %.0f° / %.0f km/h\nSelected: %s\nImpact zones: %d / 45   Fit: %.1f%%\nFull structural steps this run: %d\nTimed simulation/playback code: %.1f ms' %[mode,library.size(),launch_angle,launch_speed,selected,zone_count,score*100,full,cpu]
 if not player.match_result.is_empty() and not mode.begins_with('LIVE'):
  readout.text+='\n'+str(player.match_result.reason)
 if mode.begins_with('BAKED'):
  guard=true;replay_slider.value=player.time/float(data.metadata.duration_s);guard=false
 if roundtrip and mode=='LIVE RECORD SAVED':
  hold_time+=dt
  if hold_time>.75:_replay();roundtrip=false
 if not playlist.is_empty() and mode=='BAKED COMPLETE':
  hold_time+=dt
  if hold_time>.8:
   playlist_index+=1
   if playlist_index<playlist.size():_playlist_start()
   else:playlist.clear()
 if capture_mode:
  if mode=='BAKED REPLAY' and player.time>.12 and capture_stage==0:
   grid_toggle.button_pressed=true
   capture_stage=1
  elif mode=='BAKED REPLAY' and player.time>.25 and capture_stage==1:
   _save('baked_zones.png');capture_stage=2;grid_toggle.button_pressed=false
  elif mode=='BAKED COMPLETE':
   hold_time+=dt
   if hold_time>.3:
    _save('baked_complete.png');get_tree().quit()

func _zones() -> void:
 zone_lines.visible=grid_toggle.button_pressed
 if not zone_lines.visible:return
 var hit_ids: Array=[]
 var signature: Dictionary=recorder.signature if mode.begins_with('LIVE') and recorder!=null else player.incoming
 for item in signature.get('zones',[]):hit_ids.append(int(item.id))
 var basis: Basis=grid.body_basis(solver)
 var root: Vector3=solver.station_center(2)-basis*((solver.rest[8]+solver.rest[9]+solver.rest[10]+solver.rest[11])*.25)
 var cell: Vector3=grid.size/Vector3(grid.counts)
 var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES)
 var edges: Array=[[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]
 for id in 45:
  var center: Vector3=grid.cell_center(id)
  var corners: Array=[]
  for x in 2:
   for y in 2:
    for z in 2:corners.append(center+Vector3(x-.5,y-.5,z-.5)*cell)
  for edge in edges:
   mesh.surface_set_color(Color('#ffb44e') if id in hit_ids else Color('#466574'))
   mesh.surface_add_vertex(root+basis*corners[edge[0]]);mesh.surface_add_vertex(root+basis*corners[edge[1]])
 mesh.surface_end();zone_lines.mesh=mesh
func _save(name_: String) -> void:
 RenderingServer.force_draw(false)
 var frame:=get_viewport().get_texture().get_image()
 frame.save_png('res://verification/'+name_)
 frame.save_png('res://verification/'+str(player.data.metadata.id)+'_'+name_)
 print('BAKED_PREVIEW ',name_)
func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
  yaw+=event.relative.x*.008;height=clampf(height+event.relative.y*.012,.3,6)
 if event is InputEventMouseButton and event.pressed:
  if event.button_index==MOUSE_BUTTON_WHEEL_UP:distance=maxf(3.5,distance-.5)
  elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:distance=minf(14,distance+.5)
 if event is InputEventKey and event.pressed and not event.echo:
  match event.physical_keycode:
   KEY_SPACE:_manual_replay()
   KEY_L:_record()
   KEY_Z:grid_toggle.button_pressed=not grid_toggle.button_pressed
   KEY_1,KEY_2,KEY_3,KEY_4:view.set_mode(event.physical_keycode-KEY_1)
   KEY_ESCAPE:get_tree().quit()
