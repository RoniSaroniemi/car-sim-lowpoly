extends SceneTree
const Driving=preload('res://scripts/driving_vehicle.gd')
const Arena=preload('res://arena/vehicle.gd')
const Terrain=preload('res://arena/terrain.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Staging=preload('res://scripts/partial_wall_staging.gd')
const Partial=preload('res://scripts/partial_crash_library.gd')
var runs: Array=[]
func _initialize() -> void:call_deferred('_run')
func one(kind: String,angle: float,overlap: float,side: String,speed: float=60) -> void:
 var car: RefCounted=Arena.new() if kind=='arena' else Driving.new()
 car.setup();car.solver.terrain=Terrain.new() if kind=='arena' else null
 car.solver.barrier_min=Vector3(40,0,-8);car.solver.barrier_max=Vector3(41,3,8)
 Staging.stage(car,speed,angle,overlap,side)
 var identifier: int=car.solver.get_instance_id()
 var last_reject:='';var touched:=false;var touch_time:=-1.0
 for frame in 140:
  car.advance(1.0/120)
  if not car.contact_sensor.last_rejection.is_empty():last_reject=car.contact_sensor.last_rejection
  if car.baked_count>0:break
  if car.solver.contact_wall.has(1):
   touched=true
   if touch_time<0:touch_time=car.solver.simulated_time
  if touch_time>=0 and car.solver.simulated_time>touch_time+.15:break
 var row: Dictionary={'case':'%s_%d_%d_%s_%d'%[kind,speed,angle,side,roundi(overlap*100)],'kind':kind,'angle':angle,'requested_overlap':overlap,'side':side,'speed_kmh':speed,'baked':car.baked_count,'selected':car.last_bake.get('id',''),'last_bake':car.last_bake,'rejection':last_reject,'physical_contact':touched,'heavy_steps':car.solver.step_count,'legacy_forecasts':car.forecast.checks,'same_graph':car.solver.get_instance_id()==identifier,'sensor':car.contact_sensor.statistics()}
 runs.append(row)
 print('PARTIAL_DRIVE ',row.case,' played=',row.baked,' clip=',row.selected,' reject=',last_reject)
func _run() -> void:
 var directory: String=Partial.DIRECTORY
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with('--directory='):directory=argument.trim_prefix('--directory=')
 var bank: Array=Clip.read_library()+Partial.read_library(directory)
 Driving.cached_library=bank
 for kind in ['driving','arena']:
  for speed in [60.0,120.0]:
   for angle in [0.,10.,-10.,20.,-20.,30.,-30.]:
    one(kind,angle,1,'none',speed)
    for side in ['left','right']:
     for overlap in [.25,.50,.75]:one(kind,angle,overlap,side,speed)
 var safe: bool=runs.size()==196 and runs.all(func(row):return row.heavy_steps==0 and row.legacy_forecasts==0 and row.same_graph)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification/partial_coverage'))
 FileAccess.open('res://verification/partial_coverage/driving.json',FileAccess.WRITE).store_string(JSON.stringify({'safe':safe,'all_triggered':runs.all(func(row):return row.baked==1),'runs':runs},'\t'))
 print('PARTIAL_DRIVING_COMPLETE safe=',safe,' played=',runs.filter(func(row):return row.baked==1).size(),'/',runs.size())
 quit(0 if safe and runs.all(func(row):return row.baked==1) else 1)
