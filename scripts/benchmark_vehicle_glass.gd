extends SceneTree
const Graph=preload('res://scripts/structure_solver.gd')
const Glass=preload('res://scripts/vehicle_glass.gd')
func _initialize() -> void:call_deferred('_run')
func measure(fx: RefCounted,kind: String,count: int) -> Dictionary:
 var times: Array=[]
 for i in count:
  var start: int=Time.get_ticks_usec()
  if kind=='debris':fx.step_debris(1.0/120)
  else:fx.step_live(1.0/120)
  times.append(Time.get_ticks_usec()-start)
 times.sort()
 var total:=0.0
 for value in times:total+=value
 return {'steps':count,'mean_ms':total/count/1000,'p99_ms':times[int(count*.99)]/1000.0}
func _run() -> void:
 var g:=Graph.new();g.setup();g.reset(0,Vector3.ZERO);g.barrier_enabled=false
 var fx:=Glass.new();fx.setup(g)
 var result: Dictionary={'scope':'CPU module only, Apple M3, Godot 4.7.2 headless debug; excludes renderer, full car solver, load/setup and file IO.'}
 result.dormant_six_panes=measure(fx,'live',240)
 fx.hit_window('windscreen',1.8,false)
 result.live_laminate=measure(fx,'live',240)
 var sheet_state: Dictionary=fx.capture()
 fx.reset();fx.hit_window('door_left',1.3);fx.hit_window('quarter_left',1.3)
 result.debris_initial_count=fx.debris.size();result.capped_debris=measure(fx,'debris',180)
 var a: Dictionary=sheet_state;fx.begin_playback(a)
 var times: Array=[]
 for i in 240:
  var start: int=Time.get_ticks_usec();fx.restore_interpolated(a,a,0);times.append(Time.get_ticks_usec()-start)
 times.sort();var total:=0.0
 for value in times:total+=value
 result.baked_restore={'steps':240,'mean_ms':total/240000,'p99_ms':times[237]/1000.0,'membrane_solves':fx.membrane_solve_steps}
 FileAccess.open('res://verification/vehicle_glass_benchmark.json',FileAccess.WRITE).store_string(JSON.stringify(result,'\t'));print('VEHICLE_GLASS_BENCHMARK ',JSON.stringify(result));quit()
