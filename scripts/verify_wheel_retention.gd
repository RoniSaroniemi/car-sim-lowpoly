extends SceneTree
## Focused suspension retention regressions; includes live practice terrain.
const Solver=preload('res://scripts/structure_solver.gd')
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Terrain=preload('res://scripts/practice_terrain.gd')
var runs: Array=[]
func _initialize() -> void:call_deferred('_run')
func inspect(s: RefCounted,record: Dictionary) -> void:
 for i in s.wheels.wheels.size():
  var w=s.wheels.wheels[i]
  var r: Dictionary=record.wheels[i]
  r.peak_torque_nm=maxf(r.peak_torque_nm,w.joint_peak)
  r.peak_lateral_n=maxf(r.peak_lateral_n,w.lateral_peak)
  r.peak_alignment_deg=maxf(r.peak_alignment_deg,rad_to_deg(acos(clampf(w.alignment.dot(Vector3.BACK),-1,1))))
  for l in w.links:r.peak_link_force_n=maxf(r.peak_link_force_n,l.peak_force)
  if w.detached and r.release_s<0:
   r.release_s=s.simulated_time
   r.release_reason=w.detach_reason
func record_for(s: RefCounted,name: String) -> Dictionary:
 var r: Dictionary={'case':name,'wheels':[]}
 for w in s.wheels.wheels:
  r.wheels.append({'name':s.config.nodes[w.node].name,'peak_torque_nm':0.0,'peak_lateral_n':0.0,'peak_link_force_n':0.0,'peak_alignment_deg':0.0,'release_s':-1.0,'release_reason':''})
 return r
func finish(s: RefCounted,r: Dictionary) -> void:
 r['broken_supports']=s.links.filter(func(l):return l.broken).size()
 r['rear_released']=s.wheels.wheels.slice(0,2).filter(func(w):return w.detached).size()
 r['front_released']=s.wheels.wheels.slice(2,4).filter(func(w):return w.detached).size()
 r['final_body_x_m']=s.station_center(2).x
 r['finite']=true
 for p in s.points:r.finite=r.finite and p.is_finite()
 for w in s.wheels.wheels:r.finite=r.finite and w.rotation.is_finite() and w.angular_velocity.is_finite() and is_finite(w.spin_speed)
 runs.append(r)
 print('RETENTION_CASE ',JSON.stringify(r))
func crash(speed: float,offset: bool=false) -> void:
 var s=Solver.new()
 s.setup()
 s.set_impact_mode(1 if offset else 0)
 s.reset(speed)
 var r: Dictionary=record_for(s,('offset_' if offset else 'head_on_')+str(speed))
 for i in 1440:
  s.step(s.config.fixed_step_s)
  inspect(s,r)
 finish(s,r)
func driving_crash(speed: float) -> void:
 var v=Vehicle.new()
 v.setup('res://vehicles/niva.json',true)
 v.solver.barrier_min=Vector3(0,0,-8)
 v.solver.barrier_max=Vector3(1,3,8)
 v.reset(speed,Vector3(-45,0,0))
 var r: Dictionary=record_for(v.solver,'head_on_driving_'+str(speed))
 for i in 840:
  v.advance(1.0/120.0)
  inspect(v.solver,r)
 finish(v.solver,r)
func ramp(index: int) -> void:
 var v=Vehicle.new()
 v.setup('res://vehicles/niva.json',true)
 v.solver.terrain=Terrain.new()
 v.solver.barrier_enabled=false
 var hill: Dictionary=v.solver.terrain.ramps[index]
 v.reset(60,Vector3(float(hill.start)-12,0,float(hill.z)))
 var r: Dictionary=record_for(v.solver,'ramp_'+str(index))
 var airborne:=false
 var landed:=false
 var maximum_clearance:=0.0
 for i in 600:
  v.advance(1.0/120.0)
  inspect(v.solver,r)
  var lowest:=100.0
  for w in v.solver.wheels.wheels:
   var p: Vector3=v.solver.points[w.node]
   var surface: Vector4=v.solver.floor_sample(p)
   lowest=minf(lowest,p.y+v.solver.wheels.support(w,Vector3.DOWN).y-surface.w)
  maximum_clearance=maxf(maximum_clearance,lowest)
  if lowest>.05:airborne=true
  if airborne and lowest<.01:landed=true
 r['airborne']=airborne
 r['landed']=landed
 r['maximum_clearance_m']=maximum_clearance
 r['full_steps']=v.full_steps
 finish(v.solver,r)
func _run() -> void:
 var args: PackedStringArray=OS.get_cmdline_user_args()
 if args.is_empty() or 'crash' in args:
  crash(80)
  crash(120)
 if args.is_empty() or 'offset' in args:
  crash(80,true)
  crash(120,true)
 if args.is_empty() or 'driving' in args:
  driving_crash(80)
  driving_crash(120)
 if args.is_empty() or 'ramp' in args:
  ramp(0)
  ramp(1)
 var checks: Dictionary={}
 for r in runs:
  checks[r.case+'_finite']=r.finite
  if r.case.begins_with('head_on') or r.case.begins_with('offset'):
   checks[r.case+'_rear_mounts_retained']=r.rear_released==0
   if r.case=='offset_120.0':
    # niva_multiaxis_v1 absorbs more impact in the cabin than the original
    # front-bench cage. A120 km/h offset now damages/bends the mount without
    # requiring full wheel release. Detachment capability remains covered by
    # verify_wheel_mounts.gd's explicit force/torque overload checks.
    checks['severe_offset_creates_support_damage']=r.broken_supports>0
    checks['severe_offset_leaves_permanent_front_bend']=r.wheels.slice(2,4).any(func(w):return w.peak_alignment_deg>10.0)
  else:
   checks[r.case+'_flight_and_landing']=r.airborne and r.landed
   checks[r.case+'_all_supports_retained']=r.broken_supports==0 and r.front_released==0 and r.rear_released==0
   checks[r.case+'_no_permanent_alignment']=r.wheels.all(func(w):return w.peak_alignment_deg<.1)
 var passed: bool=not runs.is_empty() and checks.values().all(func(c):return c)
 FileAccess.open('res://verification/wheel_retention_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':runs,'material_baseline_note':'The promoted cabin absorbs more energy; offset120 must damage/bend supports but need not eject the front wheel. Rear/ramp retention remains mandatory.','release_capability_suite':'res://scripts/verify_wheel_mounts.gd'},'\t'))
 print('WHEEL_RETENTION_VERIFICATION_COMPLETE ',passed,' ',JSON.stringify(checks))
 quit(0 if passed else 1)
