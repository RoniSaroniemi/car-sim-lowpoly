extends SceneTree
const Arena=preload('res://arena/vehicle.gd')
const Terrain=preload('res://arena/terrain.gd')
const Roof=preload('res://scripts/roof_landing_geometry.gd')
const Ground=preload('res://scripts/ground_impact_geometry.gd')
var runs: Array=[]
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 for speed in [35.,50.,70.]:
  for offset in [-.5,.5]:
   var car:=Arena.new();car.setup();car.solver.terrain=Terrain.new();car.solver.barrier_enabled=false
   car.reset(speed,Vector3(-24,0,-50+offset));car.set_controls(.4,0,0)
   var lowest_up:=1.;var first_rejection:='';var airborne:=false;var roof_gap:=INF
   for tick in 1440:
    car.advance(1./120)
    var up: Vector3=Roof.basis(car.solver).y
    lowest_up=minf(lowest_up,up.y)
    if up.y<-.05:
     for probe in Roof.probes(car.solver):
      if probe.source=='wheel' or probe.rest.y<1.15:continue
      var contact: Dictionary=Ground.gap(car.solver,probe.position,probe.radius)
      if -up.dot(contact.normal)>.05:roof_gap=minf(roof_gap,contact.distance)
    var clear:=true
    for wheel in car.solver.wheels.wheels:
     var p: Vector3=car.solver.points[wheel.node]+car.solver.wheels.support(wheel,Vector3.DOWN)
     if p.y-car.solver.floor_sample(p).w<.1:clear=false
    airborne=airborne or clear
    if car.roof_landing_sensor.last_rejection!='':first_rejection=car.roof_landing_sensor.last_rejection
    if car.impact_history.any(func(hit):return hit.get('contact_family','')=='roof_landing_floor'):break
   runs.append({'speed_kmh':speed,'seam_offset_m':offset,'airborne':airborne,'minimum_inverted_roof_gap_m':roof_gap,'roof_supported':roof_gap<=.015,'maximum_roll_deg':rad_to_deg(acos(clampf(lowest_up,-1,1))),'bakes':car.baked_count,'roof_hits':car.impact_history.filter(func(hit):return hit.get('contact_family','')=='roof_landing_floor').size(),'last_rejection':first_rejection,'last_bake':car.last_bake,'full_steps':car.full_steps})
   print('DRIVEN_ROLLOVER ',JSON.stringify(runs[-1]))
 var passed: bool=runs.any(func(run):return run.roof_hits>=1) and runs.all(func(run):return run.full_steps==0 and (not run.roof_supported or run.roof_hits>=1))
 FileAccess.open('res://verification/roof_response/driven_rollover.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'runs':runs,'scope':'Actual driven seam of the42/24degree ramps, not teleported roof poses; some trajectories do not roll far enough to hit the roof.'},'\t'))
 print('DRIVEN_ROLLOVER_VERIFIED ',passed)
 quit(0 if passed else 1)
