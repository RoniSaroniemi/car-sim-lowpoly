extends SceneTree
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Interior=preload('res://scripts/vehicle_interior.gd')
const SkinView=preload('res://scripts/structural_skin.gd')
var viewport: SubViewport
var vehicle: RefCounted
var interior: RefCounted
var view: Node3D
var visual: Node3D
var camera: Camera3D
var label: Label
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var path: String='res://verification/interior_car_evidence.fx'
 if not FileAccess.file_exists(path):push_error('Run verify_vehicle_interior.gd first');quit(1);return
 var file:=FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_ZSTD)
 var frames: Array=file.get_var(false);file.close()
 viewport=SubViewport.new();viewport.size=Vector2i(1440,900);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
 var stage:=Node3D.new();viewport.add_child(stage)
 var world:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color('#24353f');env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color('#e9e7dd');env.ambient_light_energy=.9;world.environment=env;stage.add_child(world)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-20,0);sun.light_energy=1.3;stage.add_child(sun)
 vehicle=Vehicle.new();vehicle.setup('res://vehicles/niva.json',false);vehicle.reset(120)
 interior=vehicle.solver.effects.interior if vehicle.solver.get('effects')!=null else Interior.new()
 if vehicle.solver.get('effects')==null:interior.setup(vehicle.solver)
 view=Node3D.new();view.set_script(SkinView);stage.add_child(view);view.setup(vehicle.solver,vehicle.profile.model);view.show_frame=false;view.set_mode(2)
 for record in view.records:
  var node: MeshInstance3D=record.node
  if node.name=='Niva_Body_Static' or str(node.name).begins_with('Panel_'):node.visible=false
  if node.name=='Niva_Interior_Static':
   var material: ShaderMaterial=node.mesh.surface_get_material(0).duplicate()
   var shader:=Shader.new();shader.code=material.shader.code.replace('void fragment() {','void fragment() {\n if(COLOR.r>0.20 && COLOR.g>0.20) discard;')
   material.shader=shader;node.mesh.surface_set_material(0,material)
 visual=view.get_node_or_null('InteriorSeatAndAirbagEffects')
 if visual==null:visual=interior.create_visual(view,view.body);view.add_child(visual)
 camera=Camera3D.new();camera.current=true;camera.fov=55;camera.far=100;stage.add_child(camera)
 var fill:=DirectionalLight3D.new();fill.light_energy=.8;camera.add_child(fill)
 var canvas:=CanvasLayer.new();stage.add_child(canvas)
 var panel:=PanelContainer.new();panel.position=Vector2(20,20);canvas.add_child(panel)
 var style:=StyleBoxFlat.new();style.bg_color=Color(.03,.06,.08,.93);style.content_margin_left=13;style.content_margin_right=13;style.content_margin_top=11;style.content_margin_bottom=11;panel.add_theme_stylebox_override('panel',style)
 label=Label.new();label.add_theme_font_size_override('font_size',17);panel.add_child(label)
 var peak:=0;var full_bag:=0
 for i in frames.size():
  if frames[i].interior.seats[0].angle>frames[peak].interior.seats[0].angle:peak=i
  if full_bag==0 and frames[i].interior.airbag.deployment>.90:full_bag=i
 for item in [['before',0],['deployment',full_bag],['peak',peak],['after',frames.size()-1]]:
  var frame: Dictionary=frames[item[1]]
  vehicle.solver.restore(frame.body)
  if vehicle.solver.get('effects')==null:interior.restore_interpolated(frame.interior,frame.interior,0)
  view.update_pose();visual._process(0)
  var mount: Transform3D=interior.seat_mount(0)
  var target: Vector3=mount*Vector3(-.01,1.15,.28)
  camera.position=target+mount.basis*Vector3(-.60,.34,1.05)
  camera.look_at(target)
  label.text='ACTUAL CAR INTERIOR / 120 km/h authoring\nTime %.3f s · driver back %.1f° · permanent %.1f°\nOptional airbag %.0f%% · %d cloth nodes\nPlayback cloth solves: %d\nCutaway hides exterior/headliner for inspection.' %[frame.body.time,rad_to_deg(interior.seats[0].angle),rad_to_deg(interior.seats[0].plastic_angle),interior.bag.deployment*100,interior.bag.points.size(),interior.cloth_steps]
  await process_frame
  await RenderingServer.frame_post_draw
  viewport.get_texture().get_image().save_png('res://verification/actual_interior_'+item[0]+'.png')
  print('ACTUAL_INTERIOR_CAPTURE ',item[0],' time=',frame.body.time,' angle=',interior.seats[0].angle)
 quit()
