extends SceneTree
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Fixture=preload('res://scripts/body_impact_fixture.gd')
var runs: Array=[]
var checks: Dictionary={}
func _initialize() -> void:call_deferred('_run')
func test_case(scenario: String,experimental: bool) -> void:
 var vehicle:=Vehicle.new();vehicle.setup('res://vehicles/niva.json',false)
 var original: Dictionary=vehicle.solver.config.duplicate(true)
 Fixture.start(vehicle,scenario,1.0,experimental)
 var g: RefCounted=vehicle.solver
 var before: Dictionary=Fixture.metrics(g)
 var minimum_height: float=before.cabin_height_m;var minimum_width: float=before.cabin_width_m
 var roof_span_loss:=0.0
 var initial_energy: float=g.kinetic_energy()
 for i in g.points.size():initial_energy+=g.masses[i]*g.config.gravity_mps2*g.points[i].y
 var max_energy: float=initial_energy
 var samples: Array=[]
 for step in 1440:
  vehicle.step(1.0/480)
  if step%24==0:
   var m: Dictionary=Fixture.metrics(g)
   minimum_height=minf(minimum_height,m.cabin_height_m);minimum_width=minf(minimum_width,m.cabin_width_m)
   for i in m.roof_spans_m.size():roof_span_loss=maxf(roof_span_loss,before.roof_spans_m[i]-m.roof_spans_m[i])
   var energy: float=g.kinetic_energy()
   for i in g.points.size():energy+=g.masses[i]*g.config.gravity_mps2*g.points[i].y
   max_energy=maxf(max_energy,energy)
   samples.append({'time':g.simulated_time,'height':m.cabin_height_m,'width':m.cabin_width_m})
 var final: Dictionary=Fixture.metrics(g)
 # Remove contact/gravity load, preserving plastic lengths, then let elasticity relax.
 g.config.gravity_mps2=0;g.barrier_enabled=false
 for i in g.points.size():g.points[i].y+=10;g.velocities[i]=Vector3.ZERO
 for wheel in g.wheels.wheels:wheel.angular_velocity=Vector3.ZERO;wheel.spin_speed=0
 for step in 240:vehicle.step(1.0/480)
 var unloaded: Dictionary=Fixture.metrics(g)
 var key: String=scenario+('_experimental' if experimental else '_baseline')
 checks[key+'_finite']=final.finite and unloaded.finite
 checks[key+'_floor_nonpenetration']=final.minimum_floor_clearance_m>-.005
 checks[key+'_no_energy_growth']=max_energy<initial_energy*1.08+1000
 checks[key+'_full_solver_used']=g.step_count>=1680 and not g.compact_active
 checks[key+'_mass_topology_preserved']=g.points.size()==38 and g.links.size()==187 and absf(float(g.config.mass_kg)-1210)<.01
 Fixture.restore(vehicle)
 checks[key+'_restores_original_materials']=g.config.links==original.links and vehicle.adaptive_enabled
 runs.append({'case':scenario,'experimental':experimental,'before':before,'final':final,'unloaded':unloaded,'maximum_cabin_height_loss_m':before.cabin_height_m-minimum_height,'maximum_cabin_width_loss_m':before.cabin_width_m-minimum_width,'maximum_local_roof_span_loss_m':roof_span_loss,'initial_mechanical_energy_j':initial_energy,'maximum_mechanical_energy_j':max_energy,'samples':samples})
 print('BODY_CASE ',key,' height_loss=',before.cabin_height_m-minimum_height,' width_loss=',before.cabin_width_m-minimum_width,' roof_span_loss=',roof_span_loss,' work=',final.plastic_work_kj)
func _run() -> void:
 for experimental in [false,true]:
  for scenario in Fixture.CASES:test_case(scenario,experimental)
 checks['all_six_cases_completed']=runs.size()==6
 if runs.size()==6:
  for index in 2:
   checks['roof_case_%d_intrudes_more'%index]=runs[index+3].maximum_cabin_height_loss_m>runs[index].maximum_cabin_height_loss_m*5 and runs[index+3].maximum_cabin_height_loss_m>.12
   checks['roof_case_%d_permanent_after_unload'%index]=runs[index+3].before.cabin_height_m-runs[index+3].unloaded.cabin_height_m>.10
  checks['side_case_upper_frame_intrudes_more']=runs[5].maximum_local_roof_span_loss_m>runs[2].maximum_local_roof_span_loss_m*1.5
 var passed: bool=checks.values().all(func(value):return value)
 FileAccess.open('res://verification/body_impacts_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':runs,'scope':'Live full solver, game material comparison; no calibrated crash-engineering prediction.'},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('BODY_IMPACT_VERIFICATION ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
