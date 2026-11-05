extends SceneTree
const Partial=preload('res://scripts/partial_crash_library.gd')
const Driving=preload('res://scripts/driving_vehicle.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Stage=preload('res://scripts/partial_wall_staging.gd')
var viewport: SubViewport
var scene: Node3D
var saved:=false
var before_saved:=false
var debug_mesh: MeshInstance3D
var debug_material: StandardMaterial3D
var age:=0.0
var output: String='partial_corner'
var directory: String='res://verification/partial_bakes'
var angle:=20.0
var overlap:=.5
var side: String='right'
func _initialize() -> void:call_deferred('_start')
func _start() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with('--directory='):directory=arg.trim_prefix('--directory=')
  if arg.begins_with('--angle='):angle=float(arg.trim_prefix('--angle='))
  if arg.begins_with('--overlap='):overlap=float(arg.trim_prefix('--overlap='))
  if arg.begins_with('--side='):side=arg.trim_prefix('--side=')
  if arg.begins_with('--output='):output=arg.trim_prefix('--output=')
 Driving.cached_library=Clip.read_library()+Partial.read_library(directory)
 viewport=SubViewport.new();viewport.size=Vector2i(1440,900);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 root.add_child(viewport)
 scene=load('res://driving.tscn').instantiate();viewport.add_child(scene)
 scene.set_physics_process(false);scene.set_process(false)
 Stage.stage(scene.vehicle,60,angle,overlap,side)
 scene.camera_mode=2;scene.orbit=0
 debug_mesh=MeshInstance3D.new();scene.add_child(debug_mesh)
 debug_material=StandardMaterial3D.new();debug_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;debug_material.albedo_color=Color(1,.65,.1);debug_material.no_depth_test=true;debug_mesh.material_override=debug_material
 var layer:=CanvasLayer.new();scene.add_child(layer)
 var label:=Label.new();label.position=Vector2(690,25)
 label.text='FINITE WALL / %.0f%% %s / %.0f°\nActual driving → coverage-aware bake → rigid aftermath'%[overlap*100,side,angle]
 label.add_theme_font_size_override('font_size',18);layer.add_child(label)
func _process(dt: float) -> bool:
 if scene==null:return false
 age+=dt
 scene.vehicle.advance(minf(dt,.0333)*.4)
 scene._process(dt)
 _draw_grid()
 if age>.13 and not before_saved and scene.vehicle.baked_count==0:
  _save(output+'_before.png');before_saved=true
 if scene.vehicle.mode=='BAKED' and scene.vehicle.crash_player.time>.3 and not saved:
  _save(output+'_impact.png');saved=true
 if scene.vehicle.last_bake.get('completed',false):
  _save(output+'_aftermath.png');quit()
 if age>18:
  print('PREVIEW_REJECTED ',scene.vehicle.contact_sensor.last_rejection);_save(output+'_rejected.png');quit(1)
 return false
func _save(name_: String) -> void:
 RenderingServer.force_draw(false)
 viewport.get_texture().get_image().save_png('res://verification/partial_coverage/'+name_)
 print('PARTIAL_PREVIEW ',name_,' ',JSON.stringify(scene.vehicle.last_bake))

func _draw_grid() -> void:
 var g: RefCounted=scene.vehicle.solver
 var grid=preload('res://scripts/impact_zone_grid.gd').new()
 var basis: Basis=grid.body_basis(g)
 var origin: Vector3=g.station_center(2)
 var rest_origin:=Vector3.ZERO
 for i in range(8,12):rest_origin+=g.rest[i]*.25
 var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES)
 for axis in 3:
  var a: int=(axis+1)%3;var b: int=(axis+2)%3
  for i in grid.counts[a]+1:
   for j in grid.counts[b]+1:
    var p: Vector3=grid.low;p[a]+=grid.size[a]*i/grid.counts[a];p[b]+=grid.size[b]*j/grid.counts[b]
    var q: Vector3=p;q[axis]+=grid.size[axis]
    mesh.surface_add_vertex(origin+basis*(p-rest_origin));mesh.surface_add_vertex(origin+basis*(q-rest_origin))
 mesh.surface_end();debug_mesh.mesh=mesh
