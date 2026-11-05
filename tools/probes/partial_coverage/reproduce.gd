extends SceneTree
const Driving=preload('res://scripts/driving_vehicle.gd')
const Arena=preload('res://arena/vehicle.gd')
const Terrain=preload('res://arena/terrain.gd')
const Coverage=preload('res://scripts/baked_contact_coverage.gd')
var runs: Array=[]
func _initialize() -> void:
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification/partial_coverage'))
 call_deferred('_run')
func stage(car: RefCounted,angle: float,overlap: float,side: String,speed: float=60) -> void:
 car.reset(speed,Vector3(28,0,0))
 var basis:=Basis(Vector3.UP,deg_to_rad(angle))
 var low:=INF;var high:=-INF
 for i in car.solver.points.size():
  car.solver.points[i]=basis*car.solver.rest[i]+Vector3(28,0,0)
  low=minf(low,car.solver.points[i].z-car.solver.radii[i]);high=maxf(high,car.solver.points[i].z+car.solver.radii[i])
 if overlap<1:
  var shift: float=car.solver.barrier_min.z-(high-overlap*(high-low)) if side=='left' else car.solver.barrier_max.z-(low+overlap*(high-low))
  for i in car.solver.points.size():car.solver.points[i].z+=shift
 for wheel in car.solver.wheels.wheels:
  wheel.rotation=basis.get_rotation_quaternion();wheel.previous_rotation=wheel.rotation
  wheel.spin_speed=-speed/3.6*cos(deg_to_rad(angle))/wheel.radius
 car.compact.capture_shape()
func one(kind: String,angle: float,overlap: float,side: String) -> void:
 var car: RefCounted=Arena.new() if kind=='arena' else Driving.new()
 car.setup();car.solver.terrain=Terrain.new() if kind=='arena' else null
 car.solver.barrier_min=Vector3(40,0,-8);car.solver.barrier_max=Vector3(41,3,8)
 stage(car,angle,overlap,side)
 var trace: Dictionary={}
 var touched:=false;var first_touch:=-1.0
 for step in 180:
  var packet: Dictionary=car.contact_sensor.event(car.solver,car.velocity(),1.0/120)
  if not packet.is_empty() and trace.is_empty():
   var signature: Dictionary=packet.signature
   var coverage: Dictionary=Coverage.describe(car.solver,packet,signature)
   trace={'toi':packet.toi,'armed':packet.armed,'bounds_min':packet.bounds_min,'bounds_max':packet.bounds_max,'primary':signature,'fallback':packet.fallback_signatures,'coverage':coverage,'proxy':car.solver.static_contact(car.solver.station_center(2),3.5).get('source','none')}
  car.advance(1.0/120)
  if car.baked_count>0:break
  if car.solver.contact_wall.has(1):
   if first_touch<0:first_touch=car.solver.simulated_time
   touched=true
  if touched and car.solver.simulated_time>first_touch+.1:break
 var id: String='%s_%d_%s_%d'%[kind,roundi(angle),side,roundi(overlap*100)]
 var row: Dictionary={'id':id,'kind':kind,'angle':angle,'overlap_requested':overlap,'side':side,'baked':car.baked_count,'clip':car.last_bake.get('id',''),'physical_contact':touched,'rejection':car.contact_sensor.last_rejection,'trace':trace,'full_steps':car.solver.step_count,'legacy_forecasts':car.forecast.checks}
 runs.append(row);print('PARTIAL_REPRO ',id,' played=',row.baked,' reject=',row.rejection)
func _run() -> void:
 for kind in ['driving','arena']:
  for angle in [0.,10.,-10.,20.,-20.,30.,-30.]:one(kind,angle,1,'none')
  for angle in [0.,30.,-30.]:
   for side in ['left','right']:
    for overlap in [.25,.5,.75]:one(kind,angle,overlap,side)
 var passed: bool=runs.size()==50 and runs.all(func(row):return row.full_steps==0 and row.legacy_forecasts==0)
 FileAccess.open('res://verification/partial_coverage/baseline.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'runs':runs},'\t'))
 print('PARTIAL_REPRO_COMPLETED ',passed,' cases=',runs.size())
 quit(0 if passed else 1)
