extends SceneTree
const Vehicle=preload('res://tools/probes/baked_trigger_investigation/baseline_driving_vehicle.gd')
func _initialize() -> void:
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification/trigger_investigation'))
 call_deferred('_run')
func cheap_forecast(car: RefCounted,horizon: float) -> float:
 var g: RefCounted=car.solver
 var center: Vector3=car.compact.center
 var motion: Vector3=car.compact.linear_velocity
 var offset: Vector3=(g.barrier_min-center).max(center-g.barrier_max).max(Vector3.ZERO)
 var extent: float=3.5+motion.length()*horizon
 if offset.length_squared()>extent*extent:return INF
 var earliest:=INF
 for i in g.points.size():
  var radius: float=g.radii[i]
  var a: Vector3=g.barrier_min-Vector3.ONE*radius
  var b: Vector3=g.barrier_max+Vector3.ONE*radius
  var entry:=0.0;var exit:=horizon;var hit:=true
  for axis in 3:
   var v: float=g.velocities[i][axis]
   if absf(v)<1e-7:
    if g.points[i][axis]<a[axis] or g.points[i][axis]>b[axis]:hit=false
   else:
    var ta: float=(a[axis]-g.points[i][axis])/v
    var tb: float=(b[axis]-g.points[i][axis])/v
    entry=maxf(entry,minf(ta,tb));exit=minf(exit,maxf(ta,tb))
   if entry>exit:hit=false
  if hit and exit>=0 and entry<=horizon:earliest=minf(earliest,maxf(0,entry))
 return earliest
func _run() -> void:
 var car:=Vehicle.new();car.setup()
 car.solver.barrier_min=Vector3(40,0,-8);car.solver.barrier_max=Vector3(41,3,8)
 var results: Array=[]
 for distance in [65.0,5.0,2.05]:
  car.reset(120,Vector3(40-distance,0,0))
  var n:=10000
  var began: int=Time.get_ticks_usec()
  var hits:=0
  for i in n:
   if is_finite(cheap_forecast(car,.100)):hits+=1
  var cheap_us: float=float(Time.get_ticks_usec()-began)/n
  began=Time.get_ticks_usec()
  var existing_hits:=0
  for i in n:
   if not car._contact_event(1.0/120).is_empty():existing_hits+=1
  var actual_us: float=float(Time.get_ticks_usec()-began)/n
  results.append({'distance_to_wall_origin_m':distance,'trials':n,'cheap_100ms_forecast_us':cheap_us,'existing_oneframe_detector_us':actual_us,'forecast_hits':hits,'existing_event_hits':existing_hits,'full_solver_steps':car.solver.step_count,'legacy_forecast_calls':car.forecast.checks,'library_rankings_by_forecast':0})
  print('FORECAST_COST ',JSON.stringify(results[-1]))
 FileAccess.open('res://verification/trigger_investigation/forecast_cost.json',FileAccess.WRITE).store_string(JSON.stringify({'runs':results,'scope':'Headless repeated detector calls only; excludes setup, physics, rendering. Forecast produces only TOI and does not rank library.'},'\t'))
 quit()
