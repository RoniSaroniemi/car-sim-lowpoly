extends Node3D
const Fixture=preload('res://probes/panels/fixtures.gd')
const PanelSkin=preload('res://probes/panels/panel_skin.gd')
var fixture: RefCounted
var view: Node3D
var camera: Camera3D
var obstacle_mesh: MeshInstance3D
var readout: Label
var sliders: Dictionary={}
var current_case:='controls'
var accumulator:=0.0
var paused:=false
var replaying:=false
var replay_time:=0.0
var replay_duration:=2.5
var yaw:=.70
var elevation:=2.8
var distance:=6.3
var inner_view:=false
var capture_mode:=false
var captures: Array=[]
var capture_index:=0
var capture_wait:=0
var pending_capture:=''
var slow_toggle: CheckButton
var hud_panel: Control

func _ready() -> void:
 DisplayServer.window_set_title('Niva / opening, bending and breakable panel probe')
 _world();_hud()
 camera=Camera3D.new();camera.current=true;camera.fov=47;add_child(camera)
 var fill:=DirectionalLight3D.new();fill.light_energy=.35;camera.add_child(fill)
 _start('controls')
 capture_mode='--capture-panels' in OS.get_cmdline_user_args()
 if capture_mode:
  captures=[['controls','intact_closed',.18],['open_controls','intact_open',2.3],['closed_medium','closed_deformed',.45],['closed_medium','closed_latch_hang',1.8],['open_medium','open_strike_hang',.65],['open_severe','open_separation',.14],['open_severe','detached_aftermath',1.5],['open_inside','inside_open',2.3]]
  _capture_start()
 print('ARTICULATED_PANEL_PROBE_READY 4 operational source panels / 10 cage nodes per active panel')

func _material(color: String) -> StandardMaterial3D:
 var material:=StandardMaterial3D.new();material.albedo_color=Color(color).srgb_to_linear();material.roughness=.85;return material

func _world() -> void:
 var world:=WorldEnvironment.new();var env:=Environment.new()
 env.background_mode=Environment.BG_COLOR;env.background_color=Color('#9bafb7');env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color('#dbe8ed');env.ambient_light_energy=.6;env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
 world.environment=env;add_child(world)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-35,0);sun.light_energy=.9;sun.shadow_enabled=true;add_child(sun)
 var floor_:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(100,.2,80);floor_.mesh=box;floor_.position.y=-.1;floor_.material_override=_material('#647b80');add_child(floor_)
 obstacle_mesh=MeshInstance3D.new();var shape:=BoxMesh.new();shape.size=Vector3(.6,.65,.14);obstacle_mesh.mesh=shape;obstacle_mesh.material_override=_material('#d08a52');add_child(obstacle_mesh)

func _hud() -> void:
 var layer:=CanvasLayer.new();add_child(layer)
 var panel:=PanelContainer.new();panel.position=Vector2(18,18);panel.size=Vector2(405,760);layer.add_child(panel)
 hud_panel=panel
 var style:=StyleBoxFlat.new();style.bg_color=Color(.035,.065,.08,.9);style.content_margin_left=13;style.content_margin_right=13;style.content_margin_top=12;style.content_margin_bottom=12;panel.add_theme_stylebox_override('panel',style)
 var column:=VBoxContainer.new();column.add_theme_constant_override('separation',6);panel.add_child(column)
 var title:=Label.new();title.text='NIVA / BREAKABLE PANELS';title.add_theme_font_size_override('font_size',22);column.add_child(title)
 readout=Label.new();readout.add_theme_font_size_override('font_size',14);column.add_child(readout)
 var grid:=GridContainer.new();grid.columns=2;column.add_child(grid)
 for item in [['Controls / repair','controls'],['Closed / moderate','closed_medium'],['Closed / severe','closed_severe'],['Open / moderate','open_medium'],['Open / severe','open_severe'],['Open / missed','missed_open'],['Closed / weak','weak_closed']]:
  var button:=Button.new();button.text=item[0];button.pressed.connect(_start.bind(item[1]));grid.add_child(button)
 for item in [['door_left','Left door'],['door_right','Right door'],['bonnet','Bonnet'],['tailgate','Rear hatch']]:
  var label:=Label.new();label.text=item[1]+' opening';column.add_child(label)
  var slider:=HSlider.new();slider.min_value=0;slider.max_value=82 if item[0]!='tailgate' else 95;slider.step=1;column.add_child(slider)
  slider.value_changed.connect(_set_open.bind(item[0]));sliders[item[0]]=slider
 var row:=HBoxContainer.new();column.add_child(row)
 var replay:=Button.new();replay.text='Replay saved motion';replay.pressed.connect(_replay);row.add_child(replay)
 var pause:=Button.new();pause.text='Pause / run';pause.pressed.connect(func():paused=not paused);row.add_child(pause)
 slow_toggle=CheckButton.new();slow_toggle.text='Quarter speed';slow_toggle.button_pressed=true;column.add_child(slow_toggle)
 var inside:=CheckButton.new();inside.text='Inspect from inside';inside.toggled.connect(func(value):inner_view=value);column.add_child(inside)
 var overlay:=CheckButton.new();overlay.text='Show structural graph';overlay.toggled.connect(func(value):view.show_frame=value);column.add_child(overlay)
 var help:=Label.new();help.text='R repair · Space replay · P pause · C inside\nDrag orbit · wheel zoom · Esc close\nMoving striker is an external impact fixture.\nThresholds are game parameters, not crash calibration.';help.add_theme_font_size_override('font_size',12);column.add_child(help)

func _start(name_: String) -> void:
 current_case=name_;paused=false;replaying=false;accumulator=0;replay_time=0
 fixture=Fixture.new();fixture.start(name_)
 if view!=null:remove_child(view);view.queue_free()
 view=Node3D.new();view.set_script(PanelSkin);view.panel_system=fixture.graph.panels;add_child(view);view.setup(fixture.graph);view.show_frame=false;view.set_mode(2)
 for id in sliders:sliders[id].set_value_no_signal(rad_to_deg(fixture.graph.panels.find(id).target))

func _set_open(value: float,id: String) -> void:
 if fixture==null or replaying:return
 if not fixture.graph.panels.set_open(id,value):print('PANEL_CONTROL_REJECTED damaged or detached ',id)

func _replay() -> void:
 if fixture.frames.is_empty():return
 replaying=true;replay_time=0;paused=false;replay_duration=float(fixture.frames.size()-1)/120

func _physics_process(dt: float) -> void:
 if paused:return
 var scale_: float=1 if capture_mode else (.25 if slow_toggle.button_pressed else 1.0)
 if replaying:
  replay_time=minf(replay_duration,replay_time+dt*scale_)
  fixture.graph.restore(fixture.frames[mini(floori(replay_time*120),fixture.frames.size()-1)])
  return
 accumulator+=dt*scale_
 while accumulator>=fixture.h:
  if capture_mode and fixture.time+fixture.h>float(captures[capture_index][2])+.00001:
   accumulator=0;break
  if current_case=='controls' and not capture_mode:
   fixture.graph.step(fixture.h)
   if fixture.graph.step_count%4==0:
    fixture.frames.append(fixture.graph.capture())
    if fixture.frames.size()>481:fixture.frames.pop_front()
  elif not fixture.complete:fixture.step()
  accumulator-=fixture.h

func _process(_dt: float) -> void:
 if fixture==null:return
 var g: RefCounted=fixture.graph
 var center: Vector3=g.station_center(2)
 var p: Dictionary=g.panels.find('door_left')
 var target: Vector3=center+Vector3(0,.2,0)
 var camera_distance: float=distance
 if p.detached:
  var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
  for point_ in p.points:low=low.min(point_);high=high.max(point_)
  for i in 28:low=low.min(g.points[i]);high=high.max(g.points[i])
  target=(low+high)*.5;camera_distance=maxf(distance,(high-low).length()*1.5)
 if inner_view:
  camera.position=center+Vector3(.65,.15,-.20);target=p.points[7]
 else:
  var right:=Vector3(sin(yaw),0,-cos(yaw))
  target-=right*camera_distance*.17
  camera.position=target+Vector3(cos(yaw)*camera_distance,elevation,sin(yaw)*camera_distance)
 camera.look_at(target);view.update_pose()
 obstacle_mesh.visible=not g.panels.obstacle.is_empty()
 if obstacle_mesh.visible:obstacle_mesh.position=g.panels.obstacle.center;obstacle_mesh.mesh.size=g.panels.obstacle.size
 var mode_: String='REPLAY / zero solves' if replaying else 'LIVE'
 readout.text='%s · %s · %.2f s\nLeft door %.0f° · %s\nHinges failed %d / 2 · latch %s\nPermanent panel work %.0f J\nPanel contacts %d · peak mount %.0f N\nTotal owned mass %.0f kg\nActive panels %d / 4 · panel mesh rebuilds 0' %[mode_,current_case.replace('_',' '),g.simulated_time,rad_to_deg(p.angle),'DETACHED' if p.detached else 'hanging / open' if not p.latched else 'latched',int(p.anchors[0].broken)+int(p.anchors[1].broken),'BROKEN' if p.anchors[2].broken else 'released' if not p.latched else 'engaged',p.plastic_work,p.contacts,p.maximum_force,g.panels.total_mass(),g.panels.panels.filter(func(panel_):return panel_.active).size()]
 if capture_mode:_capture_tick()

func _capture_start() -> void:
 var spec: Array=captures[capture_index]
 inner_view=spec[0]=='open_inside'
 hud_panel.visible=not inner_view
 yaw=2.2 if spec[0]=='open_severe' else .7
 _start('controls' if spec[0] in ['open_controls','open_inside'] else spec[0])
 if spec[0] in ['open_controls','open_inside']:
  fixture.graph.panels.set_open('door_left',68);fixture.graph.panels.set_open('door_right',50);fixture.graph.panels.set_open('bonnet',55);fixture.graph.panels.set_open('tailgate',65)
  for id in sliders:sliders[id].set_value_no_signal(rad_to_deg(fixture.graph.panels.find(id).target))
  current_case='capture_controls'
 pending_capture='';capture_wait=0

func _capture_tick() -> void:
 var spec: Array=captures[capture_index]
 if pending_capture=='':
  if fixture.time<float(spec[2])-fixture.h:return
  paused=true;pending_capture=spec[1];capture_wait=4;return
 capture_wait-=1
 if capture_wait>0:return
 var path: String='res://probes/panels/evidence/'+pending_capture+'.png'
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
 RenderingServer.force_draw(false);get_viewport().get_texture().get_image().save_png(path)
 print('PANEL_CAPTURE ',path,' ',JSON.stringify(fixture.metrics()))
 capture_index+=1
 if capture_index>=captures.size():get_tree().quit();return
 _capture_start()

func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):yaw+=event.relative.x*.008;elevation=clampf(elevation+event.relative.y*.01,.2,6)
 if event is InputEventMouseButton and event.pressed:
  if event.button_index==MOUSE_BUTTON_WHEEL_UP:distance=maxf(2.5,distance-.5)
  if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:distance=minf(12,distance+.5)
 if event is InputEventKey and event.pressed and not event.echo:
  match event.physical_keycode:
   KEY_R:_start('controls')
   KEY_SPACE:_replay()
   KEY_P:paused=not paused
   KEY_C:inner_view=not inner_view
   KEY_ESCAPE:get_tree().quit()
