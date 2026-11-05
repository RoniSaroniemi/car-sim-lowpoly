extends Node3D
const Graph=preload('res://scripts/structure_solver.gd')
const Glass=preload('res://scripts/vehicle_glass.gd')
const SkinView=preload('res://scripts/structural_skin.gd')
var graph: RefCounted
var glass: RefCounted
var skin: Node3D
var visual: Node3D
var camera: Camera3D
var label: Label
var clock:=0.0
var recorded: Array=[]
var playback:=false
var replay_index:=0
var capture_mode:=false
var phase:=0
var rotation_start:=0.0
func _ready() -> void:
 capture_mode='--capture-glass-car' in OS.get_cmdline_user_args()
 DisplayServer.window_set_title('Niva glass — live membrane and baked playback')
 var environment:=WorldEnvironment.new();var e:=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color('#34434b');e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color('#d2dfe5');e.ambient_light_energy=.75;environment.environment=e;add_child(environment)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-35,0);sun.light_energy=.9;sun.shadow_enabled=true;add_child(sun)
 var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-25,145,0);fill.light_energy=.7;add_child(fill)
 var floor_:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(30,.2,30);floor_.mesh=box;floor_.position.y=-.1;var mat:=StandardMaterial3D.new();mat.albedo_color=Color('#45594f');floor_.material_override=mat;add_child(floor_)
 graph=Graph.new();graph.setup();graph.reset(0,Vector3.ZERO);graph.barrier_enabled=false
 glass=Glass.new();glass.setup(graph)
 skin=Node3D.new();skin.set_script(SkinView);add_child(skin);skin.setup(graph);skin.show_frame=false;skin.set_mode(2)
 visual=glass.create_visual(skin,skin.body);skin.add_child(visual)
 camera=Camera3D.new();camera.position=Vector3(4.2,2.6,3.8);camera.fov=40;camera.current=true;add_child(camera);camera.look_at(Vector3(0,1,0))
 var canvas:=CanvasLayer.new();add_child(canvas);var panel:=PanelContainer.new();panel.position=Vector2(20,20);canvas.add_child(panel)
 var style:=StyleBoxFlat.new();style.bg_color=Color(.02,.05,.06,.95);style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=10;style.content_margin_bottom=10;panel.add_theme_stylebox_override('panel',style)
 var column:=VBoxContainer.new();panel.add_child(column);label=Label.new();column.add_child(label)
 for entry in [['Hit windscreen / piercing',func():_hit()],['Shatter left side panes',func():glass.hit_window('door_left',1.3);glass.hit_window('quarter_left',1.3)],['Replay recording',_replay],['Repair glass',func():glass.reset();recorded.clear();playback=false]]:
  var button:=Button.new();button.text=entry[0];button.pressed.connect(entry[1]);column.add_child(button)
 print('GLASS_CAR_PROBE_READY panes=',glass.panes.size(),' visuals=',visual.records.size())
func _hit() -> void:
 glass.hit_window('windscreen',2.0,true)
 recorded=[glass.capture()];playback=false
func _replay() -> void:
 if recorded.is_empty():return
 glass.begin_playback(recorded[0]);playback=true;replay_index=0
func _physics_process(dt: float) -> void:
 clock+=dt
 if playback:
  replay_index=mini(replay_index+1,recorded.size()-1)
  glass.restore_interpolated(recorded[replay_index],recorded[replay_index],0)
 else:
  glass.step_live(dt)
  if not recorded.is_empty():recorded.append(glass.capture())
 glass.step_debris(dt)
func _process(_dt: float) -> void:
 skin.update_pose();visual.update_visual()
 var wind: Dictionary=glass.capture().panes.windscreen
 label.text='ACTUAL NIVA / GLASS\n%s · %d panes\nWindscreen: stage %d / %d broken bonds\nMembrane solves: %d\nDebris %d / 192' %['BAKED' if playback else 'LIVE',glass.panes.size(),wind.stage,Array(wind.broken).count(1),glass.membrane_solve_steps,glass.debris.size()]
 if capture_mode:
  if phase==0 and clock>.2:
   _save('glass_car_intact.png');_hit();glass.hit_window('door_left',1.3);glass.hit_window('quarter_left',1.3);phase=1
  elif phase==1 and clock>.55:
   _save('glass_car_live.png');phase=2
  elif phase==2 and clock>2.3:_replay();phase=3
  elif phase==3 and replay_index>35:
   _save('glass_car_replay.png');playback=false;recorded.clear();glass.reset()
   var yaw:=Basis(Vector3.UP,1.2)
   for i in graph.points.size():
    var point: Vector3=graph.rest[i]
    if point.y>1.4:point+=Vector3(.10,-.12,0)
    graph.points[i]=yaw*point;graph.velocities[i]=Vector3.ZERO
   glass.synchronize();glass.hit_window('windscreen',1.8,false)
   camera.position=yaw*Vector3(4.2,2.6,3.8);camera.look_at(Vector3(0,1,0));rotation_start=clock;phase=4
  elif phase==4 and clock>rotation_start+.5:
   _save('glass_car_rotated_retained.png');print('GPU_ROTATED_MOUNT_ERROR ',_boundary_error());get_tree().quit()
func _save(name_: String) -> void:
 RenderingServer.force_draw(false);get_viewport().get_texture().get_image().save_png('res://verification/'+name_);print('GLASS_CAR_PREVIEW ',name_,' ',JSON.stringify(glass.statistics()))

func _boundary_error() -> float:
 var error:=0.0;var Attachment=load('res://scripts/car_attachment.gd')
 for pane in glass.panes.values():
  if pane.membrane==null:continue
  var targets: PackedVector3Array=glass._node_world(pane,Attachment.rotations(graph))
  for i in targets.size():
   if pane.membrane.anchored[i]:error=maxf(error,pane.membrane.points[i].distance_to(targets[i]))
 return error
