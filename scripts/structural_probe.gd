extends Node3D
const VehicleSimulation=preload('res://scripts/vehicle_simulation.gd')
@export_file('*.json') var vehicle_profile: String='res://vehicles/niva.json'
var simulation: RefCounted
const SkinView=preload('res://scripts/structural_skin.gd')
var solver: RefCounted
var view: Node3D
var camera: Camera3D
var barrier_visual: MeshInstance3D
var status: Label
var telemetry: Label
var impact_picker: OptionButton
var speed_picker: OptionButton
var mode_picker: OptionButton
var slow_toggle: CheckButton
var frame_toggle: CheckButton
var details_toggle: CheckButton
var weak_toggle: CheckButton
var barrier_toggle: CheckButton
var timeline: HSlider
var run_button: Button
var speed:=120.0
var running:=false
var completed:=false
var accumulator:=0.0
var record_timer:=0.0
var frames: Array[Dictionary]=[]
var scrub_guard:=false
var yaw:=0.70
var height:=2.7
var distance:=7.8
var top_camera:=false
var wait_time:=0.0
var autoplay:=false
var verify:=false
var capture_mode:=false
var test_index:=0
var results: Array[Dictionary]=[]
var speeds: Array[float]=[20,50,80,120]
var capture_phase:=0
var summary_mode:=false

func _ready() -> void:
 verify='--verify-structure' in OS.get_cmdline_user_args()
 capture_mode='--capture-structure' in OS.get_cmdline_user_args()
 autoplay=verify or capture_mode or '--autoplay' in OS.get_cmdline_user_args()
 _stage()
 simulation=VehicleSimulation.new()
 simulation.setup(vehicle_profile)
 solver=simulation.solver
 view=Node3D.new()
 view.set_script(SkinView)
 add_child(view)
 view.setup(solver,simulation.profile.model)
 camera=Camera3D.new()
 camera.current=true
 camera.fov=39
 camera.far=250
 add_child(camera)
 # Inspection fill follows the camera so damaged panels remain readable after yaw.
 var fill:=DirectionalLight3D.new()
 fill.light_energy=.60
 fill.shadow_enabled=false
 camera.add_child(fill)
 _ui()
 if capture_mode:slow_toggle.button_pressed=false
 reset_probe()
 print('STRUCTURAL_PROBE_READY ',solver.rest.size(),' mass nodes / ',solver.links.size(),' yielding links / ',solver.config.mass_kg,' kg')

func _stage() -> void:
 var world:=WorldEnvironment.new()
 var env:=Environment.new()
 env.background_mode=Environment.BG_COLOR
 env.background_color=Color('#26313b')
 env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color=Color('#d7e2e8')
 env.ambient_light_energy=0.46
 env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
 world.environment=env
 add_child(world)
 var sun:=DirectionalLight3D.new()
 sun.rotation_degrees=Vector3(-45,-30,0)
 sun.light_energy=0.65
 sun.shadow_enabled=true
 add_child(sun)
 var ground:=MeshInstance3D.new()
 var floor_mesh:=BoxMesh.new()
 floor_mesh.size=Vector3(200,0.25,200)
 ground.mesh=floor_mesh
 ground.position.y=-0.125
 ground.material_override=_material(Color('#3d484f'))
 add_child(ground)
 barrier_visual=MeshInstance3D.new()
 var wall:=BoxMesh.new()
 wall.size=Vector3(.5,3.5,4.5)
 barrier_visual.mesh=wall
 barrier_visual.position=Vector3(.25,1.75,0)
 barrier_visual.material_override=_material(Color('#a4aaa9'))
 add_child(barrier_visual)
 # Collision planes in the structural solver use the same x=0 / y=0 surfaces.
 var paint:=_material(Color('#b9a777'))
 for x in range(-15,1):
  for z in [-1.45,1.45]:
   var line:=MeshInstance3D.new()
   var mesh:=BoxMesh.new()
   mesh.size=Vector3(.25,.008,.04)
   line.mesh=mesh
   line.position=Vector3(x,.005,z)
   line.material_override=paint
   add_child(line)

func _material(color: Color) -> StandardMaterial3D:
 var material:=StandardMaterial3D.new()
 material.albedo_color=color
 material.roughness=0.9
 return material

func _ui() -> void:
 var canvas:=CanvasLayer.new()
 add_child(canvas)
 var title:=Label.new()
 title.position=Vector2(26,20)
 title.text=simulation.profile.name.to_upper()+' / STRUCTURAL CRASH PROBE'
 title.add_theme_font_size_override('font_size',24)
 canvas.add_child(title)
 var subtitle:=Label.new()
 subtitle.position=Vector2(28,53)
 subtitle.text='Mass and load paths · permanent structural yielding · panels attached to the frame'
 subtitle.add_theme_font_size_override('font_size',13)
 canvas.add_child(subtitle)
 var panel:=PanelContainer.new()
 panel.position=Vector2(26,88)
 panel.custom_minimum_size=Vector2(290,0)
 var style:=StyleBoxFlat.new()
 style.bg_color=Color(.07,.11,.14,.95)
 for corner in ['corner_radius_top_left','corner_radius_top_right','corner_radius_bottom_left','corner_radius_bottom_right']:
  style.set(corner,10)
 style.content_margin_left=14
 style.content_margin_right=14
 style.content_margin_top=14
 style.content_margin_bottom=14
 panel.add_theme_stylebox_override('panel',style)
 canvas.add_child(panel)
 var column:=VBoxContainer.new()
 column.add_theme_constant_override('separation',9)
 panel.add_child(column)
 var label:=Label.new()
 label.text='Impact speed'
 column.add_child(label)
 speed_picker=OptionButton.new()
 for value in speeds:speed_picker.add_item('%d km/h'%value)
 speed_picker.select(3)
 speed_picker.item_selected.connect(func(i):speed=speeds[i])
 column.add_child(speed_picker)
 var setup_label:=Label.new()
 setup_label.text='Impact setup'
 column.add_child(setup_label)
 impact_picker=OptionButton.new()
 impact_picker.add_item('Full-width frontal')
 impact_picker.add_item('Offset / left front wheel')
 impact_picker.select(0 if verify else 1)
 impact_picker.item_selected.connect(func(_i):reset_probe())
 column.add_child(impact_picker)
 run_button=Button.new()
 run_button.text='Run structural impact'
 run_button.pressed.connect(func():begin(speed))
 column.add_child(run_button)
 var reset:=Button.new()
 reset.text='Reset to pristine'
 reset.pressed.connect(reset_probe)
 column.add_child(reset)
 var look:=Label.new()
 look.text='Inspection view'
 column.add_child(look)
 mode_picker=OptionButton.new()
 for name in ['Bare structure','Plain bodywork','Textured car','Ghost bodywork']:mode_picker.add_item(name)
 mode_picker.item_selected.connect(func(i):view.set_mode(i))
 column.add_child(mode_picker)
 slow_toggle=_check('Slow motion',true,column)
 frame_toggle=_check('Structure overlay',true,column)
 details_toggle=_check('Folds and surface damage',true,column)
 weak_toggle=_check('Weaken one front rail',false,column)
 barrier_toggle=_check('Show barrier',true,column)
 var legend:=Label.new()
 legend.text='Teal      Body / sills / pillars\nOrange  Front rails\nBlue      Engine / mounts\nGreen   Suspension\nRed       Yielded / failed'
 legend.add_theme_font_size_override('font_size',12)
 column.add_child(legend)
 var cameras:=HBoxContainer.new()
 cameras.position=Vector2(342,90)
 canvas.add_child(cameras)
 for name in ['Front 3/4','Side','Top']:
  var button:=Button.new()
  button.text=name
  button.pressed.connect(func():
   top_camera=name=='Top'
   yaw=0.70 if name=='Front 3/4' else PI/2)
  cameras.add_child(button)
 status=Label.new()
 status.position=Vector2(342,132)
 status.text='Ready · wheels and suspension load the deformable structure'
 status.add_theme_font_size_override('font_size',17)
 canvas.add_child(status)
 telemetry=Label.new()
 telemetry.position=Vector2(342,162)
 telemetry.add_theme_font_size_override('font_size',13)
 canvas.add_child(telemetry)
 var bottom:=VBoxContainer.new()
 bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
 canvas.add_child(bottom)
 bottom.offset_left=28
 bottom.offset_right=-28
 bottom.offset_bottom=-24
 bottom.offset_top=-98
 var replay:=Label.new()
 replay.text='Recorded structural impact — drag to inspect any moment'
 bottom.add_child(replay)
 timeline=HSlider.new()
 timeline.min_value=0
 timeline.max_value=1
 timeline.step=.001
 timeline.editable=false
 timeline.value_changed.connect(scrub)
 bottom.add_child(timeline)
 var help:=Label.new()
 help.text='Drag: orbit · Wheel: zoom · Space: run · R: reset · 1–4: inspection view · B: barrier · Esc: close'
 help.add_theme_font_size_override('font_size',13)
 bottom.add_child(help)

func _check(text: String,pressed: bool,column: Node) -> CheckButton:
 var button:=CheckButton.new()
 button.text=text
 button.button_pressed=pressed
 column.add_child(button)
 button.toggled.connect(func(_value):_options())
 return button

func _options() -> void:
 if frame_toggle==null or details_toggle==null or barrier_toggle==null:return
 view.show_frame=frame_toggle.button_pressed
 view.detail_enabled=details_toggle.button_pressed
 view.set_mode(mode_picker.selected)
 barrier_visual.visible=barrier_toggle.button_pressed

func reset_probe() -> void:
 running=false
 completed=false
 accumulator=0
 record_timer=0
 solver.set_impact_mode(impact_picker.selected)
 _update_barrier()
 simulation.reset(0,Vector3(-9,0,0))
 frames.clear()
 timeline.editable=false
 scrub_guard=true
 timeline.value=0
 scrub_guard=false
 run_button.disabled=false
 barrier_toggle.button_pressed=true
 status.text='Pristine structure · ready'
 view.update_pose()

func _update_barrier() -> void:
 var mesh:=BoxMesh.new()
 mesh.size=solver.barrier_max-solver.barrier_min
 barrier_visual.mesh=mesh
 barrier_visual.position=(solver.barrier_min+solver.barrier_max)*.5

func begin(value: float) -> void:
 reset_probe()
 speed=value
 simulation.reset(value,Vector3(-9,0,0),weak_toggle.button_pressed)
 running=true
 run_button.disabled=true
 status.text='Approaching barrier · %d km/h'%value
 frames.append(solver.capture())

func _physics_process(dt: float) -> void:
 if not running:return
 accumulator+=dt*(0.25 if slow_toggle.button_pressed and not verify else 1.0)
 var step: float=solver.config.fixed_step_s
 while accumulator>=step and running:
  simulation.step(step)
  accumulator-=step
  record_timer+=step
  if record_timer>=1.0/120.0:
   record_timer-=1.0/120.0
   frames.append(solver.capture())
  if solver.impact_started:
   status.text='Impact · load propagating through the body structure'
  if solver.simulated_time>=3.0:
   finish()

func finish() -> void:
 running=false
 completed=true
 frames.append(solver.capture())
 run_button.disabled=false
 barrier_toggle.button_pressed=false
 timeline.editable=true
 scrub_guard=true
 timeline.value=1
 scrub_guard=false
 status.text='Impact held · compare structure, plain shell and textured body'
 view.update_pose()
 if verify:
  _verify_run()

func scrub(value: float) -> void:
 if scrub_guard or running or frames.is_empty():return
 var n: float=value*(frames.size()-1)
 var a: Dictionary=frames[floori(n)]
 var b: Dictionary=frames[mini(ceili(n),frames.size()-1)]
 var t: float=n-floorf(n)
 var interpolated: Dictionary=a.duplicate(true)
 var positions: PackedVector3Array=a.points.duplicate()
 for i in positions.size():positions[i]=a.points[i].lerp(b.points[i],t)
 var states: Array=interpolated.wheels
 for i in states.size():
  states[i].rotation=a.wheels[i].rotation.slerp(b.wheels[i].rotation,t)
  states[i].spin=lerp_angle(a.wheels[i].spin,b.wheels[i].spin,t)
 interpolated.wheels=states
 interpolated.points=positions
 interpolated.time=lerpf(a.time,b.time,t)
 solver.restore(interpolated)
 view.update_pose()
 status.text='Replay · %.2f s'%solver.simulated_time

func _process(dt: float) -> void:
 var target: Vector3=solver.center_of_mass()+Vector3(0,.25,0)
 if top_camera:camera.position=target+Vector3(0,8,.001)
 else:
  var forward: Vector3=solver.station_center(3)-solver.station_center(1)
  var heading: float=atan2(forward.z,forward.x)
  camera.position=target+Vector3(cos(yaw+heading)*distance,height,sin(yaw+heading)*distance)
 camera.look_at(target)
 view.update_pose()
 var m: Dictionary=solver.metrics()
 var wheel_contacts:=0
 var detached:=0
 var tilt:=0.0
 for w in m.wheels:
  wheel_contacts+=w.body_contact_events
  detached+=1 if w.detached else 0
  tilt=maxf(tilt,w.hub_tilt_deg)
 telemetry.text='Front shortening: %d mm   Cabin shortening: %d mm\nYielded connections: %d / %d   Plastic work: %.0f kJ' %[m.front_shortening_m*1000,m.cabin_shortening_m*1000,m.yielded_links,m.links,m.plastic_work_kj]
 telemetry.text+='\nSuspension failures: %d   Detached wheels: %d   Hub tilt: %.0f°\nWheel / body contact: %s' %[m.broken_suspension_links,detached,tilt,'yes' if wheel_contacts>0 else 'none yet']
 if autoplay:
  wait_time+=dt
  if wait_time>(.05 if verify else 1.5):
   autoplay=false
   wait_time=0
   begin(20 if verify else speed)
 if verify and completed:
  wait_time+=dt
  if wait_time>.05:
   wait_time=0
   test_index+=1
   if test_index<speeds.size():begin(speeds[test_index])
   elif test_index==speeds.size():
    solver.config.enforce_symmetry=false
    weak_toggle.button_pressed=false
    begin(80)
   elif test_index==speeds.size()+1:
    weak_toggle.button_pressed=true
    begin(80)
   else:_finish_verification()
 if capture_mode and completed:_capture(dt)

func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseMotion and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
  yaw+=event.relative.x*.008
  height=clampf(height+event.relative.y*.014,.3,6)
  top_camera=false
 if event is InputEventMouseButton and event.pressed:
  if event.button_index==MOUSE_BUTTON_WHEEL_UP:distance=maxf(3.8,distance-.5)
  elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:distance=minf(14,distance+.5)
 if event is InputEventKey and event.pressed and not event.echo:
  match event.physical_keycode:
   KEY_SPACE:begin(speed)
   KEY_R:reset_probe()
   KEY_B:barrier_toggle.button_pressed=not barrier_toggle.button_pressed
   KEY_1,KEY_2,KEY_3,KEY_4:
    var i: int=event.physical_keycode-KEY_1
    mode_picker.select(i)
    view.set_mode(i)
   KEY_ESCAPE:get_tree().quit()

func _verify_run() -> void:
 var m: Dictionary=solver.metrics()
 m['speed_kmh']=speed
 m['weak_rail']=weak_toggle.button_pressed
 m['symmetric_boundary']=bool(solver.config.enforce_symmetry) and not solver.weak_rail and solver.impact_mode==0
 var lengths: Array=[]
 for link in solver.links:lengths.append(link.length)
 m['plastic_rest_lengths_m']=lengths
 m['binding_quality']=view.binding_quality()
 var finite:=true
 for i in solver.points.size():finite=finite and solver.points[i].is_finite() and solver.velocities[i].is_finite()
 m['all_finite']=finite
 var max_x: float=-100
 var min_y: float=100
 for i in solver.points.size():
  var hit: Dictionary=solver.barrier_distance(solver.points[i])
  if solver.wheels.by_node.has(i):
   var w=solver.wheels.wheels[solver.wheels.by_node[i]]
   var r: Vector3=solver.wheels.support(w,-hit.normal)
   max_x=maxf(max_x,-float(hit.distance)-hit.normal.dot(r)-w.max_compression)
   min_y=minf(min_y,solver.points[i].y+solver.wheels.support(w,Vector3.DOWN).y+w.max_compression)
  else:
   max_x=maxf(max_x,solver.radii[i]-float(hit.distance))
   min_y=minf(min_y,solver.points[i].y-solver.radii[i])
 m['maximum_wall_penetration_m']=max_x
 m['minimum_floor_clearance_m']=min_y
 m['no_energy_explosion']=m.maximum_kinetic_kj<=m.initial_energy_kj*1.04+1.0
 m['mass_accounted_once']=absf(float(m.mass_kg)-1210.0)<.01
 var actual_change:=0.0
 for l in solver.links:actual_change+=absf(l.length-l.original)
 m['permanent_rest_change_m']=actual_change
 m['passed']=m.all_finite and m.no_energy_explosion and m.mass_accounted_once and max_x<.005 and min_y>-.005 and m.yielded_links>0 and m.binding_quality.maximum_bone_anchor_error_m<0.001 and m.binding_quality.maximum_weight_sum_error<0.0001 and m.binding_quality.maximum_wheel_basis_error<0.001
 results.append(m)
 print('STRUCTURAL_RESULT ',JSON.stringify(m))

func _finish_verification() -> void:
 var escalation: bool=results[0].cabin_shortening_m<results[1].cabin_shortening_m and results[1].cabin_shortening_m<results[3].cabin_shortening_m
 var original: PackedVector3Array=solver.points.duplicate()
 scrub(0)
 var pristine: bool=_maximum_damage()<.001
 scrub(1)
 var restores: bool=solver.points[8].distance_to(original[8])<.001
 reset_probe()
 var clean: bool=solver.links.all(func(l):return is_equal_approx(l.length,l.original)) and _maximum_damage()==0
 var changed:=0.0
 for i in solver.links.size():changed+=absf(results[4].plastic_rest_lengths_m[i]-results[5].plastic_rest_lengths_m[i])
 var strength_affects_result: bool=changed>0.01
 var passed: bool=results.all(func(r):return r.passed) and escalation and pristine and restores and clean and strength_affects_result
 var report: Dictionary={'passed':passed,'engine':Engine.get_version_info(),'solver':'mass-bearing elastic/plastic XPBD graph with rigid wheel orientation/spin, yielding/breakable suspension and selective wheel/body contact','runs':results,'cabin_damage_escalates':escalation,'strength_changes_physical_result':strength_affects_result,'same_boundary_strength_comparison_rest_difference_m':changed,'replay_pristine':pristine,'replay_restores':restores,'reset_restores_rest_lengths':clean,'triangles':view.mesh_triangles,'skin_build_ms':view.build_ms,'max_visual_upload_us':view.max_upload_us}
 FileAccess.open('res://verification/structural_validation.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
 print('STRUCTURAL_VERIFICATION_COMPLETE ',passed)
 get_tree().quit(0 if passed else 1)

func _capture(dt: float) -> void:
 wait_time+=dt
 if wait_time<.5:return
 wait_time=0
 match capture_phase:
  0:_save('wheel_structure.png')
  1:
   mode_picker.select(1)
   view.set_mode(1)
  2:_save('wheel_plain.png')
  3:
   mode_picker.select(2)
   frame_toggle.button_pressed=false
   view.set_mode(2)
  4:_save('wheel_textured.png')
  5:
   yaw=PI/2
  6:_save('wheel_side.png')
  7:
   mode_picker.select(3)
   view.set_mode(3)
  8:
   _save('wheel_ghost.png')
   get_tree().quit()
 capture_phase+=1

func _save(filename: String) -> void:
 RenderingServer.force_draw(false)
 get_viewport().get_texture().get_image().save_png('res://verification/'+filename)
 print('STRUCTURE_PREVIEW ',filename)


func _maximum_damage() -> float:
 var value:=0.0
 for d in solver.node_damage:value=maxf(value,d)
 return value
