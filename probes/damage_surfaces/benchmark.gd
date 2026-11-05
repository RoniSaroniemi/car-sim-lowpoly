extends SceneTree
var probe: Control
var ticks:=0
var case_index:=0
var samples: Array=[]
var reports: Array=[]
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 root.size=Vector2i(1920,1080)
 probe=load('res://probes/damage_surfaces/probe.tscn').instantiate();root.add_child(probe)
 for item in probe.views:RenderingServer.viewport_set_measure_render_time(item.viewport.get_viewport_rid(),true)
 _case(0)
func _case(index: int) -> void:
 case_index=index;ticks=0;samples=[];probe.closeup=true;probe._select(index)
 for i in 3:samples.append({'cpu':[],'gpu':[]})
func _process(_dt: float) -> bool:
 if probe==null:return false
 ticks+=1
 if ticks<30:return false
 for i in 3:
  var rid: RID=probe.views[i].viewport.get_viewport_rid()
  samples[i].cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
  samples[i].gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
 if ticks<150:return false
 for i in 3:
  var began: int=Time.get_ticks_usec()
  for iteration in 100:probe.views[i].skin.update_pose()
  var cpu_us: float=(Time.get_ticks_usec()-began)/100.
  var gpu_mean: float=average(samples[i].gpu)
  reports.append({'case':case_index,'appearance':['original','current','layered'][i],'viewport_size':str(probe.views[i].viewport.size),'render_cpu_mean_ms':average(samples[i].cpu),'render_gpu_mean_ms':gpu_mean,'gpu_timings_available':gpu_mean>0.0001,'pose_upload_mean_us':cpu_us,'physics_steps':probe.views[i].car.solver.step_count})
 if case_index<2:_case(case_index+1)
 else:
  var report: Dictionary={'device':RenderingServer.get_video_adapter_name(),'method':RenderingServer.get_current_rendering_method(),'runs':reports,'scope':'Native1920x1080 three-column comparison, each subviewport measured by Godot. Columns render concurrently; excludes a complete gameplay scene. Zero GPU timing means unavailable, not free shading.'}
  FileAccess.open('res://probes/damage_surfaces/evidence/native_budget.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
  print('DAMAGE_SURFACE_NATIVE_BUDGET ',JSON.stringify(report));quit()
 return false
func average(values: Array) -> float:
 var total:=0.0
 for value in values:total+=float(value)
 return total/maxi(1,values.size())
