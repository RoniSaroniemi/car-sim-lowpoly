extends SceneTree
const Vehicle=preload('res://scripts/driving_vehicle.gd')
func _initialize() -> void:call_deferred('_run')
func percentile(values: Array,p: float) -> float:
 values.sort();return float(values[clampi(ceili(p*values.size())-1,0,values.size()-1)])/1000.0
func _run() -> void:
 var results: Array=[]
 for speed in [60.0,120.0]:
  for enabled in [false,true]:
   var vehicle:=Vehicle.new();vehicle.setup();vehicle.baked_enabled=enabled
   vehicle.solver.barrier_min=Vector3(40,0,-8);vehicle.solver.barrier_max=Vector3(41,3,8)
   vehicle.reset_wall_approach(speed)
   var samples: Array=[]
   var total:=0
   for frame in 480:
    var began: int=Time.get_ticks_usec()
    vehicle.advance(1.0/120)
    var cost: int=Time.get_ticks_usec()-began
    samples.append(cost);total+=cost
   var result: Dictionary={'speed_kmh':speed,'baked':enabled,'simulated_seconds':4,'total_physics_ms':total/1000.0,'mean_ms_per_120hz_step':total/480000.0,'p99_ms':percentile(samples,.99),'forecast_checks':vehicle.forecast.checks,'full_solver_steps':vehicle.solver.step_count,'baked_count':vehicle.baked_count,'rigid_contacts':vehicle.rigid_contact_count}
   results.append(result);print('DRIVING_BAKE_COST ',JSON.stringify(result))
 var passed: bool=results.filter(func(r):return r.baked).all(func(r):return r.forecast_checks==0 and r.full_solver_steps==0 and r.baked_count==1)
 FileAccess.open('res://verification/driving_bakes_performance.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'runs':results,'scope':'Local timed physics/selection/playback calls. Excludes rendering, input, scene setup and bank loading; not an FPS benchmark.'},'\t'))
 quit(0 if passed else 1)
