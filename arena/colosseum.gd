extends Node3D
const Terrain=preload('res://arena/terrain.gd')
const Stadium=preload('res://arena/stadium.gd')
const Vehicle=preload('res://arena/vehicle.gd')
const BodyFixture=preload('res://scripts/body_impact_fixture.gd')
const MountDemo=preload('res://scripts/wheel_mount_demo.gd')
const SkinView=preload('res://scripts/damage_skin.gd')
var terrain:=Terrain.new()
var stadium: Node3D
var car: RefCounted
var skin: Node3D
var camera: Camera3D
var readout: Label
var bake_toggle: CheckButton
var quality_control: OptionButton
var power_control: HSlider
var grip_control: HSlider
var panel_controls: VBoxContainer
var mount_demo:=MountDemo.new()
var body_fixture_active:=false
var body_previous_baked:=true
var capture_crash:=false
var crash_saved:=false
var camera_mode:=0
var orbit:=0.0
var reverse:=false
var capture:=false
var capture_tick:=0
var capture_stage:=0
var capture_air:=false
var debug_visible:=false
var capture_manifest: Array=[]
func _ready() -> void:
 DisplayServer.window_set_title('Niva / Colosseum sand arena')
 capture='--capture-arena' in OS.get_cmdline_user_args()
 stadium=Stadium.new();add_child(stadium);stadium.build(terrain)
 car=Vehicle.new();car.setup();car.solver.terrain=terrain;car.solver.barrier_enabled=true
 car.reset(0,Vector3(-12,0,0))
 skin=Node3D.new();skin.set_script(SkinView);add_child(skin);skin.setup(car.solver,car.profile.model);skin.show_frame=false;skin.set_mode(2)
 camera=Camera3D.new();camera.current=true;camera.fov=58;camera.far=1200;add_child(camera)
 mount_demo=MountDemo.new();car.before_step.connect(mount_demo.step)
 _hud()
 capture_crash='--capture-arena-crash' in OS.get_cmdline_user_args()
 if '--live' in OS.get_cmdline_user_args():bake_toggle.button_pressed=false
 if capture_crash:_start_head_on(120,20)
 if capture:camera_mode=2
 print('ARENA_READY base603c3fd shared120Hz car, instances=',stadium.instances,' triangles=',stadium.mesh_triangles,' static_build_ms=',stadium.load_ms)
func _button(parent: Node,text_: String,callback: Callable) -> void:
 var button:=Button.new();button.text=text_;button.pressed.connect(callback);parent.add_child(button)
func _hud() -> void:
 var layer:=CanvasLayer.new();add_child(layer)
 var panel:=PanelContainer.new();panel.position=Vector2(18,18);panel.size=Vector2(390,get_viewport().get_visible_rect().size.y-36);layer.add_child(panel)
 get_viewport().size_changed.connect(func():panel.size.y=get_viewport().get_visible_rect().size.y-36)
 var style:=StyleBoxFlat.new();style.bg_color=Color(.075,.09,.10,.88);style.content_margin_left=13;style.content_margin_right=13;style.content_margin_top=10;style.content_margin_bottom=10;panel.add_theme_stylebox_override('panel',style)
 var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;panel.add_child(scroll)
 var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(column)
 var title:=Label.new();title.text='COLOSSEUM / DRIVE & CRASH';title.add_theme_font_size_override('font_size',19);column.add_child(title)
 readout=Label.new();readout.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(readout)
 var help:=Label.new();help.text='W/S throttle/brake · A/D steer · Space handbrake\nQ reverse · R repair · C camera · drag orbit\nH/Y 60/120 wall · U/I ±20° · B baked/live';help.add_theme_font_size_override('font_size',12);column.add_child(help)
 bake_toggle=CheckButton.new();bake_toggle.text='Use baked wall crashes';bake_toggle.button_pressed=car.baked_enabled;bake_toggle.toggled.connect(_baked_toggled);column.add_child(bake_toggle)
 var grip_label:=Label.new();column.add_child(grip_label)
 var grip:=HSlider.new();grip_control=grip;grip.min_value=.1;grip.max_value=1.5;grip.step=.01;grip.value=car.dynamics.parameters.tire_friction;column.add_child(grip)
 grip_label.text='Tyre friction: %.2f'%grip.value;grip.value_changed.connect(func(v):car.set_tire_friction(v);grip_label.text='Tyre friction: %.2f'%v)
 var power_label:=Label.new();column.add_child(power_label)
 var power:=HSlider.new();power_control=power;power.min_value=55;power.max_value=660;power.step=5;power.value=car.dynamics.parameters.power_w/1000.;column.add_child(power)
 power_label.text='Engine power: %.0f kW'%power.value;power.value_changed.connect(func(v):car.set_engine_power_kw(v);power_label.text='Engine power: %.0f kW'%v)
 var quality_row:=HBoxContainer.new();column.add_child(quality_row)
 var label:=Label.new();label.text='Live precision';quality_row.add_child(label)
 quality_control=OptionButton.new();quality_row.add_child(quality_control)
 for item in [['480 Hz',1],['960 Hz',2],['1,920 Hz',4]]:quality_control.add_item(item[0],item[1])
 quality_control.item_selected.connect(func(i):car.set_simulation_quality(quality_control.get_item_id(i)))
 _button(column,'Repair / return to centre',_reset)
 for row_spec in [[['Wall 60',60.,0.],['Wall 120',120.,0.]],[['Wall +20°',120.,20.],['Wall −20°',120.,-20.]]]:
  var row:=HBoxContainer.new();column.add_child(row)
  for spec in row_spec:_button(row,spec[0],_start_head_on.bind(spec[1],spec[2]))
 var sequence_row:=HBoxContainer.new();column.add_child(sequence_row)
 _button(sequence_row,'Three baked impacts',_start_baked_sequence);_button(sequence_row,'Next impact',_stage_next_impact)
 var terrain_row:=HBoxContainer.new();column.add_child(terrain_row)
 for i in 4:_button(terrain_row,['Sand','Concrete','Timber','Halfpipe'][i],_stage_feature.bind(i))
 var pair_row:=HBoxContainer.new();column.add_child(pair_row)
 for spec in [['Steep 42°',-2.3],['Medium 24°',2.3],['Straddle',0.]]:_button(pair_row,spec[0],_pair_start.bind(spec[1]))
 var body_row:=HBoxContainer.new();column.add_child(body_row)
 for spec in [['Flat roof','roof_flat'],['Angled roof','roof_corner'],['Side hit','side_wall']]:_button(body_row,spec[0],_start_body_test.bind(spec[1]))
 var view_row:=HBoxContainer.new();column.add_child(view_row)
 _button(view_row,'Wheel mount test',_start_mount_test);_button(view_row,'Structure',func():skin.set_mode(0));_button(view_row,'Textured',func():skin.set_mode(2))
 panel_controls=VBoxContainer.new();panel_controls.name='PanelControls';column.add_child(panel_controls)
 _button(column,'Open test yard',func():get_tree().change_scene_to_file('res://driving.tscn'))
func _baked_toggled(value: bool) -> void:
 if body_fixture_active and value:BodyFixture.restore(car);body_fixture_active=false
 car.baked_enabled=value
func _reset() -> void:
 BodyFixture.restore(car);mount_demo.stop()
 if body_fixture_active:body_fixture_active=false;bake_toggle.button_pressed=body_previous_baked
 reverse=false;orbit=0;car.reset(0,Vector3(-12,0,0));car.solver.barrier_enabled=true
func _stage_feature(index: int) -> void:
 _reset()
 var f: Dictionary=terrain.features[index]
 camera_mode=0;car.reset(0,Vector3(f.start-14,0,f.z))
func _pair_start(side: float) -> void:
 _stage_feature(4)
 car.reset(0,Vector3(terrain.features[4].start-14,0,terrain.features[4].z+side))
func _start_head_on(speed: float=60,heading: float=0) -> void:
 _reset();camera_mode=1;car.reset_wall_approach(speed,heading)
func _start_baked_sequence() -> void:
 _reset();bake_toggle.button_pressed=true;camera_mode=1;car.start_baked_sequence()
func _stage_next_impact() -> void:
 if car.mode=='BAKED':return
 bake_toggle.button_pressed=true;camera_mode=1;car.stage_next_supported()
func _start_mount_test() -> void:
 _reset();bake_toggle.button_pressed=false;camera_mode=1;mount_demo.start(car.solver)
func _start_body_test(case_: String) -> void:
 _reset();body_previous_baked=car.baked_enabled;bake_toggle.button_pressed=false
 BodyFixture.start(car,case_,1.0,true);car.set_simulation_quality(quality_control.get_selected_id());body_fixture_active=true;camera_mode=1
 if car.solver.effects!=null:car.solver.effects.synchronize()
func _physics_process(dt: float) -> void:
 if capture and not capture_air:return
 var throttle:=1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0
 var brake:=1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0
 var steering: float=(1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)-(1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0)
 if capture_air:throttle=.1;brake=0;steering=0
 car.set_controls(-throttle if reverse else throttle,brake,steering,1.0 if Input.is_physical_key_pressed(KEY_SPACE) else 0.0)
 if car.sequence_active or mount_demo.active:car.set_controls(0,0,0,0)
 car.advance(dt,.25 if body_fixture_active else (.5 if car.sequence_active or mount_demo.active else 1.0))
 if car.compact.center.length()>140 or car.compact.center.y< -10:_reset()
func _process(_dt: float) -> void:
 skin.update_pose()
 var center: Vector3=car.solver.station_center(2)
 var f: Vector3=car.forward()
 var heading:=atan2(f.z,f.x)+orbit
 if camera_mode==0:
  camera.position=center+Vector3(-cos(heading)*7.5,3.0,-sin(heading)*7.5);camera.look_at(center+Vector3.UP*.6)
 elif camera_mode==1:
  camera.position=center+Vector3(cos(heading+1)*8,3.0,sin(heading+1)*8);camera.look_at(center+Vector3.UP*.4)
 else:
  camera.position=Vector3(113,110,128);camera.look_at(Vector3(0,2,0))
 if camera_mode!=2 and car.solver.barrier_enabled and car.solver.barrier_min.z-1<camera.position.z and camera.position.z<car.solver.barrier_max.z+1:
  if center.x<car.solver.barrier_min.x:camera.position.x=minf(camera.position.x,minf(center.x-absf(camera.position.x-center.x),car.solver.barrier_min.x-.8))
  else:camera.position.x=maxf(camera.position.x,maxf(center.x+absf(camera.position.x-center.x),car.solver.barrier_max.x+.8))
  camera.look_at(center+Vector3.UP*.4)
 if capture and capture_stage==2:
  camera.position=Vector3(18,5,-30);camera.look_at(Vector3(19,1.5,-18))
 if capture and capture_stage==5:
  camera.position=Vector3(70,4,-3);camera.look_at(Vector3(82,5.0,0))
 if capture and capture_stage==6:
  camera.position=Vector3(-10,1.1,1.5);camera.look_at(Vector3(-8,0,0))
 if capture and capture_stage==7:
  camera.position=Vector3(2,17,-67);camera.look_at(Vector3(2,3,-50))
 readout.text='%3.0f km/h · %s   |   C changes view'%[car.velocity().length()*3.6,'R' if reverse else 'D']
 readout.text+='\n%s · baked %s · impacts %d'%[{'DRIVE':'Light driving','FULL':'Live deformation','BAKED':'Baked playback','SLEEP':'Sleeping'}[car.mode],'ON' if car.baked_enabled else 'OFF',car.baked_count]
 if not car.last_bake.is_empty():readout.text+='\n'+str(car.last_bake.id)
 if car.sequence_notice!='':readout.text+='\n'+car.sequence_notice
 if debug_visible:readout.text+='\n%d full solves · %.2f ms / 120 Hz\n%d instances · %d triangles'%[car.full_steps,car.statistics().cpu_ms_per_sim_second/120,stadium.instances,stadium.mesh_triangles]
 if capture:_capture_step()
 if capture_crash and not crash_saved and car.mode=='BAKED' and car.crash_player.time>.65:
  crash_saved=true;_save('arena_crash_controls.png');get_tree().quit()
func _capture_step() -> void:
 capture_tick+=1
 if capture_tick<18 and capture_stage!=4:return
 capture_tick=0
 if capture_stage==0:
  _save('overview.png');camera_mode=1;capture_stage+=1
 elif capture_stage==1:
  _save('car_lighting.png');camera_mode=0;_stage_feature(2);capture_stage+=1
 elif capture_stage==2:
  camera.position=Vector3(18,5,-30);camera.look_at(Vector3(19,1.5,-18));_save('timber_detail.png');capture_stage+=1
 elif capture_stage==3:
  _save('chase.png');camera_mode=1;car.reset(58,Vector3(-55,0,-25));car.solver.barrier_enabled=false;capture_air=true;capture_stage+=1
 elif capture_stage==4:
  var gap:=INF
  for wheel in car.solver.wheels.wheels:
   var p: Vector3=car.solver.points[wheel.node];gap=minf(gap,p.y+car.solver.wheels.support(wheel,Vector3.DOWN).y-terrain.sample(p).w)
  if gap>.16:_save('sand_jump.png');capture_air=false;capture_stage+=1
  elif car.solver.simulated_time>5:push_error('Capture did not reach airborne state');get_tree().quit(1)
 elif capture_stage==5:_save('stone_detail.png');capture_stage+=1
 elif capture_stage==6:_save('sand_detail.png');_pair_start(0);capture_stage+=1
 elif capture_stage==7:_save('paired_ramps.png');_pair_start(0);camera_mode=1;capture_air=true;capture_stage+=1;car.reset(28,Vector3(-16,0,-50));car.solver.barrier_enabled=false
 elif capture_stage==8:
  if car.compact.center.x> -7.5:_save('paired_straddle.png');capture_air=false;capture_stage+=1
  elif car.solver.simulated_time>6:push_error('Straddle approach stalled');get_tree().quit(1)
 elif capture_stage==9:get_tree().quit()
func _save(name_: String) -> void:
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://arena/evidence'))
 RenderingServer.force_draw(false);get_viewport().get_texture().get_image().save_png('res://arena/evidence/'+name_)
 var wheels: Array=[]
 for wheel in car.solver.wheels.wheels:
  var p: Vector3=car.solver.points[wheel.node];var floor_: Vector4=terrain.sample(p)
  wheels.append({'node':wheel.node,'position':[p.x,p.y,p.z],'floor_height_m':floor_.w,'vertical_tire_gap_m':p.y+car.solver.wheels.support(wheel,Vector3.DOWN).y-floor_.w,'detached':wheel.detached})
 capture_manifest.append({'file':name_,'simulation_time_s':car.solver.simulated_time,'full_solver_steps':car.full_steps,'camera_position':str(camera.position),'wheels':wheels})
 FileAccess.open('res://arena/evidence/'+('parity_capture.json' if capture_crash else 'captures.json'),FileAccess.WRITE).store_string(JSON.stringify(capture_manifest,'\t'))
 print('ARENA_CAPTURE ',name_)
func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):orbit+=event.relative.x*.008
 if event is InputEventKey and event.pressed and not event.echo:
  match event.physical_keycode:
   KEY_R:_reset()
   KEY_B:bake_toggle.button_pressed=not bake_toggle.button_pressed
   KEY_H:_start_head_on(60)
   KEY_Y:_start_head_on(120)
   KEY_U:_start_head_on(120,20)
   KEY_I:_start_head_on(120,-20)
   KEY_T:_start_mount_test()
   KEY_J:_stage_feature(0)
   KEY_K:_stage_feature(2)
   KEY_Q:reverse=not reverse
   KEY_C:camera_mode=(camera_mode+1)%3
   KEY_F3:debug_visible=not debug_visible
   KEY_1:_stage_feature(0)
   KEY_2:_stage_feature(1)
   KEY_3:_stage_feature(2)
   KEY_4:_stage_feature(3)
   KEY_5:_stage_feature(4)
   KEY_ESCAPE:get_tree().quit()
