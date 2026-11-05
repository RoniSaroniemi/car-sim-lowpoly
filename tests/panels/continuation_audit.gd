extends SceneTree
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Terrain=preload('res://scripts/practice_terrain.gd')
func make(adaptive: bool) -> RefCounted:
 var v:=Vehicle.new();v.setup('res://vehicles/niva.json',true);v.adaptive_enabled=adaptive;v.solver.terrain=Terrain.new();v.solver.barrier_min=Vector3(0,0,-8);v.solver.barrier_max=Vector3(1,3,8);v.reset(80,Vector3(-90,0,0));return v
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var source: RefCounted=make(true)
 while source.mode!='FULL':source.advance(1.0/120)
 var snapshot: Dictionary=source.solver.capture();var overload: Array=source.solver.links.map(func(l):return l.overload_time)
 var a: RefCounted=make(false);var b: RefCounted=make(true);b.wake('matched_state')
 for v in [a,b]:
  v.solver.restore(snapshot)
  for k in overload.size():v.solver.links[k].overload_time=overload[k]
 var first:=-1;var full_error:=0.;var final_error:=0.
 for i in 120:
  var same: bool=a.mode==b.mode
  a.advance(1.0/120);b.advance(1.0/120)
  var error:=0.
  for k in a.solver.points.size():error=maxf(error,a.solver.points[k].distance_to(b.solver.points[k]))
  if same and a.mode==b.mode:full_error=maxf(full_error,error)
  if error>.00001 and first<0:first=i;print('CONTINUATION_FIRST ',i,' error=',error,' a=',a.mode,' b=',b.mode,' transitions=',b.transitions)
  final_error=error
 print('CONTINUATION_AUDIT full_error=',full_error,' final=',final_error,' first=',first,' work=',a.solver.plastic_work,'/',b.solver.plastic_work)
 assert(full_error<.00001 and final_error<.00001 and absf(a.solver.plastic_work-b.solver.plastic_work)<.01)
 quit()
