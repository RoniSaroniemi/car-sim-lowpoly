extends SceneTree
## Requires unmodified 2ad1656 sources staged under verification/contact_baseline.
const Current=preload('res://scripts/vehicle_simulation.gd')
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var legacy: GDScript=load('res://verification/contact_baseline/vehicle_simulation.gd')
 if legacy==null:push_error('Run python3 arena/prepare_contact_baseline.py first');quit(1);return
 var runs: Array=[];var passed:=true
 for spec in [[false,60.],[false,120.],[true,0.]]:
  var a: RefCounted=legacy.new();var b:=Current.new()
  a.setup('res://vehicles/niva.json',spec[0]);b.setup('res://vehicles/niva.json',spec[0])
  a.reset(spec[1],Vector3(-4,0,0));b.reset(spec[1],Vector3(-4,0,0))
  if spec[0]:
   a.solver.barrier_enabled=false;b.solver.barrier_enabled=false
   a.set_controls(1,.1,.5);b.set_controls(1,.1,.5)
  var maximum_position:=0.0;var maximum_velocity:=0.0;var maximum_length:=0.0
  for tick in 480:
   a.advance(1.0/480);b.advance(1.0/480)
   for i in a.solver.points.size():
    maximum_position=maxf(maximum_position,a.solver.points[i].distance_to(b.solver.points[i]))
    maximum_velocity=maxf(maximum_velocity,a.solver.velocities[i].distance_to(b.solver.velocities[i]))
   for i in a.solver.links.size():maximum_length=maxf(maximum_length,absf(a.solver.links[i].length-b.solver.links[i].length))
  var exact: bool=maximum_position==0 and maximum_velocity==0 and maximum_length==0 and a.solver.plastic_work==b.solver.plastic_work
  passed=passed and exact
  runs.append({'driving':spec[0],'speed_kmh':spec[1],'exact':exact,'max_position_error_m':maximum_position,'max_velocity_error_mps':maximum_velocity,'max_plastic_length_error_m':maximum_length})
 FileAccess.open('res://verification/static_contact_compatibility.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'baseline':'2ad1656','scope':'Default null-provider state at every integration step; 60/120 frontal live and throttle/brake/steering compact run. No source-hash waiver is granted by this diagnostic.','runs':runs},'\t'))
 print('STATIC_CONTACT_NULL_COMPATIBLE ',passed)
 quit(0 if passed else 1)
