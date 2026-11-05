extends SceneTree
var scene: Node3D
var ticks:=0
var variant:=0
var render_cpu: Array=[]
var render_gpu: Array=[]
var results: Array=[]
var updates: Array=[]
func _initialize() -> void:call_deferred('_start')
func _start() -> void:
 scene=load('res://arena/colosseum.tscn').instantiate();root.add_child(scene)
 root.size=Vector2i(1440,900)
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 scene.set_physics_process(false)
 _variant()
func _variant() -> void:
 ticks=0;render_cpu=[];render_gpu=[];updates=[]
 scene.car.reset(0,Vector3(-12,0,0));scene.car.solver.barrier_enabled=false
 scene.camera_mode=2 if variant==0 else 1
 for node in scene.stadium.get_children():
  if node is GeometryInstance3D:node.visible=variant!=2
func _process(_dt: float) -> bool:
 if scene==null:return false
 ticks+=1
 if ticks<40:return false
 var rid: RID=root.get_viewport_rid()
 render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
 render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
 var began:=Time.get_ticks_usec();scene.car.advance(1.0/120);updates.append(Time.get_ticks_usec()-began)
 if ticks<160:return false
 var result: Dictionary={'view':['overview','driver','car_only_same_sky'][variant],'viewport':[root.size.x,root.size.y],'render_cpu_mean_ms':average(render_cpu),'render_gpu_mean_ms':average(render_gpu),'gpu_timings_available':average(render_gpu)>.0001,'physics_mean_us_per_120hz':average(updates),'full_solver_steps':scene.car.full_steps,'draw_calls':root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),'primitives':root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),'objects':root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_OBJECTS_IN_FRAME)}
 results.append(result)
 print('ARENA_NATIVE_BUDGET ',JSON.stringify(result))
 variant+=1
 if variant<3:_variant()
 else:
  var report: Dictionary={'device':RenderingServer.get_video_adapter_name(),'renderer':RenderingServer.get_current_rendering_method(),'arena_instances':scene.stadium.instances,'arena_triangle_instances':scene.stadium.mesh_triangles,'unique_meshes':scene.stadium.measured_meshes.size(),'serialized_mesh_array_bytes':scene.stadium.mesh_array_bytes,'instance_transform_bytes':scene.stadium.instances*48,'generation_cpu_ms':scene.stadium.load_ms,'runs':results,'scope':'One native scene,1440x900,120samples after40warmupframes perview. CPU submission is not complete frame time. ZeroGPUtimestamp means unavailable. Car-only control hides arena geometry, retaining identical light/environment/car. Serialized geometry and transform payload exclude engine/GPU allocation overhead.'}
  FileAccess.open('res://arena/evidence/native_budget.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'));quit()
 return false
func average(values: Array) -> float:
 var sum:=0.0
 for value in values:sum+=float(value)
 return sum/maxi(1,values.size())
