extends SceneTree
const Driving=preload('res://scripts/driving_vehicle.gd')
const Cases=preload('res://scripts/roof_landing_cases.gd')
const Geometry=preload('res://scripts/roof_landing_geometry.gd')
const Response=preload('res://scripts/roof_landing_response.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
var checks: Dictionary={}
var runs: Array=[]
func _initialize() -> void:call_deferred('_run')
func height(f: Dictionary) -> float:return (f.points[10].distance_to(f.points[8])+f.points[11].distance_to(f.points[9]))*.5
func _source_checks(car: RefCounted) -> void:
 for spec in Cases.specifications():
  var raw: Dictionary=Clip.read(Cases.DIRECTORY+'/'+spec.id+'.crashclip')
  var before: int=hash(var_to_bytes(raw.frames))
  var derived: Dictionary=Response.prepare(car.solver,raw)
  checks[spec.id+'_source_immutable']=before==hash(var_to_bytes(raw.frames))
  var raw_loss: float=height(raw.frames[0])-height(raw.frames[-1])
  var new_loss: float=height(derived.frames[0])-height(derived.frames[-1])
  checks[spec.id+'_stronger_roof']=new_loss>raw_loss+.10
  var gap_error:=0.0
  for i in derived.frames.size():gap_error=maxf(gap_error,absf(Response._minimum(car.solver,derived.frames[i])-Response._minimum(car.solver,raw.frames[i])))
  checks[spec.id+'_floor_clearance_preserved']=gap_error<.0001
  var reference: float=(derived.frames[0].velocities[8].x+derived.frames[0].velocities[9].x+derived.frames[0].velocities[10].x+derived.frames[0].velocities[11].x)*.25
  var same: Dictionary=Response.view(derived,1,Vector3(-reference,0,0))
  var v: Vector3=(same.frames[120].velocities[8]+same.frames[120].velocities[9]+same.frames[120].velocities[10]+same.frames[120].velocities[11])*.25
  checks[spec.id+'_stationary_not_accelerated']=absf(v.x)<.002
func _landing(roll: float,pitch: float,forward: float,down: float) -> void:
 var car:=Driving.new();car.setup();car.solver.barrier_enabled=false
 var spec: Dictionary={'roll_deg':roll,'forward_kmh':forward,'down_mps':down,'roll_rate':0.0}
 Cases.place(car,spec,0)
 if pitch!=0:
  var rotation:=Basis(Vector3.BACK,deg_to_rad(pitch));var center: Vector3=car.solver.station_center(2)
  for i in car.solver.points.size():car.solver.points[i]=center+rotation*(car.solver.points[i]-center)
  for w in car.solver.wheels.wheels:w.rotation=(rotation.get_rotation_quaternion()*w.rotation).normalized();w.previous_rotation=w.rotation
  car.solver.panels.synchronize_inactive()
 var shift: float=.02-Geometry.minimum_gap(car.solver)
 for i in car.solver.points.size():car.solver.points[i].y+=shift;car.solver.velocities[i]=Vector3(forward/3.6,-down,0)
 car.solver.panels.synchronize_inactive();car.solver.effects.synchronize();car.compact.capture_shape()
 car.mode='DRIVE';car.solver.compact_active=true
 var preparations_before: int=Response.preparations
 var minimum:=INF;var body_minimum:=INF;var tire_overcompression:=0.0;var maximum_speed:=0.0;var entry_forward:=0.0;var saw_entry:=false
 for tick in 420:
  car.advance(1.0/120)
  if car.mode=='BAKED':
   minimum=minf(minimum,Geometry.minimum_gap(car.solver))
   for probe in Geometry.probes(car.solver):
    var gap: float=probe.position.y-probe.radius-car.solver.floor_sample(probe.position).w
    if probe.source=='wheel':
     var wheel: Variant=car.solver.wheels.wheels[car.solver.wheels.by_node[probe.node]]
     tire_overcompression=maxf(tire_overcompression,-gap-float(wheel.max_compression))
    else:body_minimum=minf(body_minimum,gap)
   if not saw_entry:
    entry_forward=car.velocity().x;saw_entry=true
   for v in car.solver.velocities:maximum_speed=maxf(maximum_speed,v.length())
 var key: String='roll%d_pitch%d_forward%d_down%.1f'%[roundi(roll),roundi(pitch),roundi(forward),down]
 checks[key+'_triggers']=car.baked_count==1 and car.last_bake.get('completed',false)
 checks[key+'_no_live_solves']=car.full_steps==0 and car.solver.step_count==0 and car.solver.panels.active_steps==0 and car.solver.effects.glass.membrane_solve_steps==0 and car.solver.effects.interior.cloth_steps==0
 checks[key+'_floor_safe']=body_minimum>-.012 and tire_overcompression<.012
 checks[key+'_finite_velocity']=maximum_speed<100 and Array(car.solver.points).all(func(p):return p.is_finite())
 checks[key+'_continuous_entry']=car.last_bake.get('handoff_position_jump_m',INF)<.00001 and car.last_bake.get('handoff_velocity_jump_mps',INF)<.0001
 checks[key+'_forward_preserved']=absf(entry_forward-forward/3.6)<1.5
 checks[key+'_no_contact_time_prepare']=Response.preparations==preparations_before
 runs.append({'case':key,'last_bake':car.last_bake,'minimum_gap_m':minimum,'body_minimum_gap_m':body_minimum,'tire_overcompression_m':tire_overcompression,'maximum_velocity_mps':maximum_speed,'entry_forward_mps':entry_forward})
 print('EASY_ROOF ',key,' selected=',car.last_bake.get('id','NONE'),' gap=',minimum,' body_gap=',body_minimum,' tire_overcompression=',tire_overcompression,' vmax=',maximum_speed)
func _run() -> void:
 var car:=Driving.new();car.setup();_source_checks(car)
 for speed in [0.,30.,100.,160.]:_landing(0,0,speed,.8)
 for roll in [-55.,-40.,40.,55.]:_landing(roll,0,60.,1.2)
 for pitch in [-35.,35.,-55.,55.]:_landing(0,pitch,60.,1.2)
 var passed: bool=checks.values().all(func(v):return v)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification/roof_response'))
 FileAccess.open('res://verification/roof_response/response.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':runs,'crumple_gain':Response.GAIN,'activation_mps':.5,'mode':'art-directed derived baked playback; not a new physical simulation'},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('EASY_ROOF_VERIFIED ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
