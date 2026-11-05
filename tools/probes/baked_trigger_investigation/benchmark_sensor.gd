extends SceneTree
const Vehicle=preload('res://tools/probes/baked_trigger_investigation/baseline_driving_vehicle.gd')
const Sensor=preload('res://scripts/baked_contact_sensor.gd')
func _initialize() -> void:
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification/trigger_investigation'))
 call_deferred('_run')
func _run() -> void:
 var car:=Vehicle.new();car.setup()
 car.solver.barrier_min=Vector3(40,0,-8);car.solver.barrier_max=Vector3(41,3,8)
 var runs: Array=[]
 for distance in [65.0,5.0,2.05]:
  car.reset(120,Vector3(40-distance,0,0))
  var sensor:=Sensor.new()
  var trials:=10000
  var began: int=Time.get_ticks_usec()
  var events:=0
  for index in trials:
   # Force the scheduled forecast for a standalone per-forecast cost. Normal
   # driving limits this pass to30Hz and leaves clear roads at the broad phase.
   sensor.next_forecast_s=0
   if not sensor.event(car.solver,car.velocity(),1.0/120).is_empty():events+=1
  var total_us: int=Time.get_ticks_usec()-began
  var cost: Dictionary={'distance_m':distance,'trials':trials,'event_mean_us':float(total_us)/trials,'forecast_mean_us':float(sensor.forecast_cpu_us)/maxi(1,sensor.forecast_checks),'events':events,'sensor':sensor.statistics(),'full_solver_steps':car.solver.step_count,'legacy_forecasts':car.forecast.checks}
  runs.append(cost);print('PRODUCTION_SENSOR_COST ',JSON.stringify(cost))
 FileAccess.open('res://verification/trigger_investigation/production_sensor_cost.json',FileAccess.WRITE).store_string(JSON.stringify({'runs':runs,'scope':'Repeated helper calls only, forced forecast schedule; excludes physics, owner gates, bank ranking and rendering. Timing is evidence, not a CI threshold.'},'\t'))
 quit()
