extends Node3D
const Terrain=preload('res://arena/terrain.gd')
const Stadium=preload('res://arena/stadium.gd')
const Vehicle=preload('res://arena/vehicle.gd')
const SkinView=preload('res://scripts/damage_skin.gd')
var terrain:=Terrain.new()
var stadium: Node3D
var car: RefCounted
var skin: Node3D
var camera: Camera3D
var readout: Label
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
 car=Vehicle.new();car.setup();car.solver.terrain=terrain;car.solver.barrier_enabled=false
 car.reset(0,Vector3(-12,0,0))
 skin=Node3D.new();skin.set_script(SkinView);add_child(skin);skin.setup(car.solver,car.profile.model);skin.show_frame=false;skin.set_mode(2)
 camera=Camera3D.new();camera.current=true;camera.fov=58;camera.far=1200;add_child(camera)
 _hud()
 if capture:camera_mode=2
 print('ARENA_READY base603c3fd shared120Hz car, instances=',stadium.instances,' triangles=',stadium.mesh_triangles,' static_build_ms=',stadium.load_ms)
func _hud() -> void:
 var layer:=CanvasLayer.new();add_child(layer)
 var panel:=PanelContainer.new();panel.position=Vector2(18,18);layer.add_child(panel)
 var style:=StyleBoxFlat.new();style.bg_color=Color(.075,.09,.10,.86);style.content_margin_left=13;style.content_margin_right=13;style.content_margin_top=10;style.content_margin_bottom=10;panel.add_theme_stylebox_override('panel',style)
 var column:=VBoxContainer.new();panel.add_child(column)
 var title:=Label.new();title.text='COLOSSEUM / SAND & RAMPS';title.add_theme_font_size_override('font_size',20);column.add_child(title)
 readout=Label.new();column.add_child(readout)
 var help:=Label.new();help.text='W throttle · S brake · A/D steer\nSpace handbrake · Q reverse · R repair\nC camera · drag orbit · F3 performance';column.add_child(help)
 var row:=HBoxContainer.new();column.add_child(row)
 for i in terrain.features.size():
  var button:=Button.new();button.text=['Sand','Concrete','Timber','Halfpipe','Pair 42°/24°'][i];button.pressed.connect(_stage_feature.bind(i));row.add_child(button)
 var pair_buttons:=HBoxContainer.new();column.add_child(pair_buttons)
 for spec in [['Steep lane',-2.3],['Medium lane',2.3],['Straddle seam',0.0]]:
  var button:=Button.new();button.text=spec[0];button.pressed.connect(_pair_start.bind(spec[1]));pair_buttons.add_child(button)
 var reset:=Button.new();reset.text='Return to centre';reset.pressed.connect(_reset);column.add_child(reset)
 var yard:=Button.new();yard.text='Open test yard';yard.pressed.connect(func():get_tree().change_scene_to_file('res://driving.tscn'));column.add_child(yard)
func _reset() -> void:
 reverse=false;orbit=0;car.reset(0,Vector3(-12,0,0));car.solver.barrier_enabled=false
func _stage_feature(index: int) -> void:
 var f: Dictionary=terrain.features[index]
 reverse=false;orbit=0;camera_mode=0;car.reset(0,Vector3(f.start-14,0,f.z));car.solver.barrier_enabled=false
func _pair_start(side: float) -> void:
 _stage_feature(4)
 car.reset(0,Vector3(terrain.features[4].start-14,0,terrain.features[4].z+side));car.solver.barrier_enabled=false
func _physics_process(dt: float) -> void:
 if capture and not capture_air:return
 var throttle:=1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0
 var brake:=1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0
 var steering: float=(1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)-(1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0)
 if capture_air:throttle=.1;brake=0;steering=0
 car.set_controls(-throttle if reverse else throttle,brake,steering,1.0 if Input.is_physical_key_pressed(KEY_SPACE) else 0.0)
 car.advance(dt)
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
 if capture and capture_stage==2:
  camera.position=Vector3(18,5,-30);camera.look_at(Vector3(19,1.5,-18))
 if capture and capture_stage==5:
  camera.position=Vector3(70,4,-3);camera.look_at(Vector3(82,5.0,0))
 if capture and capture_stage==6:
  camera.position=Vector3(-10,1.1,1.5);camera.look_at(Vector3(-8,0,0))
 if capture and capture_stage==7:
  camera.position=Vector3(2,17,-67);camera.look_at(Vector3(2,3,-50))
 readout.text='%3.0f km/h · %s   |   C changes view'%[car.velocity().length()*3.6,'R' if reverse else 'D']
 if debug_visible:readout.text+='\n%d full solves · %.2f ms / 120 Hz\n%d instances · %d triangles'%[car.full_steps,car.statistics().cpu_ms_per_sim_second/120,stadium.instances,stadium.mesh_triangles]
 if capture:_capture_step()
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
 FileAccess.open('res://arena/evidence/captures.json',FileAccess.WRITE).store_string(JSON.stringify(capture_manifest,'\t'))
 print('ARENA_CAPTURE ',name_)
func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):orbit+=event.relative.x*.008
 if event is InputEventKey and event.pressed and not event.echo:
  match event.physical_keycode:
   KEY_R:_reset()
   KEY_Q:reverse=not reverse
   KEY_C:camera_mode=(camera_mode+1)%3
   KEY_F3:debug_visible=not debug_visible
   KEY_1:_stage_feature(0)
   KEY_2:_stage_feature(1)
   KEY_3:_stage_feature(2)
   KEY_4:_stage_feature(3)
   KEY_5:_stage_feature(4)
   KEY_ESCAPE:get_tree().quit()
