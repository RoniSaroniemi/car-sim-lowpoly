extends SceneTree
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Cases=preload('res://scripts/roof_landing_cases.gd')
const Soft=preload('res://scripts/soft_roof_profile.gd')
const Floor=preload('res://scripts/panel_floor_wake.gd')
var runs: Array=[]
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var passed:=true
 for roll in [0.,-60.]:
  var car:=Vehicle.new();car.setup('res://vehicles/niva.json',false)
  Cases.place(car,{'roll_deg':roll,'forward_kmh':0.,'down_mps':0.,'roll_rate':0.},0)
  car.set_simulation_quality(4);car.mode='FULL';car.adaptive_enabled=false;car.solver.barrier_enabled=false;car.solver.compact_active=false
  var g: RefCounted=car.solver;g.config.enforce_symmetry=false;Soft.apply(g);car.before_step.connect(func(h):Floor.step(g,h))
  var initial: float=g.points[10].distance_to(g.points[8]);var minimum:=initial
  for tick in 1920:
   car.advance(1./1920)
   minimum=minf(minimum,g.points[10].distance_to(g.points[8]))
  var ok: bool=minimum<initial-.05 and absf(g.owned_mass_kg()-1210)<.001 and Array(g.points).all(func(p):return p.is_finite())
  passed=passed and ok
  runs.append({'roll_from_upside_down_deg':roll,'initial_cabin_height_m':initial,'minimum_cabin_height_m':minimum,'roof_crush_m':initial-minimum,'plastic_work_j':g.plastic_work,'mass_kg':g.owned_mass_kg(),'maximum_energy_j':g.maximum_energy,'final_energy_j':g.kinetic_energy(),'passed':ok})
  print('STATIC_LIVE_ROOF roll=',roll,' crush=',initial-minimum,' work=',g.plastic_work)
 FileAccess.open('res://verification/roof_response/static_live.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'runs':runs,'scope':'1920Hz real weak-roof graph, initially resting, zero launch velocity; no playback amplification'},'\t'))
 quit(0 if passed else 1)
