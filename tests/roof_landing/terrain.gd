extends SceneTree
const Driving=preload('res://scripts/driving_vehicle.gd')
const Arena=preload('res://arena/vehicle.gd')
const Terrain=preload('res://arena/terrain.gd')
const Cases=preload('res://scripts/roof_landing_cases.gd')
const Geometry=preload('res://scripts/roof_landing_geometry.gd')
const Ground=preload('res://scripts/ground_impact_geometry.gd')
var checks: Dictionary={}
var runs: Array=[]
class GroundPlane:
 extends RefCounted
 var grade:=.4
 var yaw:=0.0
 func sample(p: Vector3) -> Vector4:
  var n:=Vector3(-grade*cos(yaw),1,grade*sin(yaw)).normalized()
  return Vector4(n.x,n.y,n.z,grade*(p.x*cos(yaw)-p.z*sin(yaw)))
func _initialize() -> void:call_deferred('_run')
func _place(car: RefCounted,roll: float,normal: Vector3,down: float,stationary: bool) -> void:
 var spec: Dictionary={'roll_deg':roll,'forward_kmh':0. if stationary else 60.,'down_mps':down,'roll_rate':0.}
 Cases.place(car,spec,0,Vector3.ZERO)
 var axis: Vector3=Vector3.UP.cross(normal)
 var rotation:=Basis(axis.normalized(),acos(clampf(Vector3.UP.dot(normal),-1,1))) if axis.length()>.0001 else Basis.IDENTITY
 for i in car.solver.points.size():car.solver.points[i]=rotation*car.solver.points[i]
 for w in car.solver.wheels.wheels:w.rotation=(rotation.get_rotation_quaternion()*w.rotation).normalized();w.previous_rotation=w.rotation
 car.solver.panels.synchronize_inactive()
 var low:=INF
 for p in Geometry.probes(car.solver):low=minf(low,Ground.gap(car.solver,p.position,p.radius).distance)
 var shift: Vector3=normal*((0 if stationary else .06)-low)
 var tangent: Vector3=rotation*Vector3.RIGHT
 for i in car.solver.points.size():car.solver.points[i]+=shift;car.solver.velocities[i]=(Vector3.ZERO if stationary else tangent*20.0-normal*down)
 car.solver.panels.synchronize_inactive();car.solver.effects.synchronize();car.compact.capture_shape()
 car.mode='DRIVE';car.solver.compact_active=true
func _case(roll: float,grade: float,yaw: float,down: float,stationary: bool) -> void:
 var car:=Driving.new();car.setup();car.solver.barrier_enabled=false
 var plane:=GroundPlane.new();plane.grade=grade;plane.yaw=yaw;car.solver.terrain=plane
 var s: Vector4=plane.sample(Vector3.ZERO);var normal:=Vector3(s.x,s.y,s.z)
 _place(car,roll,normal,down,stationary)
 var lower: float=car.solver.points[10].distance_to(car.solver.points[8]);var minimum:=lower
 var gap:=INF
 for tick in 420:
  car.advance(1./120)
  minimum=minf(minimum,car.solver.points[10].distance_to(car.solver.points[8]))
  if car.mode=='BAKED':
   for p in Geometry.probes(car.solver):
    if p.source!='wheel':gap=minf(gap,Ground.gap(car.solver,p.position,p.radius).distance)
 var key: String='roll%d_grade%.2f_yaw%.2f_static%s'%[roundi(roll),grade,yaw,str(stationary)]
 checks[key+'_triggered']=car.baked_count==1 and car.last_bake.get('completed',false)
 checks[key+'_roof_buckled']=minimum<lower-.10
 checks[key+'_no_live_solve']=car.full_steps==0 and car.solver.step_count==0 and car.solver.panels.active_steps==0 and car.solver.effects.glass.membrane_solve_steps==0
 checks[key+'_no_floor_penetration']=gap>-.015
 checks[key+'_mass_and_finite']=absf(car.solver.owned_mass_kg()-1210)<.001 and Array(car.solver.points).all(func(p):return p.is_finite())
 checks[key+'_continuous']=car.last_bake.get('handoff_position_jump_m',INF)<.00001 and car.last_bake.get('handoff_velocity_jump_mps',INF)<.0001
 runs.append({'case':key,'bake':car.last_bake,'roof_height_loss_m':lower-minimum,'minimum_gap_m':gap,'incoming_forward_mps':0 if stationary else 20.0})
 print('TERRAIN_ROOF ',key,' clip=',car.last_bake.get('id','NONE'),' crush=',lower-minimum,' gap=',gap)
func _ramp() -> void:
 var car:=Arena.new();car.setup();car.solver.terrain=Terrain.new();car.solver.barrier_enabled=false
 # Actual 42-degree ramp surface, roof contact; no planar test wall enabled.
 var location:=Vector3(-6,0,-52)
 var floor_: Vector4=car.solver.floor_sample(location);var normal:=Vector3(floor_.x,floor_.y,floor_.z).normalized()
 _place(car,-40,normal,1.0,false)
 var current: Vector4=car.solver.floor_sample(car.solver.station_center(2))
 var shift:=location+Vector3.UP*(floor_.w-current.w)
 for i in car.solver.points.size():car.solver.points[i]+=shift
 # Put the closest physical probe at the actual ramp height after translation.
 car.solver.panels.synchronize_inactive();var low:=INF
 for p in Geometry.probes(car.solver):low=minf(low,Ground.gap(car.solver,p.position,p.radius).distance)
 for i in car.solver.points.size():car.solver.points[i]+=normal*(.03-low)
 car.solver.panels.synchronize_inactive();car.solver.effects.synchronize();car.compact.capture_shape()
 for tick in 420:car.advance(1./120)
 checks.actual_arena_ramp_triggers=car.baked_count==1 and car.last_bake.get('completed',false) and car.full_steps==0
 runs.append({'case':'actual_42_degree_ramp','bake':car.last_bake,'rejection':car.roof_landing_sensor.last_rejection})
func _run() -> void:
 for roll in [0.,-60.,60.]:
  _case(roll,0,0,0,true)
  _case(roll,.4,.6,1.0,false)
 _case(0,.7,-.8,1.0,false)
 _ramp()
 var passed: bool=checks.values().all(func(v):return v)
 FileAccess.open('res://verification/roof_response/terrain.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':runs},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('ROOF_TERRAIN_VERIFIED ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
