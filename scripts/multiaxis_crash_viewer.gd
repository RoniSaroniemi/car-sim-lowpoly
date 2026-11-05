extends Node3D
## Explicit 3D bank inspection. No yaw matcher and no full solver during replay.
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Player=preload('res://scripts/baked_crash_player.gd')
const Skin=preload('res://scripts/damage_skin.gd')
var vehicle: RefCounted
var player: RefCounted
var data: Dictionary={}
var library: Array=[]
var paths: Array=[]
var view: Node3D
var camera: Camera3D
var label: Label
var slider: HSlider
var paused:=false
var guard:=false
var yaw:=.85
var height:=2.9
var distance:=7.5
var capture_path: String=''
var capture_time:=.4
var capture_wait:=0
var selected:=0
func _ready() -> void:
 var explicit: String=''
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with('--clip='):explicit=argument.trim_prefix('--clip=')
  elif argument.begins_with('--capture='):capture_path=argument.trim_prefix('--capture=')
  elif argument.begins_with('--time='):capture_time=float(argument.trim_prefix('--time='))
 if not explicit.is_empty():paths=[explicit]
 else:
  var directory:=DirAccess.open('res://bakes/multiaxis')
  if directory!=null:
   var names:=directory.get_files();names.sort()
   for name in names:
    if name.ends_with('.crashclip'):paths.append('res://bakes/multiaxis/'+name)
 for path in paths:library.append(Clip.read(path))
 assert(not library.is_empty(),'Bake or provide --clip=res://bakes/multiaxis/top_60.crashclip first')
 vehicle=Vehicle.new();vehicle.setup('res://vehicles/niva.json',false)
 _world()
 view=Node3D.new();view.set_script(Skin);add_child(view);view.setup(vehicle.solver,vehicle.profile.model);view.show_frame=false;view.set_mode(2)
 camera=Camera3D.new();camera.current=true;camera.fov=45;add_child(camera)
 var fill:=DirectionalLight3D.new();fill.light_energy=.6;camera.add_child(fill)
 _ui();_select(0)
 if not capture_path.is_empty():paused=true;Clip.apply(vehicle.solver,data,capture_time,_origin());slider.set_value_no_signal(capture_time)
func _origin() -> Vector3:
 var p: Array=data.metadata.origin;return Vector3(p[0],p[1],p[2])
func _select(index: int) -> void:
 selected=index;data=library[index]
 vehicle.reset(0,Vector3.ZERO);vehicle.solver.barrier_enabled=false
 vehicle.solver.effects.begin_playback(data.frames[0].effects)
 Clip.apply(vehicle.solver,data,0,_origin())
 player=Player.new();player.attach_live(vehicle,[data],data.metadata.signature,{'accepted':true,'index':0,'id':data.metadata.id})
 slider.max_value=data.metadata.duration_s;slider.set_value_no_signal(0);paused=false
func _ui() -> void:
 var layer:=CanvasLayer.new();add_child(layer)
 var panel:=PanelContainer.new();panel.position=Vector2(20,20);layer.add_child(panel)
 var column:=VBoxContainer.new();panel.add_child(column)
 var title:=Label.new();title.text='NIVA / TOP, UNDERSIDE & DIAGONAL IMPACTS';title.add_theme_font_size_override('font_size',21);column.add_child(title)
 var picker:=OptionButton.new()
 for clip in library:picker.add_item(clip.metadata.id.replace('_',' '))
 picker.item_selected.connect(_select);column.add_child(picker)
 var repeat:=Button.new();repeat.text='Replay impact';repeat.pressed.connect(func():_select(selected));column.add_child(repeat)
 var frame:=CheckButton.new();frame.text='Structure overlay';frame.toggled.connect(func(value):view.show_frame=value;view.set_mode(view.mode));column.add_child(frame)
 label=Label.new();column.add_child(label)
 var help:=Label.new();help.text='Space pause · R replay · Drag orbit · Scroll zoom · Esc close';column.add_child(help)
 slider=HSlider.new();slider.position=Vector2(24,660);slider.size=Vector2(1100,25);slider.min_value=0;slider.step=.001
 slider.value_changed.connect(func(value):
  if guard:return
  paused=true;Clip.apply(vehicle.solver,data,value,_origin()))
 layer.add_child(slider)
func _world() -> void:
 var world:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color('#293944');env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color('#e3ecf0');env.ambient_light_energy=.65;world.environment=env;add_child(world)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.light_energy=1.0;sun.shadow_enabled=true;add_child(sun)
 var floor_:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(100,.2,100);floor_.mesh=box;floor_.position.y=-.1
 var material:=StandardMaterial3D.new();material.albedo_color=Color('#63737b');material.roughness=.9;floor_.material_override=material;add_child(floor_)
func _process(dt: float) -> void:
 if player==null:return
 if not paused and player.state=='REPLAY':player.advance(minf(dt,.05)*.35);slider.set_value_no_signal(player.time)
 var g: RefCounted=vehicle.solver;var center: Vector3=g.station_center(2)
 camera.position=center+Vector3(cos(yaw)*distance,height,sin(yaw)*distance);camera.look_at(center);view.update_pose()
 label.text='%s · %.2f / %.1f s\nRecorded at %d Hz · 120 samples/s\n%.0f kg · live body/cage solves: %d / %d'%[data.metadata.direction_key,slider.value,data.metadata.duration_s,data.metadata.physics_hz,g.owned_mass_kg(),g.step_count,g.panels.active_steps]
 if not capture_path.is_empty():
  capture_wait+=1
  if capture_wait>=4:
   RenderingServer.force_draw(false);get_viewport().get_texture().get_image().save_png(capture_path);print('MULTIAXIS_PREVIEW ',capture_path);get_tree().quit()
func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):yaw+=event.relative.x*.008;height=clampf(height+event.relative.y*.01,.3,7)
 if event is InputEventMouseButton and event.pressed:
  if event.button_index==MOUSE_BUTTON_WHEEL_UP:distance=maxf(4,distance-.4)
  if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:distance=minf(15,distance+.4)
 if event is InputEventKey and event.pressed and not event.echo:
  match event.physical_keycode:
   KEY_SPACE:paused=not paused
   KEY_R:_select(selected)
   KEY_ESCAPE:get_tree().quit()
