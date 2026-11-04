extends SceneTree
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Terrain=preload('res://scripts/practice_terrain.gd')
var checks: Dictionary={}
var runs: Array=[]
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var terrain=Terrain.new()
 for index in terrain.ramps.size():
  var ramp: Dictionary=terrain.ramps[index]
  var mesh: ArrayMesh=terrain.mesh(ramp)
  var arrays: Array=mesh.surface_get_arrays(0)
  var error:=0.0
  for vertex in arrays[Mesh.ARRAY_VERTEX]:error=maxf(error,absf(vertex.y-terrain.sample(vertex).w))
  checks['mesh_matches_contact_'+str(index)]=error<.00001
  var v=Vehicle.new()
  v.setup('res://vehicles/niva.json',true)
  v.solver.terrain=terrain
  v.solver.barrier_enabled=false
  v.reset(60,Vector3(float(ramp.start)-18,0,ramp.z))
  v.set_controls(.1,0,0)
  var longest_air:=0.0
  var current_air:=0.0
  var max_clearance:=0.0
  var landed:=false
  var finite:=true
  for frame in 600:
   v.advance(1.0/120.0)
   var minimum:=INF
   for w in v.solver.wheels.wheels:
    var p: Vector3=v.solver.points[w.node]
    var gap: float=p.y+v.solver.wheels.support(w,Vector3.DOWN).y-terrain.sample(p).w
    minimum=minf(minimum,gap)
    finite=finite and p.is_finite()
   max_clearance=maxf(max_clearance,minimum)
   if minimum>.04:
    current_air+=1.0/120.0
    longest_air=maxf(longest_air,current_air)
   else:
    if current_air>.08:landed=true
    current_air=0
  checks['natural_takeoff_'+str(index)]=longest_air>.08 and max_clearance>.08
  checks['landing_'+str(index)]=landed
  checks['finite_'+str(index)]=finite
  checks['landing_wakes_structure_'+str(index)]=v.transitions.any(func(t):return t.to=='FULL' and t.reason in ['forecast_hard_landing','forecast_body_floor','suspension_load'])
  runs.append({'ramp':ramp.name,'airtime_s':longest_air,'all_wheel_clearance_m':max_clearance,'landed':landed,'finite':finite,'statistics':v.statistics(),'damage':v.solver.metrics()})
 var passed: bool=checks.values().all(func(c):return c)
 FileAccess.open('res://verification/ramp_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':runs},'\t'))
 print('RAMP_VERIFICATION_COMPLETE ',passed,' ',JSON.stringify(checks))
 for r in runs:print('RAMP_RUN ',r.ramp,' air=',r.airtime_s,' gap=',r.all_wheel_clearance_m,' landed=',r.landed)
 quit(0 if passed else 1)
