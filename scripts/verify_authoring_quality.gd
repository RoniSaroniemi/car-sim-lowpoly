extends SceneTree
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Fixture=preload('res://scripts/body_impact_fixture.gd')
var checks: Dictionary={}
var runs: Array=[]
var fallback_allowed:=false
func _initialize() -> void:call_deferred('_run')
func apply_quality(vehicle: RefCounted,quality: int) -> bool:
 if vehicle.has_method('set_simulation_quality'):
  vehicle.set_simulation_quality(quality)
  return true
 assert(fallback_allowed,'Shared quality API is required; --allow-quality-fallback permits isolated physical study only.')
 vehicle.solver.config.fixed_step_s=1.0/(480*quality)
 vehicle.solver.config['simulation_quality_multiplier']=quality
 for link in vehicle.solver.links:link.damping_fraction=1-exp(-link.damping_ns_per_m*link.weight_sum*vehicle.solver.config.fixed_step_s)
 return false
func test_case(scenario: String,quality: int) -> void:
 var vehicle:=Vehicle.new();vehicle.setup('res://vehicles/niva.json',false)
 vehicle.adaptive_enabled=false
 var g: RefCounted=vehicle.solver
 if scenario=='roof_corner':Fixture.start(vehicle,scenario)
 elif scenario=='narrow_offset':
  g.set_impact_mode(1);g.barrier_max.x=.015
  vehicle.reset(175,Vector3(-1.84,0,0));g.config.enforce_symmetry=false
 else:
  g.set_impact_mode(0);vehicle.reset(120);g.config.enforce_symmetry=false
 var api_used: bool=apply_quality(vehicle,quality)
 var dt: float=g.config.fixed_step_s
 var initial_metrics: Dictionary=Fixture.metrics(g)
 var initial_energy: float=g.kinetic_energy()
 for i in g.points.size():initial_energy+=g.masses[i]*g.config.gravity_mps2*g.points[i].y
 var maximum_energy: float=initial_energy
 var minimum_floor:=INF;var minimum_wall:=INF
 var height_loss:=0.0;var tunnel_count:=0
 var elapsed_us:=0
 var duration: float=1.2 if scenario=='frontal' else .8
 var expected_steps: int=roundi(duration/dt)
 var finite:=true
 for step in expected_steps:
  var before: PackedVector3Array=g.points.duplicate()
  var began: int=Time.get_ticks_usec()
  vehicle.step(dt)
  elapsed_us+=Time.get_ticks_usec()-began
  var energy: float=g.kinetic_energy()
  for i in g.points.size():
   finite=finite and g.points[i].is_finite() and g.velocities[i].is_finite()
   energy+=g.masses[i]*g.config.gravity_mps2*g.points[i].y
   if g.wheels.by_node.has(i):continue
   minimum_floor=minf(minimum_floor,g.points[i].y-g.radii[i])
   if g.barrier_enabled:
    var hit: Dictionary=g.barrier_distance(g.points[i])
    minimum_wall=minf(minimum_wall,hit.distance-g.radii[i])
    if before[i].x<g.barrier_min.x-g.radii[i]-1e-5 and g.points[i].x>=g.barrier_max.x+g.radii[i]-1e-5:
     var fraction: float=(g.barrier_min.x-before[i].x)/(g.points[i].x-before[i].x)
     var crossing: Vector3=before[i].lerp(g.points[i],fraction)
     if crossing.y>=g.barrier_min.y and crossing.y<=g.barrier_max.y and crossing.z>=g.barrier_min.z and crossing.z<=g.barrier_max.z:tunnel_count+=1
  maximum_energy=maxf(maximum_energy,energy)
  if step%quality==0:
   var metrics: Dictionary=Fixture.metrics(g)
   height_loss=maxf(height_loss,initial_metrics.cabin_height_m-metrics.cabin_height_m)
 var final: Dictionary=Fixture.metrics(g)
 var key: String=scenario+'_'+str(quality)
 checks[key+'_finite']=finite
 checks[key+'_actual_step_count']=g.step_count==expected_steps
 checks[key+'_configured_hz']=absf(1.0/dt-480*quality)<.0001
 checks[key+'_floor_penetration_bounded']=minimum_floor>-.01
 checks[key+'_energy_bounded']=maximum_energy<initial_energy*1.1+1000
 checks[key+'_damping_matches_dt']=g.links.all(func(link):return absf(link.damping_fraction-(1-exp(-link.damping_ns_per_m*link.weight_sum*dt)))<1e-8)
 checks[key+'_fixed_mass_and_topology']=g.points.size()==38 and g.links.size()==187 and absf(float(g.config.mass_kg)-1210)<.01
 var record: Dictionary={'case':scenario,'quality_multiplier':quality,'physics_hz':480*quality,'used_shared_quality_api':api_used,'duration_s':duration,'steps':g.step_count,'finite':finite,'minimum_floor_clearance_m':minimum_floor,'minimum_wall_clearance_m':minimum_wall if is_finite(minimum_wall) else null,'unresolved_center_sweeps':tunnel_count,'initial_mechanical_energy_j':initial_energy,'maximum_mechanical_energy_j':maximum_energy,'peak_cabin_height_loss_m':height_loss,'final_cabin_height_m':final.cabin_height_m,'front_shortening_m':g.metrics().front_shortening_m,'plastic_work_kj':final.plastic_work_kj,'cpu_ms_simulation_calls':elapsed_us/1000.0,'mean_us_per_physics_step':float(elapsed_us)/expected_steps,'nodes':38,'links':187}
 runs.append(record)
 print('AUTHORING_QUALITY ',JSON.stringify(record))
func _run() -> void:
 fallback_allowed='--allow-quality-fallback' in OS.get_cmdline_user_args()
 var probe:=Vehicle.new();probe.setup('res://vehicles/niva.json',false)
 checks['shared_api_or_explicit_study_fallback']=probe.has_method('set_simulation_quality') or fallback_allowed
 apply_quality(probe,4)
 Fixture.start(probe,'roof_corner')
 checks['material_apply_preserves_quality']=absf(1.0/float(probe.solver.config.fixed_step_s)-1920)<.0001
 Fixture.restore(probe)
 checks['material_restore_preserves_quality']=absf(1.0/float(probe.solver.config.fixed_step_s)-1920)<.0001
 for scenario in ['frontal','roof_corner','narrow_offset']:
  for quality in [1,2,4]:test_case(scenario,quality)
 checks['all_nine_cases_completed']=runs.size()==9
 if runs.size()==9:
  checks['high_quality_thin_contact_not_worse']=runs[8].unresolved_center_sweeps<=runs[6].unresolved_center_sweeps
  checks['roof_collapse_retained_at_all_qualities']=runs.slice(3,6).all(func(r):return r.peak_cabin_height_loss_m>.10)
 var passed: bool=checks.values().all(func(value):return value)
 var report: Dictionary={'passed':passed,'checks':checks,'runs':runs,'scope':'Controlled local full-solver temporal refinement. Timings include vehicle.step calls only, excluding metrics, rendering and setup. Higher substeps do not establish calibrated physical accuracy or guarantee convergence of damage thresholds.'}
 FileAccess.open('res://verification/authoring_quality_validation.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('AUTHORING_QUALITY_VERIFIED ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
