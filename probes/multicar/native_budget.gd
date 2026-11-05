extends SceneTree
var probe: Node3D
var ticks:=0
var count:=1
var reports: Array=[]
var cpu: Array=[]
var gpu: Array=[]
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 probe=load('res://probes/multicar/probe.tscn').instantiate();root.add_child(probe)
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 _case(1)
func _case(number: int) -> void:
 count=number;ticks=0;cpu.clear();gpu.clear()
 probe._start('triple' if number==3 else 'head_on');probe.paused=true
 if number==1:
  probe.sim.cars.pop_back()
  var skin: Node=probe.skins.pop_back();probe.remove_child(skin);skin.queue_free()
  var label: Node=probe.labels.pop_back();probe.remove_child(label);label.queue_free()
func _process(_dt: float) -> bool:
 if probe==null:return false
 ticks+=1
 if ticks<30:return false
 cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
 gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
 if ticks<90:return false
 var begin: int=Time.get_ticks_usec()
 for repeat in 100:
  for skin in probe.skins:skin.update_pose()
 var pose_us: float=(Time.get_ticks_usec()-begin)/100.0
 var gpu_total:=0.0;var cpu_total:=0.0
 for value in gpu:gpu_total+=value
 for value in cpu:cpu_total+=value
 var report: Dictionary={'cars':number_of_cars(),'visible_draws':root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),'shadow_draws':root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),'visible_primitives_counter':root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),'render_objects':root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_OBJECTS_IN_FRAME),'model_triangles_per_car':57624,'pose_upload_all_cars_us':pose_us,'viewport_cpu_mean_ms':cpu_total/cpu.size(),'viewport_gpu_mean_ms':gpu_total/gpu.size(),'gpu_timestamp_available':gpu_total>0.0001,'full_structure_steps':probe.sim.stats().full_structure_steps}
 reports.append(report);print('MULTICAR_NATIVE_COST ',JSON.stringify(report))
 if count<3:_case(count+1)
 else:
  FileAccess.open('res://probes/multicar/evidence/native_budget.json',FileAccess.WRITE).store_string(JSON.stringify({'size':str(root.size),'renderer':RenderingServer.get_current_rendering_method(),'adapter':RenderingServer.get_video_adapter_name(),'runs':reports,'scope':'Native full probe scene including floor/labels/UI/shadow passes. Warm paused frames, pose upload separately. GPU zero means unavailable; not an FPS or overall memory benchmark.'},'\t'));quit()
 return false
func number_of_cars() -> int:return probe.sim.cars.size()
