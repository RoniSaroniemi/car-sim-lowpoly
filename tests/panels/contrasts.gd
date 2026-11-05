extends SceneTree
const Vehicle=preload('res://scripts/driving_vehicle.gd')
const Angular=preload('res://scripts/panel_angular_mount.gd')
const Attachment=preload('res://scripts/car_attachment.gd')
var states: Dictionary={}
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 for speed_ in [6.,12.,24.]:
  var v:=Vehicle.new();v.setup('res://vehicles/niva.json',false);v.baked_enabled=false;v.reset(0,Vector3.ZERO);v.solver.barrier_enabled=false;v.solver.config.enforce_symmetry=false;v.set_simulation_quality(2)
  var system: RefCounted=v.solver.panels
  system.obstacle={'center':Vector3(-.1,1.1,-2.3),'size':Vector3(.95,1.4,.14),'velocity':Vector3(0,0,speed_),'travel_axis':2,'stop':.05,'retracting':false,'hold_at_stop':true}
  for i in 960:
   v.step(1.0/960)
   if system.obstacle.center.z<.05:system.obstacle.center.z+=speed_/960
   else:system.obstacle.velocity=Vector3.ZERO
   var current: Dictionary=system.find('door_right')
   if speed_<24 and current.anchors[2].broken and current.closing_supports.all(func(seat):return seat.broken) and int(current.anchors[0].broken)+int(current.anchors[1].broken)==(0 if speed_==6 else 1):break
  system.obstacle={}
  for i in 192:v.step(1.0/960)
  var p: Dictionary=system.find('door_right')
  print('MAIN_PANEL_SIDE ',speed_,' hinges=',p.anchors.map(func(a):return a.broken),' detached=',p.detached,' intrusion=',p.impact_evidence.max_inward_m)
  assert(system.panels.filter(func(part):return part.id!='door_right').all(func(part):return part.anchors.all(func(a):return not a.broken)))
  if speed_==24:assert(p.detached)
  elif speed_==12:assert(not p.detached and p.anchors[0].broken and not p.anchors[1].broken)
  else:assert(not p.detached and p.anchors[2].broken and not p.anchors[0].broken and not p.anchors[1].broken)
  v.prepare_lightweight_panels();states[str(int(speed_))]=v.solver.capture()
  FileAccess.open('user://main_panel_side_'+str(int(speed_))+'.state',FileAccess.WRITE).store_var(v.solver.capture())
 for kind in ['closed','free','single']:
  var v:=Vehicle.new();v.setup();v.solver.barrier_enabled=false
  if kind!='closed':v.solver.restore(states['6' if kind=='free' else '12']);v.prepare_lightweight_panels();v.mode='DRIVE';v.solver.compact_active=true
  var costs: Array=[];var p: Dictionary=v.panel_state('door_right');var flags: Array=p.anchors.map(func(a):return a.broken)
  var initial_plastic: float=p.angular_mount.plastic_rad;var max_tilt:=0.
  for i in 600:
   v.set_controls(1 if i<180 else 0,1 if i>=180 and i<360 else 0,.5*sin(i*.02))
   var began: int=Time.get_ticks_usec();v.step(1.0/120);costs.append(Time.get_ticks_usec()-began)
   if kind=='single':max_tilt=maxf(max_tilt,Angular.error_vector(Angular.axis_from_points(p),Angular.target(v.solver,p,Attachment.rotations(v.solver))).length())
  costs.sort();var total:=0.
  for cost in costs:total+=cost
  print('MAIN_PANEL_BUDGET ',kind,' mean/p95/p99 us ',total/costs.size(),'/',costs[int(costs.size()*.95)],'/',costs[int(costs.size()*.99)],' tilt=',rad_to_deg(max_tilt))
  assert(v.full_steps==0 and v.solver.panels.active_steps==0 and absf(v.solver.owned_mass_kg()-1210)<.001)
  assert(flags==p.anchors.map(func(a):return a.broken))
  if kind=='single':assert(max_tilt<deg_to_rad(16) and p.angular_mount.plastic_rad-initial_plastic<deg_to_rad(4))
 print('MAIN_PANEL_CONTRASTS_PASS')
 quit()
