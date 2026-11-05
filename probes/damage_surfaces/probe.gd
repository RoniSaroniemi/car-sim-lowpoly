extends Control
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const SurfaceSkin=preload('res://probes/damage_surfaces/surface_skin.gd')
const Chassis=preload('res://scripts/roof_crash_recorder.gd')
const Field=preload('res://probes/damage_surfaces/surface_field.gd')
const CASES=[
 {'name':'LIGHT / local dent','path':'res://probes/damage_surfaces/data/light_20.crashclip','time':2.5},
 {'name':'HEAVY / left side crush','path':'res://bakes/impact_090_120.crashclip','time':1.0},
 {'name':'EXTREME / third conditioned hit','path':'res://bakes/conditioned/front_60_60_120_step_2.crashclip','time':.75}]
var views: Array=[]
var clips: Array=[]
var current_case:=0
var closeup:=false
var orbit:=.72
var chosen_time:=2.5
var header: Label
var readout: Label
var slider: HSlider
var capture_mode:=false
var capture_stage:=0
var render_ticks:=0
var samples: Array=[]
var playing:=false
var histories: Array=[]
func _ready() -> void:
 DisplayServer.window_set_title('Damage surfaces / actual recorded car comparison')
 capture_mode='--capture-surfaces' in OS.get_cmdline_user_args()
 for item in CASES:
  var data: Dictionary=Clip.read(item.path)
  assert(not data.is_empty(),'Record light probe first: '+item.path)
  clips.append(data)
 var column:=VBoxContainer.new();column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(column)
 var panel:=PanelContainer.new();column.add_child(panel)
 var summary:=VBoxContainer.new();panel.add_child(summary)
 header=Label.new();header.add_theme_font_size_override('font_size',24);summary.add_child(header)
 readout=Label.new();readout.add_theme_font_size_override('font_size',16);summary.add_child(readout)
 var row:=HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(row)
 for index in 3:
  var cell:=VBoxContainer.new();cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(cell)
  var label:=Label.new();label.text=['ORIGINAL TEXTURES / skin only','CURRENT / section stripes + folds','PROBE / local layered materials'][index];label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.add_theme_font_size_override('font_size',18);cell.add_child(label)
  var container:=SubViewportContainer.new();container.size_flags_vertical=Control.SIZE_EXPAND_FILL;container.size_flags_horizontal=Control.SIZE_EXPAND_FILL;container.stretch=true;cell.add_child(container)
  var viewport:=SubViewport.new();viewport.size=Vector2i(640,820);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;container.add_child(viewport)
  var stage:=Node3D.new();viewport.add_child(stage)
  _environment(stage)
  var car:=Vehicle.new();car.setup('res://vehicles/niva.json',false)
  var skin:=Node3D.new();skin.set_script(SurfaceSkin);skin.appearance=index;stage.add_child(skin);skin.setup(car.solver);skin.show_frame=false;skin.set_mode(2)
  var camera:=Camera3D.new();camera.current=true;camera.fov=38;stage.add_child(camera)
  views.append({'viewport':viewport,'skin':skin,'car':car,'camera':camera})
 var buttons:=HFlowContainer.new();column.add_child(buttons)
 for data in clips:histories.append(Field.history(views[0].car.solver,data))
 for index in 3:
  var button:=Button.new();button.text=CASES[index].name;button.pressed.connect(_select.bind(index));buttons.add_child(button)
 var replay:=Button.new();replay.text='Replay';replay.pressed.connect(func():chosen_time=0;playing=true);buttons.add_child(replay)
 for item in [['Close-up',func(value):closeup=value;_camera()],['Section folds',func(value):_layer('section_folds',value)],['Normal creases',func(value):_layer('normal_layer',value)],['Paint / metal',func(value):_layer('paint_layer',value)],['Roughness',func(value):_layer('roughness_layer',value)],['Masks',func(value):_layer('masks_debug',value)],['Plain geometry',func(value):_plain(value)]]:
  var toggle:=CheckButton.new();toggle.text=item[0];toggle.button_pressed=item[0] in ['Section folds','Normal creases','Paint / metal','Roughness'];toggle.toggled.connect(item[1]);buttons.add_child(toggle)
 slider=HSlider.new();slider.min_value=0;slider.max_value=2.5;slider.step=1.0/120;slider.value=2.5;slider.value_changed.connect(_sample);column.add_child(slider)
 var help:=Label.new();help.text='Same saved frame, camera and lighting in all columns. No live physics. 1/2/3 cases · C close-up · drag orbit · Esc close';column.add_child(help)
 _select(0)
 print('SURFACE_PROBE_READY three actual states / same-pose comparisons')
func _environment(root_: Node3D) -> void:
 var world:=WorldEnvironment.new();var env:=Environment.new();var sky:=Sky.new();var sky_mat:=ProceduralSkyMaterial.new()
 sky_mat.sky_top_color=Color('#344b65');sky_mat.sky_horizon_color=Color('#bfcbd1');sky_mat.ground_bottom_color=Color('#253139');sky_mat.ground_horizon_color=Color('#a1a9aa');sky.sky_material=sky_mat
 env.background_mode=Environment.BG_SKY;env.sky=sky;env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY;env.ambient_light_energy=.65;env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY;env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;world.environment=env;root_.add_child(world)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-42,-35,0);sun.light_energy=1.15;sun.shadow_enabled=true;root_.add_child(sun)
 var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-15,130,0);fill.light_energy=.4;root_.add_child(fill)
 var floor_:=MeshInstance3D.new();var plane:=BoxMesh.new();plane.size=Vector3(40,.15,40);floor_.mesh=plane;floor_.position.y=-.075;var material:=StandardMaterial3D.new();material.albedo_color=Color('#586773');material.roughness=.85;floor_.material_override=material;root_.add_child(floor_)
func _select(index: int) -> void:
 current_case=index;chosen_time=CASES[index].time
 if slider!=null:slider.set_value_no_signal(chosen_time)
 _sample(chosen_time)
func _sample(time_: float) -> void:
 chosen_time=time_
 var data: Dictionary=clips[current_case]
 var source_origin:=Vector3(data.metadata.origin[0],data.metadata.origin[1],data.metadata.origin[2])
 for item in views:
  var g: RefCounted=item.car.solver
  var registration:=Basis(Vector3.UP,deg_to_rad(-float(data.metadata.heading_deg)))
  Clip.apply(g,data,time_,registration*source_origin,registration)
  # Inspection registration only: remove rigid roll/yaw, retain all deformation.
  var canonical: Basis=Chassis.full_chassis_basis(g).transposed()
  var center: Vector3=g.station_center(2)
  var lowest:=INF
  for node in g.points.size():
   g.points[node]=canonical*(g.points[node]-center)
   g.velocities[node]=canonical*g.velocities[node]
   lowest=minf(lowest,g.points[node].y-g.radii[node])
  for node in g.points.size():g.points[node].y-=lowest
  var wheel_state: Array=g.wheels.capture()
  for wheel in wheel_state:wheel.rotation=(canonical.get_rotation_quaternion()*wheel.rotation).normalized();wheel.angular_velocity=canonical*wheel.angular_velocity
  g.wheels.restore(wheel_state)
  var n: Array=data.metadata.signature.normal
  item.skin.field.compression_override=histories[current_case][clampi(roundi(time_*120),0,data.frames.size()-1)]
  item.skin.collision_direction=-Vector3(n[0],n[1],n[2]);item.skin.apply_layers();item.skin.update_pose()
 var graph: RefCounted=views[0].car.solver
 var metrics: Dictionary=graph.metrics()
 var width_loss: float=((graph.rest[9]-graph.rest[8]).length()+(graph.rest[13]-graph.rest[12]).length()-(graph.points[9]-graph.points[8]).length()-(graph.points[13]-graph.points[12]).length())*.5
 header.text='NIVA / '+CASES[current_case].name+'   ·   '+('CLOSE-UP' if closeup else 'OVERALL')
 readout.text='Recorded %.2f s · front loss %.0f mm · cabin length/width loss %.0f / %.0f mm · plastic work %.1f kJ · live solver steps: %d'%[time_,metrics.front_shortening_m*1000,metrics.cabin_shortening_m*1000,maxf(0,width_loss)*1000,metrics.plastic_work_kj,graph.step_count]
 _camera()
func _camera() -> void:
 for item in views:
  var g: RefCounted=item.car.solver
  var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
  for i in 34:low=low.min(g.points[i]);high=high.max(g.points[i])
  var target: Vector3=(low+high)*.5
  if closeup:
   target=(g.station_center(4)+g.station_center(6))*.5 if current_case==0 else g.station_center(2)
  var radius: float=4.0 if closeup else (6.3 if current_case==2 else 9.2)
  var heading: float=orbit+.65 if current_case==1 else orbit
  item.camera.position=target+Vector3(cos(heading)*radius,(.9 if closeup and current_case==1 else 1.9),sin(heading)*radius)
  item.camera.look_at(target)
 header.text='NIVA / '+CASES[current_case].name+'   ·   '+('CLOSE-UP' if closeup else 'OVERALL')
func _layer(name_: String,value: bool) -> void:
 for item in views:item.skin.set(name_,value);item.skin.apply_layers()
func _plain(value: bool) -> void:
 for item in views:item.skin.detail_enabled=not value;item.skin.set_mode(1 if value else 2)
func _process(_dt: float) -> void:
 if playing:
  chosen_time=minf(2.5,chosen_time+_dt*.25);slider.set_value_no_signal(chosen_time);_sample(chosen_time)
  if chosen_time>=2.5:playing=false
 if not capture_mode:return
 render_ticks+=1
 if render_ticks<8:return
 render_ticks=0
 var suffix: String='close' if closeup else 'overall'
 if capture_stage==6:suffix='mask'
 if capture_stage==7:suffix='plain'
 var path: String='res://probes/damage_surfaces/evidence/%s_%s.png'%[['light','heavy','extreme'][current_case],suffix]
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
 RenderingServer.force_draw(false);get_viewport().get_texture().get_image().save_png(path)
 var metrics: Dictionary=views[0].car.solver.metrics()
 samples.append({'case':CASES[current_case].name,'time':chosen_time,'closeup':closeup,'file':path,'metrics':metrics})
 print('SURFACE_CAPTURE ',path)
 capture_stage+=1
 if capture_stage>=8:
  FileAccess.open('res://probes/damage_surfaces/evidence/states.json',FileAccess.WRITE).store_string(JSON.stringify(samples,'\t'))
  get_tree().quit();return
 if capture_stage<6:
  closeup=capture_stage%2==1;_select(capture_stage/2)
 elif capture_stage==6:
  closeup=true;_layer('masks_debug',true);_select(1)
 else:
  _layer('masks_debug',false);_plain(true);closeup=true;_select(2)
func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):orbit+=event.relative.x*.008;_camera()
 if event is InputEventKey and event.pressed and not event.echo:
  match event.physical_keycode:
   KEY_1:_select(0)
   KEY_2:_select(1)
   KEY_3:_select(2)
   KEY_C:closeup=not closeup;_camera()
   KEY_ESCAPE:get_tree().quit()
