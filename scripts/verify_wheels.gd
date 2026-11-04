extends SceneTree
const Solver=preload('res://scripts/structure_solver.gd')
var checks: Dictionary={}
func _initialize() -> void:
 call_deferred('_run')

func _run() -> void:
 _targeted_checks()
 if '--targeted-only' in OS.get_cmdline_user_args():
  print('WHEEL_TARGETED ',JSON.stringify(checks))
  quit(0 if checks.values().all(func(c):return c) else 1)
  return
 var results: Array=[]
 var end_states: Array=[]
 var permanent_states: Array=[]
 for test in [{'speed':20,'mode':0},{'speed':50,'mode':0},{'speed':80,'mode':0},{'speed':120,'mode':0},{'speed':80,'mode':1},{'speed':120,'mode':1},{'speed':120,'mode':1,'body_contact':false}]:
  var s=Solver.new()
  s.setup()
  s.set_impact_mode(test.mode)
  s.wheels.body_contact_enabled=test.get('body_contact',true)
  s.reset(test.speed)
  var dt: float=s.config.fixed_step_s
  for i in 1440:s.step(dt)
  var m: Dictionary=s.metrics()
  m['speed_kmh']=test.speed
  m['body_contact_enabled']=s.wheels.body_contact_enabled
  var finite:=true
  var floor_gap:=100.0
  var barrier_gap:=100.0
  for i in s.points.size():
   finite=finite and s.points[i].is_finite() and s.velocities[i].is_finite()
   var hit: Dictionary=s.barrier_distance(s.points[i])
   if s.config.nodes[i].group!='wheel':
    floor_gap=minf(floor_gap,s.points[i].y-s.radii[i])
    barrier_gap=minf(barrier_gap,float(hit.distance)-s.radii[i])
  for w in s.wheels.wheels:
   finite=finite and w.rotation.is_finite() and w.angular_velocity.is_finite() and is_finite(w.spin_speed)
   floor_gap=minf(floor_gap,s.points[w.node].y+s.wheels.support(w,Vector3.DOWN).y+w.max_compression)
   var hit: Dictionary=s.barrier_distance(s.points[w.node])
   barrier_gap=minf(barrier_gap,float(hit.distance)+hit.normal.dot(s.wheels.support(w,-hit.normal))+w.max_compression)
  m['finite']=finite
  m['minimum_floor_clearance_m']=floor_gap
  m['minimum_barrier_clearance_m']=barrier_gap
  m['mass_accounted_once']=absf(float(m.mass_kg)-1210.0)<.01
  m['no_energy_explosion']=m.maximum_kinetic_kj<=m.initial_energy_kj*1.06+1.0
  m['passed']=finite and floor_gap>-.005 and barrier_gap>-.005 and m.no_energy_explosion and m.mass_accounted_once
  results.append(m)
  end_states.append(s.points.duplicate())
  permanent_states.append(s.links.map(func(l):return l.length))
  print('WHEEL_RESULT ',JSON.stringify(m))
 var difference:=0.0
 for i in end_states[5].size():difference+=end_states[5][i].distance_to(end_states[6][i])
 var rest_difference:=0.0
 for i in permanent_states[5].size():rest_difference+=absf(permanent_states[5][i]-permanent_states[6][i])
 checks['wheel_body_contact_changes_permanent_deformation']=rest_difference>.001
 checks['contact_ablation_permanent_rest_difference_m']=rest_difference
 checks['wheel_body_contact_changes_deformation']=difference>.01
 checks['contact_ablation_sum_node_displacement_m']=difference
 checks['severe_impact_generates_body_contact']=results[5].wheels.any(func(w):return w.body_contact_events>0)
 checks['severe_impact_breaks_suspension']=results[5].broken_suspension_links>0
 checks['low_speed_does_not_eject_wheels']=results[0].broken_suspension_links==0 and not results[0].wheels.any(func(w):return w.detached)
 checks['cabin_damage_escalates']=results[3].cabin_shortening_m>results[1].cabin_shortening_m
 var passed: bool=results.all(func(r):return r.passed)
 for key in checks:
  if checks[key] is bool:passed=passed and checks[key]
 var report: Dictionary={'runs':results,'checks':checks,'passed':passed,'scope':'Controlled box/floor bench, rigid wheel/hub approximation; no calibrated tire FEM or general game-world collision.'}
 FileAccess.open('res://verification/wheel_validation.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
 print('WHEEL_VERIFICATION_COMPLETE ',passed,' ',JSON.stringify(checks))
 quit(0 if passed else 1)

func _targeted_checks() -> void:
 var s=Solver.new()
 s.setup()
 s.reset(0)
 var dt: float=s.config.fixed_step_s
 for i in 960:s.step(dt)
 var stable:=true
 for w in s.wheels.metrics():stable=stable and w.hub_tilt_deg<3 and w.permanent_alignment_deg<.1 and not w.detached
 checks['standing_hubs_remain_upright']=stable
 checks['standing_suspension_does_not_break']=s.links.all(func(l):return not l.broken)
 checks['standing_floor_keeps_body_supported']=s.points[16].y>.48
 # Direct narrow-phase response must push both wheel and body, conserving COM.
 s.reset(0)
 var wheel=s.wheels.wheels[3]
 s.points[wheel.node]=s.points[13]+Vector3(.15,.05,.095)
 var before: Vector3=s.center_of_mass()
 s.wheels._body_contact(3,1,dt)
 checks['internal_contact_has_equal_opposite_linear_response']=before.distance_to(s.center_of_mass())<.00001 and wheel.contact_events>0
 # Individual force/time thresholds remove links without position/velocity kicks.
 s.reset(0)
 var pristine: Dictionary=s.capture()
 var node: int=wheel.node
 s.velocities[node]=Vector3(15,0,0)
 var position: Vector3=s.points[node]
 var velocity: Vector3=s.velocities[node]
 for l in wheel.links:
  l.peak_force=l.break_force*2
  l.overload_time=l.break_delay
 s._break_links(dt)
 checks['detachment_keeps_position_and_velocity']=s.points[node]==position and s.velocities[node]==velocity and wheel.links.all(func(l):return l.broken) and wheel.joint_broken
 s.points[node]=Vector3(-.8,.5,.8)
 s.wheels.body_contact_enabled=false
 var touched:=false
 for i in 240:
  s.step(dt)
  touched=touched or bool(s.contact_wall[node])
 checks['detached_wheel_continues_colliding']=wheel.detached and touched and s.points[node].is_finite()
 var detached_state: Dictionary=s.capture()
 s.restore(pristine)
 checks['replay_restores_wheel_and_links']=not wheel.detached and wheel.links.all(func(l):return not l.broken) and wheel.rotation==Quaternion.IDENTITY
 s.restore(detached_state)
 checks['replay_restores_detachment']=wheel.detached and wheel.links.all(func(l):return l.broken)
 s.reset(0)
 checks['reset_clears_wheel_damage']=wheel.rotation==Quaternion.IDENTITY and wheel.alignment==Vector3.BACK and wheel.links.all(func(l):return not l.broken and l.damage==0)
