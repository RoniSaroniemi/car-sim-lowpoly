extends SceneTree
const Base=preload('res://scripts/structure_solver.gd')
const Graph=preload('res://probes/panels/panel_graph.gd')
const NativeSkin=preload('res://scripts/structural_skin.gd')
const PanelSkin=preload('res://probes/panels/panel_skin.gd')
var views: Array=[]
var samples: Array=[]
var ticks:=0
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 root.size=Vector2i(1440,720)
 var row:=HBoxContainer.new();row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(row)
 for index in 2:
  var container:=SubViewportContainer.new();container.stretch=true;container.size_flags_horizontal=Control.SIZE_EXPAND_FILL;container.size_flags_vertical=Control.SIZE_EXPAND_FILL;row.add_child(container)
  var viewport:=SubViewport.new();viewport.size=Vector2i(720,720);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;container.add_child(viewport)
  var stage:=Node3D.new();viewport.add_child(stage)
  var world:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color('#9bafb7');env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color('#dbe8ed');env.ambient_light_energy=.6;world.environment=env;stage.add_child(world)
  var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-35,0);sun.light_energy=.9;stage.add_child(sun)
  var graph: RefCounted=Graph.new() if index==1 else Base.new();graph.setup();graph.reset(0,Vector3.ZERO);graph.config.enforce_symmetry=false;graph.barrier_enabled=false
  if index==1:graph.panels.reset()
  var skin:=Node3D.new();skin.set_script(PanelSkin if index==1 else NativeSkin)
  if index==1:skin.panel_system=graph.panels
  stage.add_child(skin);skin.setup(graph);skin.show_frame=false;skin.set_mode(2)
  var camera:=Camera3D.new();camera.current=true;camera.fov=48;stage.add_child(camera);camera.position=Vector3(5,3,5);camera.look_at(Vector3(0,1,0))
  views.append({'viewport':viewport,'graph':graph,'skin':skin,'name':'articulated' if index==1 else 'baseline'})
  RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
  samples.append({'cpu':[],'gpu':[]})
func mean(values: Array) -> float:
 var sum:=0.0
 for value in values:sum+=float(value)
 return sum/maxi(1,values.size())
func _process(_dt: float) -> bool:
 if views.size()!=2:return false
 ticks+=1
 if ticks<20:return false
 for index in 2:
  var rid: RID=views[index].viewport.get_viewport_rid()
  samples[index].cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid));samples[index].gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
 if ticks<80:return false
 var rows: Array=[]
 for index in 2:
  var item: Dictionary=views[index];var began: int=Time.get_ticks_usec()
  for i in 200:item.skin.update_pose()
  var pose_us: float=(Time.get_ticks_usec()-began)/200.0
  rows.append({'mode':item.name,'viewport_size':str(item.viewport.size),'draw_calls':item.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),'rendered_objects':item.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_OBJECTS_IN_FRAME),'triangles':item.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),'cpu_render_ms':mean(samples[index].cpu),'gpu_render_ms':mean(samples[index].gpu),'gpu_timers_available':mean(samples[index].gpu)>.00001,'pose_upload_us':pose_us,'full_solver_steps':item.graph.step_count,'active_panel_cages':0})
 var report: Dictionary={'device':RenderingServer.get_video_adapter_name(),'method':RenderingServer.get_current_rendering_method(),'runs':rows,'scope':'Native matched intact original vs articulated skins. Rendering counters and CPU pose calls only; zero GPU timestamp means unavailable. Active live constraint costs are separate in validation.json.'}
 FileAccess.open('res://probes/panels/evidence/native_budget.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
 RenderingServer.force_draw(false);root.get_texture().get_image().save_png('res://probes/panels/evidence/intact_comparison.png')
 print('PANEL_NATIVE_BUDGET ',JSON.stringify(report));quit()
 return false
