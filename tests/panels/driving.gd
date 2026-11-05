extends SceneTree
const Vehicle=preload('res://scripts/driving_vehicle.gd')
var results: Array=[]
var passed:=true
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 for speed_ in [60.,120.]:
  for angle in [0.,20.,-20.,30.,-30.]:
   var v:=Vehicle.new();v.setup();v.baked_enabled=false;v.reset_wall_approach(speed_,angle)
   var finite:=true;var mass_error:=0.;var contactspeed:=0.
   for i in 540:
    var previous: float=v.velocity().length()*3.6
    v.set_controls(0,0,0);v.step(1.0/120)
    if v.solver.impact_started and contactspeed==0:contactspeed=previous
    mass_error=maxf(mass_error,absf(v.solver.owned_mass_kg()-1210))
    for point_ in v.solver.points:finite=finite and point_.is_finite()
   var parts: Array=v.panel_states().map(func(p):return {'id':p.id,'detached':p.detached,'anchors':p.anchors.map(func(a):return a.broken),'seats':p.closing_supports.map(func(a):return a.broken),'latched':p.latched,'plastic_j':p.plastic_work,'contacts':p.contacts,'mode':p.reduced_mode})
   var retained: bool=parts.slice(0,2).all(func(p):return not p.detached and p.latched and p.anchors.all(func(b):return not b) and p.seats.all(func(b):return not b))
   var ok: bool=finite and mass_error<.001 and retained and contactspeed>30 and parts[0].plastic_j+parts[1].plastic_j>1
   passed=passed and ok
   results.append({'speed':speed_,'angle':angle,'contact_kmh':contactspeed,'mass_error_kg':mass_error,'finite':finite,'passed':ok,'parts':parts,'stats':v.statistics()})
   print('MAIN_PANEL_DRIVE ',speed_,'/',angle,' contact=',contactspeed,' retained=',retained,' modes=',parts.map(func(p):return p.mode),' plastic=',parts.map(func(p):return p.plastic_j))
 var v:=Vehicle.new();v.setup();v.baked_enabled=false;v.reset(0,Vector3(-25,0,0));v.solver.barrier_min=Vector3(40,0,-8);v.solver.barrier_max=Vector3(41,3,8)
 for i in 1800:
  v.set_controls(1 if not v.solver.impact_started else 0,0,0);v.step(1.0/120)
 var retained: bool=v.panel_states().all(func(p):return not p.detached)
 passed=passed and retained and v.solver.impact_started
 print('MAIN_PANEL_W_FROM_REST ',retained,' impact=',v.solver.impact_started)
 FileAccess.open('res://tests/panels/driving_results.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'cases':results,'throttle_from_rest_retains':retained},'  '))
 print('MAIN_PANEL_DRIVING_PASS ',passed);quit(0 if passed else 1)
