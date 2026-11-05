extends Node3D
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Fixture=preload('res://scripts/body_impact_fixture.gd')
const SkinView=preload('res://scripts/structural_skin.gd')
var vehicle: RefCounted
var view: Node3D
var camera: Camera3D
var wall: MeshInstance3D
var readout: Label
var material_toggle: CheckButton
var scenario: String='roof_corner'
var running:=true
var yaw:=1.15
var distance:=7.3
var height:=2.1
var start_metrics: Dictionary={}
var capture_mode:=false
var capture_index:=0
var peak_saved:=false
var capture_hold:=0.0
var capture_cases: Array=Fixture.CASES.duplicate()
func _ready() -> void:
 capture_mode='--capture-body' in OS.get_cmdline_user_args()
 vehicle=Vehicle.new();vehicle.setup('res://vehicles/niva.json',false)
 _world()
 view=Node3D.new();view.set_script(SkinView);add_child(view);view.setup(vehicle.solver)
 view.show_frame=false;view.set_mode(2)
 camera=Camera3D.new();camera.current=true;camera.fov=48;add_child(camera)
 _ui()
 if '--baseline-materials' in OS.get_cmdline_user_args():material_toggle.set_pressed_no_signal(false)
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with('--capture-case='):capture_cases=[argument.trim_prefix('--capture-case=')]
 if capture_mode:scenario=capture_cases[0]
 _start(scenario)
func _mat(color: Color) -> StandardMaterial3D:
 var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.8;return mat
func _world() -> void:
 var world:=WorldEnvironment.new();var env:=Environment.new()
 env.background_mode=Environment.BG_COLOR;env.background_color=Color('#23333d')
 env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color('#c7d8df');env.ambient_light_energy=.7
 world.environment=env;add_child(world)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-42,-40,0);sun.light_energy=1.2;sun.shadow_enabled=true;add_child(sun)
 var floor_:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(100,.2,40);floor_.mesh=box;floor_.position.y=-.1
 floor_.material_override=_mat(Color('#65747c'));add_child(floor_)
 wall=MeshInstance3D.new();box=BoxMesh.new();box.size=Vector3(.5,3.5,4.5);wall.mesh=box;wall.position=Vector3(.25,1.75,0)
 var glass:=_mat(Color(.8,.85,.9,.16));glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;wall.material_override=glass;add_child(wall)
func _ui() -> void:
 var layer:=CanvasLayer.new();add_child(layer)
 var panel:=PanelContainer.new();panel.position=Vector2(22,20);layer.add_child(panel)
 var column:=VBoxContainer.new();panel.add_child(column)
 var title:=Label.new();title.text='LIVE BODY / MULTIAXIS IMPACTS';title.add_theme_font_size_override('font_size',24);column.add_child(title)
 readout=Label.new();readout.add_theme_font_size_override('font_size',15);column.add_child(readout)
 material_toggle=CheckButton.new();material_toggle.text='Experimental roof / side materials';material_toggle.button_pressed=true
 material_toggle.toggled.connect(func(_value):_start(scenario));column.add_child(material_toggle)
 for name_ in Fixture.CASES:
  var button:=Button.new();button.text=name_.replace('_',' ').capitalize();button.pressed.connect(_start.bind(name_));column.add_child(button)
 var frame:=CheckButton.new();frame.text='Structure overlay';frame.toggled.connect(func(value):view.show_frame=value;view.set_mode(view.mode));column.add_child(frame)
 var help:=Label.new();help.text='1 flat roof · 2 angled roof · 3 side wall\nSpace pause · R repeat · V plain/textured\nDrag orbit · Wheel zoom · Esc close';column.add_child(help)
func _start(name_: String) -> void:
 scenario=name_;Fixture.start(vehicle,scenario,1.0,material_toggle.button_pressed)
 start_metrics=Fixture.metrics(vehicle.solver);running=true;peak_saved=false;capture_hold=0
 wall.visible=scenario=='side_wall'
func _physics_process(dt: float) -> void:
 if running and vehicle.solver.simulated_time<3:vehicle.advance(dt,1.0 if capture_mode else .35)
func _process(dt: float) -> void:
 var g: RefCounted=vehicle.solver
 var center: Vector3=g.station_center(2)
 camera.position=center+Vector3(cos(yaw)*distance,height,sin(yaw)*distance)
 camera.look_at(center)
 view.update_pose()
 var m: Dictionary=Fixture.metrics(g)
 readout.text='%s · %s\nFull live solve / 480 Hz · %.2f s\nCabin height: %.3f m (change %+.3f)\nCabin width: %.3f m (change %+.3f)\nPlastic work: %.1f kJ · nodes %d · mass %.0f kg\nGame material probe; no calibrated crash prediction.' %[scenario,'experimental' if material_toggle.button_pressed else 'baseline',g.simulated_time,m.cabin_height_m,m.cabin_height_m-start_metrics.cabin_height_m,m.cabin_width_m,m.cabin_width_m-start_metrics.cabin_width_m,m.plastic_work_kj,g.points.size(),g.config.mass_kg]
 if capture_mode:
  if g.simulated_time>.5 and not peak_saved:
   _save(scenario+'_impact.png');peak_saved=true
  elif g.simulated_time>=3:
   capture_hold+=dt
   if capture_hold>.2:
    _save(scenario+'_final.png');capture_index+=1
    if capture_index<capture_cases.size():_start(capture_cases[capture_index])
    else:get_tree().quit()
func _save(name_: String) -> void:
 if not material_toggle.button_pressed:name_='baseline_'+name_
 RenderingServer.force_draw(false)
 get_viewport().get_texture().get_image().save_png('res://verification/'+name_)
 print('BODY_PREVIEW ',name_)
func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):yaw+=event.relative.x*.008;height=clampf(height+event.relative.y*.01,.4,5)
 if event is InputEventMouseButton and event.pressed:
  if event.button_index==MOUSE_BUTTON_WHEEL_UP:distance=maxf(4,distance-.4)
  if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:distance=minf(12,distance+.4)
 if event is InputEventKey and event.pressed and not event.echo:
  match event.physical_keycode:
   KEY_1:_start('roof_flat')
   KEY_2:_start('roof_corner')
   KEY_3:_start('side_wall')
   KEY_R:_start(scenario)
   KEY_SPACE:running=not running
   KEY_V:view.set_mode(1 if view.mode==2 else 2)
   KEY_ESCAPE:get_tree().quit()
