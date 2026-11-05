extends SceneTree
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var checks: Dictionary={}
 var observations: Array=[]
 for factor in [1,2,4]:
  var car:=Vehicle.new();car.setup('res://vehicles/niva.json',true)
  car.adaptive_enabled=false;car.set_simulation_quality(factor);car.reset(120,Vector3(-5,0,0))
  var began: int=Time.get_ticks_usec()
  car.advance(.25)
  var finite: bool=Array(car.solver.points).all(func(p):return p.is_finite())
  checks[str(factor)+'_step_rate']=car.full_steps==120*factor
  checks[str(factor)+'_finite']=finite
  checks[str(factor)+'_clock']=absf(car.solver.simulated_time-.25)<.00001
  checks[str(factor)+'_time_normalized_damping']=absf(car.solver.links[0].damping_fraction-(1-exp(-car.solver.links[0].damping_ns_per_m*car.solver.links[0].weight_sum*car.solver.config.fixed_step_s)))<1e-8
  observations.append({'factor':factor,'physics_hz':1.0/car.solver.config.fixed_step_s,'full_steps':car.full_steps,'cpu_ms':(Time.get_ticks_usec()-began)/1000.0})
 var passed: bool=checks.size()==12 and checks.values().all(func(value):return value)
 FileAccess.open('res://verification/quality_smoke.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':observations},'\t'))
 print('QUALITY_SMOKE ',passed,' ',JSON.stringify(observations))
 quit(0 if passed else 1)
