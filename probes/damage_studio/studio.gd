extends Control
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const SkinView=preload('res://probes/damage_studio/studio_skin.gd')
const Chassis=preload('res://scripts/roof_crash_recorder.gd')
const Field=preload('res://probes/damage_surfaces/surface_field.gd')
const HOME='res://probes/damage_studio/'
const CASES=[
 {'name':'Intact paint reference','path':'res://probes/damage_surfaces/data/light_20.crashclip','time':0.,'angle':.72},
 {'name':'Light frontal dent','path':'res://probes/damage_surfaces/data/light_20.crashclip','time':2.5,'angle':.72},
 {'name':'Early corner contact','path':'res://bakes/impact_030_60.crashclip','time':1.0/120.0,'angle':.85},
 {'name':'Frontal crush','path':'res://bakes/impact_000_60.crashclip','time':1.,'angle':.72},
 {'name':'Oblique crush','path':'res://bakes/impact_030_60.crashclip','time':1.,'angle':.85},
 {'name':'Heavy side compression','path':'res://bakes/impact_090_120.crashclip','time':1.,'angle':1.4},
 {'name':'Rear crush','path':'res://bakes/impact_180_60.crashclip','time':1.,'angle':2.5},
 {'name':'Third-hit cabin crumple','path':'res://bakes/conditioned/front_60_60_120_step_2.crashclip','time':.75,'angle':.72},
 {'name':'Roof corner crush','path':'res://bakes/roof/roof_corner_35.crashclip','time':1.,'angle':-2.2}]
var views: Array=[]
var preset: Dictionary={}
var layers={'section_folds':true,'normal_layer':true,'paint_layer':true,'roughness_layer':true,'masks_debug':false}
var selected: int=-1
var appearance: int=2
var plain:=false
var previous_variant:=false
var orbit:=0.
var elevation:=.35
var distance:=5.2
var grid: GridContainer
var focus: TextureRect
var title: Label
var status: Label
var preset_name: LineEdit
var sliders: Dictionary={}
var busy_capture:=false
var revision:=0
var load_ms:=0.
var last_edit_ms:=0.
var auto_capture:=false
var stats: Array=[]
var tick:=0
var frame_samples: Array=[]
var phase:=0
var phase_tick:=0
var measurements: Dictionary={}
var evidence_busy:=false

func _ready() -> void:
 var began: int=Time.get_ticks_usec()
 DisplayServer.window_set_title('NIVA • Damage Material Studio • nine saved cases')
 Engine.max_fps=60
 auto_capture='--studio-capture' in OS.get_cmdline_user_args()
 var background:=ColorRect.new();background.color=Color('#16212b');background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(background)
 var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for side in ['left','right','top','bottom']:margin.add_theme_constant_override('margin_'+side,10)
 add_child(margin)
 var column:=VBoxContainer.new();margin.add_child(column)
 title=Label.new();title.add_theme_font_size_override('font_size',22);column.add_child(title)
 var actions:=HFlowContainer.new();column.add_child(actions)
 _button(actions,'Board [0 / Esc]',func():select_case(-1))
 for pair in [['Layers [B]',2],['Section baseline',1],['Original paint',0]]:
  _button(actions,pair[0],func():appearance=pair[1];apply_materials())
 _button(actions,'Previous / new [V]',func():previous_variant=not previous_variant;apply_materials())
 _button(actions,'Reload [R]',load_preset)
 preset_name=LineEdit.new();preset_name.text='current';preset_name.custom_minimum_size.x=125;actions.add_child(preset_name)
 _button(actions,'Load named',load_preset)
 _button(actions,'Save named',save_preset)
 _button(actions,'Capture [P]',capture)
 var toggles:=HBoxContainer.new();column.add_child(toggles)
 for pair in [['Folds','section_folds'],['Normals','normal_layer'],['Coating / metal','paint_layer'],['Roughness','roughness_layer'],['Masks','masks_debug']]:
  var toggle:=CheckButton.new();toggle.text=pair[0];toggle.button_pressed=layers[pair[1]];toggles.add_child(toggle)
  toggle.toggled.connect(func(value):layers[pair[1]]=value;apply_materials())
 var plain_button:=CheckButton.new();plain_button.text='Plain geometry';toggles.add_child(plain_button);plain_button.toggled.connect(func(value):plain=value;apply_materials())
 var controls:=HFlowContainer.new();column.add_child(controls)
 for spec in [['Paint loss','paint_loss',0.,2.],['Loss threshold','loss_threshold',-.3,.5],['Pattern scale','pattern_scale',.3,3.],['Creases','crease_strength',0.,4.],['Crease scale','crease_scale',.3,3.],['Folds','fold_strength',0.,3.],['Metal rough','metal_roughness',.15,.95],['Paint scuff','scuff_strength',0.,1.5],['Peel edge','peel_strength',0.,3.],['Grime','grime_amount',0.,1.],['Grime trail','grime_trail',0.,.4],['Impact spread','impact_spread',.5,1.6]]:
  var group:=HBoxContainer.new();controls.add_child(group)
  var label:=Label.new();label.text=spec[0];group.add_child(label)
  var slider:=HSlider.new();slider.custom_minimum_size.x=100;slider.min_value=spec[2];slider.max_value=spec[3];slider.step=.01;group.add_child(slider);sliders[spec[1]]=slider
  slider.value_changed.connect(func(value):preset[spec[1]]=value;apply_materials())
 grid=GridContainer.new();grid.columns=3;grid.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(grid)
 focus=TextureRect.new();focus.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;focus.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;focus.size_flags_vertical=Control.SIZE_EXPAND_FILL;focus.visible=false;column.add_child(focus);focus.gui_input.connect(_focus_input)
 var cache: Dictionary={}
 for index in CASES.size():
  var definition: Dictionary=CASES[index]
  var cell:=VBoxContainer.new();cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL;cell.size_flags_vertical=Control.SIZE_EXPAND_FILL;grid.add_child(cell)
  var label:=Label.new();label.text='%d  /  %s'%[index+1,definition.name];label.add_theme_font_size_override('font_size',17);cell.add_child(label)
  var vp:=SubViewport.new();vp.size=Vector2i(640,320);vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(vp)
  RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(),true)
  var stage:=Node3D.new();vp.add_child(stage);_environment(stage)
  var car:=Vehicle.new();car.setup('res://vehicles/niva.json',false)
  var skin:=Node3D.new();skin.set_script(SkinView);stage.add_child(skin);skin.setup(car.solver);skin.show_frame=false;skin.set_mode(2);skin.studio_materials()
  var camera:=Camera3D.new();camera.current=true;camera.fov=38;stage.add_child(camera)
  if not cache.has(definition.path):
   var data: Dictionary=Clip.read(definition.path);assert(not data.is_empty(),definition.path)
   cache[definition.path]={'clip':data,'history':Field.history(car.solver,data)}
  var item: Dictionary={'viewport':vp,'skin':skin,'car':car,'camera':camera}
  views.append(item);_freeze(index,cache[definition.path])
  var image_rect:=TextureRect.new();image_rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image_rect.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;image_rect.size_flags_vertical=Control.SIZE_EXPAND_FILL;image_rect.texture=vp.get_texture();cell.add_child(image_rect)
  image_rect.gui_input.connect(func(event):
   if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:select_case(index))
  var metrics:=Label.new();metrics.text='%.2fs · front %.0fmm · cabin %.0fmm · %.1fkJ'%[definition.time,item.metrics.front_shortening_m*1000,item.metrics.cabin_shortening_m*1000,item.metrics.plastic_work_kj]
  if index==6:metrics.text='%.2fs · cabin %.0fmm · %.1fkJ'%[definition.time,item.metrics.cabin_shortening_m*1000,item.metrics.plastic_work_kj]
  if index==5:metrics.text='%.2fs · width loss %.0fmm · %.1fkJ'%[definition.time,item.width_loss*1000,item.metrics.plastic_work_kj]
  if index==8:metrics.text='%.2fs · roof drop %.0fmm · %.1fkJ'%[definition.time,item.metrics.roof_drop_m*1000,item.metrics.plastic_work_kj]
  cell.add_child(metrics)
 status=Label.new();status.add_theme_font_size_override('font_size',13);column.add_child(status)
 var help:=Label.new();help.text='1–9 focus · drag orbit · wheel zoom · C close-up · B same-frame baseline / layers · R reload JSON · P capture · 0 / Esc board';column.add_child(help)
 load_ms=(Time.get_ticks_usec()-began)/1000.
 load_preset();select_case(-1)
 FileAccess.open(HOME+'captures/cases.json',FileAccess.WRITE).store_string(JSON.stringify(stats,'	'))
 print('DAMAGE_STUDIO_READY nine frozen cases, load_ms=',load_ms,' pid=',OS.get_process_id())

func _button(parent: Node,label: String,action: Callable) -> void:
 var button:=Button.new();button.text=label;button.pressed.connect(action);parent.add_child(button)

func _freeze(index: int,entry: Dictionary) -> void:
 var item: Dictionary=views[index];var g: RefCounted=item.car.solver
 var data: Dictionary=entry.clip;var definition: Dictionary=CASES[index]
 var origin: Array=data.metadata.origin
 var registration:=Basis(Vector3.UP,deg_to_rad(-float(data.metadata.heading_deg)))
 Clip.apply(g,data,definition.time,registration*Vector3(origin[0],origin[1],origin[2]),registration)
 var canonical: Basis=Chassis.full_chassis_basis(g).transposed()
 var center: Vector3=g.station_center(2);var lowest:=INF
 for node in g.points.size():
  g.points[node]=canonical*(g.points[node]-center);g.velocities[node]=canonical*g.velocities[node];lowest=minf(lowest,g.points[node].y-g.radii[node])
 for node in g.points.size():g.points[node].y-=lowest
 var wheels: Array=g.wheels.capture()
 for wheel in wheels:wheel.rotation=(canonical.get_rotation_quaternion()*wheel.rotation).normalized();wheel.angular_velocity=canonical*wheel.angular_velocity
 g.wheels.restore(wheels)
 var normal: Array=data.metadata.signature.normal
 item.skin.field.compression_override=entry.history[clampi(roundi(definition.time*float(data.metadata.sample_hz)),0,data.frames.size()-1)]
 item.skin.collision_direction=-Vector3(normal[0],normal[1],normal[2]);item.skin.update_pose()
 var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
 for i in 28:low=low.min(g.points[i]);high=high.max(g.points[i])
 item.target=(low+high)*.5;item.metrics=g.metrics()
 item.width_loss=maxf(0.,((g.rest[9]-g.rest[8]).length()+(g.rest[13]-g.rest[12]).length()-(g.points[9]-g.points[8]).length()-(g.points[13]-g.points[12]).length())*.5)
 # Saved node signals define the impact centre once; material changes never
 # rebuild or resample this field. Wheel-only first contacts are excluded.
 var sum_weight:=0.;var weighted:=Vector3.ZERO
 for node in 28:
  var weight: float=pow(g.node_contact[node],2.)*pow(g.node_damage[node],1.5)*(.12+item.skin.field.compression[node])
  weighted+=g.rest[node]*weight;sum_weight+=weight
 item.impact_center=weighted/maxf(sum_weight,.00001) if sum_weight>.00001 else Vector3(1.7,.95,0.)
 if sum_weight<=.00001:
  var hit_sum:=Vector3.ZERO;var hits:=0
  for node in data.metadata.signature.get('hit_nodes',[]):
   if int(node)<28:hit_sum+=g.rest[int(node)];hits+=1
  if hits>0:item.impact_center=hit_sum/hits
 var spread:=Vector3.ZERO
 for node in 28:
  var weight: float=pow(g.node_contact[node],2.)*pow(g.node_damage[node],1.5)*(.12+item.skin.field.compression[node])
  var delta: Vector3=g.rest[node]-item.impact_center
  spread+=delta*delta*weight
 spread/=maxf(sum_weight,.00001)
 item.impact_radii=Vector3(sqrt(spread.x),sqrt(spread.y),sqrt(spread.z))*1.35+Vector3(.58,.56,.58)
 var macro: float=maxf(maxf(item.metrics.front_shortening_m,item.metrics.cabin_shortening_m),maxf(item.width_loss,item.metrics.roof_drop_m))
 item.impact_strength=clampf((macro-.015)/.40,0.,1.)
 for material in item.skin.surface_materials:
  material.set_shader_parameter('impact_center',item.impact_center)
  material.set_shader_parameter('impact_radii',item.impact_radii)
  material.set_shader_parameter('impact_strength',item.impact_strength)
 stats.append({'number':index+1,'source':definition.path,'time':definition.time,'impact_center':str(item.impact_center),'impact_radii':str(item.impact_radii),'impact_strength':item.impact_strength,'metrics':item.metrics,'physics_steps':g.step_count})
 _camera(index,false)

func _camera(index: int,focused: bool) -> void:
 var item: Dictionary=views[index]
 var angle: float=CASES[index].angle+(orbit if focused else 0.)
 var radius: float=distance if focused else (3.8 if index==7 else 4.8)
 var target: Vector3=item.target
 var lift: float=elevation if focused else (.7 if index==8 else .38)
 item.camera.position=target+Vector3(cos(angle),lift,sin(angle))*radius
 item.camera.look_at(target)
 item.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func select_case(index: int) -> void:
 if selected>=0:
  views[selected].viewport.size=Vector2i(640,320);_camera(selected,false)
 selected=index;grid.visible=index<0;focus.visible=index>=0
 if index>=0:
  orbit=0.;elevation=.35;distance=5.2
  views[index].viewport.size=Vector2i(1440,720);focus.texture=views[index].viewport.get_texture();_camera(index,true)
 _title()

func _title() -> void:
 var mode_name: String='PLAIN' if plain else ['ORIGINAL PAINT','SECTION BASELINE',('PREVIOUS MATERIAL' if previous_variant else 'IMPACT CORE / TAPERED DAMAGE')][appearance]
 title.text='DAMAGE MATERIAL STUDIO   /   '+('NINE SAVED CASES' if selected<0 else '%02d  %s'%[selected+1,CASES[selected].name])+'   /   '+mode_name

func apply_materials() -> void:
 var began: int=Time.get_ticks_usec()
 for item in views:
  var skin: Node3D=item.skin
  # Keep original section shader as a true baseline. Pose/fields stay frozen.
  for record in skin.records:
   for material in record.materials:
    if not material is ShaderMaterial:continue
    material.shader=skin.shader
    material.set_shader_parameter('view_mode',1 if plain else 2)
    material.set_shader_parameter('damage_enabled',record.folding and appearance!=0 and not plain)
  for material in skin.surface_materials:
   material.shader=skin.shader if appearance==1 and not plain else (skin.PREVIOUS_SHADER if previous_variant else skin.STUDIO_SHADER)
   material.set_shader_parameter('damage_enabled',appearance!=0 and not plain)
   material.set_shader_parameter('view_mode',1 if plain else 2)
   for key in layers:material.set_shader_parameter(key,layers[key] and not plain)
   for key in preset:
    var value: Variant=preset[key]
    if key.ends_with('_color'):value=Color(str(value)).srgb_to_linear()
    material.set_shader_parameter(key,value)
  for key in layers:skin.set(key,layers[key])
  skin.apply_layers()
  for material in skin.surface_materials:
   material.set_shader_parameter('impact_center',item.impact_center)
   material.set_shader_parameter('impact_radii',item.impact_radii)
   material.set_shader_parameter('impact_strength',item.impact_strength)
  item.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
 revision+=1;last_edit_ms=(Time.get_ticks_usec()-began)/1000.
 _title()
 if status!=null:status.text='Preset: %s · change %.2fms'%[preset_name.text,last_edit_ms]

func load_preset() -> void:
 var path: String=HOME+'presets/'+preset_name.text.validate_filename()+'.json'
 var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
 if not value is Dictionary:status.text='Cannot load '+path;return
 preset=value
 for key in sliders:
  if preset.has(key):sliders[key].set_value_no_signal(float(preset[key]))
 apply_materials()

func save_preset() -> void:
 var path: String=HOME+'presets/'+preset_name.text.validate_filename()+'.json'
 FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(preset,'	'))
 status.text='Saved '+path

func _focus_input(event: InputEvent) -> void:
 if selected<0:return
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
  orbit+=event.relative.x*.008;elevation=clampf(elevation+event.relative.y*.004,-.15,1.7);_camera(selected,true)
 if event is InputEventMouseButton and event.pressed:
  if event.button_index==MOUSE_BUTTON_WHEEL_UP:distance=maxf(1.8,distance*.9);_camera(selected,true)
  if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:distance=minf(12.,distance*1.1);_camera(selected,true)

func _unhandled_key_input(event: InputEvent) -> void:
 if not event.pressed or event.echo:return
 var key: int=event.physical_keycode
 if key>=KEY_1 and key<=KEY_9:select_case(key-KEY_1)
 elif key in [KEY_0,KEY_ESCAPE]:select_case(-1)
 elif key==KEY_B:appearance=1 if appearance==2 else 2;apply_materials()
 elif key==KEY_V:previous_variant=not previous_variant;apply_materials()
 elif key==KEY_R:load_preset()
 elif key==KEY_P:capture()
 elif key==KEY_C and selected>=0:distance=3.4 if distance>4. else 5.2;_camera(selected,true)

func capture() -> void:
 if busy_capture:return
 busy_capture=true
 for item in views:item.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
 await RenderingServer.frame_post_draw
 await get_tree().process_frame
 await RenderingServer.frame_post_draw
 var stamp: String=Time.get_datetime_string_from_system().replace(':','-')+'_%03d'%revision
 var kind: String='board' if selected<0 else 'case%02d'%[selected+1]
 var label: String=['original','baseline',('previous' if previous_variant else 'layers')][appearance]
 var base: String=HOME+'captures/'+stamp+'_'+kind+'_'+label
 get_viewport().get_texture().get_image().save_png(base+'.png')
 var record: Dictionary={'variant':('v2' if previous_variant else 'v3'),'shader_sha256':FileAccess.get_sha256(HOME+('variants/v2/studio_layers.gdshader' if previous_variant else 'studio_layers.gdshader')),'preset':preset,'case':selected+1,'appearance':label,'layers':layers,'plain':plain,'orbit':orbit,'elevation':elevation,'distance':distance,'cases':stats}
 FileAccess.open(base+'.json',FileAccess.WRITE).store_string(JSON.stringify(record,'	'))
 get_viewport().get_texture().get_image().save_png(HOME+'captures/latest_'+kind+'_'+label+'.png')
 status.text='Captured '+base.get_file()+'.png + .json'
 print('STUDIO_CAPTURE ',base)
 busy_capture=false

func _process(dt: float) -> void:
 if not auto_capture or evidence_busy:return
 if phase==2:
  orbit+=.015;_camera(selected,true)
 tick+=1;phase_tick+=1
 if phase_tick>10:frame_samples.append(dt*1000.)
 if phase_tick<50:return
 evidence_busy=true
 measurements[['board_idle','focus_idle','focus_orbit'][phase]]={'mean_frame_ms':_mean(frame_samples),'samples':frame_samples.size()}
 frame_samples.clear();phase_tick=0
 if phase==0:
  await capture();select_case(5);phase=1
 elif phase==1:
  await capture();appearance=1;apply_materials();await capture();appearance=2;apply_materials();phase=2
 elif phase==2:
  measurements['load_ms']=load_ms;measurements['material_upload_ms']=last_edit_ms;measurements['cases']=stats
  measurements['device']=RenderingServer.get_video_adapter_name();measurements['method']=RenderingServer.get_current_rendering_method()
  var renders: Array=[]
  for item in views:
   var rid: RID=item.viewport.get_viewport_rid()
   renders.append({'size':str(item.viewport.size),'cpu_submission_ms':RenderingServer.viewport_get_measured_render_time_cpu(rid),'gpu_ms':RenderingServer.viewport_get_measured_render_time_gpu(rid),'mode':item.viewport.render_target_update_mode,'physics_steps':item.car.solver.step_count,'field_updates':item.skin.field.updates})
  measurements['viewports']=renders;measurements['note']='Frame intervals include root UI; static viewports render on change. GPU zero means unavailable. No gameplay FPS claim.'
  FileAccess.open(HOME+'captures/measurements.json',FileAccess.WRITE).store_string(JSON.stringify(measurements,'	'))
  select_case(4);await capture();previous_variant=true;apply_materials();await capture();previous_variant=false;apply_materials()
  auto_capture=false;select_case(-1)
  print('STUDIO_EVIDENCE_COMPLETE')
 evidence_busy=false

func _mean(values: Array) -> float:
 var total:=0.
 for value in values:total+=value
 return total/maxi(1,values.size())
func _environment(root_: Node3D) -> void:
 var world:=WorldEnvironment.new();var env:=Environment.new();var sky:=Sky.new();var sky_mat:=ProceduralSkyMaterial.new()
 sky_mat.sky_top_color=Color('#344b65');sky_mat.sky_horizon_color=Color('#bfcbd1');sky_mat.ground_bottom_color=Color('#253139');sky_mat.ground_horizon_color=Color('#a1a9aa');sky.sky_material=sky_mat
 env.background_mode=Environment.BG_COLOR;env.background_color=Color('#424d57');env.sky=sky;env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY;env.ambient_light_energy=.65;env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY;env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;world.environment=env;root_.add_child(world)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-42,-35,0);sun.light_energy=1.15;sun.shadow_enabled=true;root_.add_child(sun)
 var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-15,130,0);fill.light_energy=.4;root_.add_child(fill)
 var floor_:=MeshInstance3D.new();var plane:=BoxMesh.new();plane.size=Vector3(200,.15,200);floor_.mesh=plane;floor_.position.y=-.075;var material:=StandardMaterial3D.new();material.albedo_color=Color('#586773');material.roughness=.85;floor_.material_override=material;root_.add_child(floor_)
