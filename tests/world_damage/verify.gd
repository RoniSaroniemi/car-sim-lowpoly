extends SceneTree
const Arena=preload('res://arena/vehicle.gd')
const Terrain=preload('res://arena/terrain.gd')
const Pose=preload('res://scripts/roof_landing_geometry.gd')
const Ground=preload('res://scripts/ground_impact_geometry.gd')
const Cases=preload('res://scripts/roof_landing_cases.gd')
const Player=preload('res://scripts/incremental_crash_player.gd')
var checks: Dictionary={}
var runs: Array=[]
func _initialize():call_deferred('_run')
func car() -> RefCounted:
 var c:=Arena.new();c.setup();c.solver.terrain=Terrain.new();c.solver.barrier_enabled=false;return c
func run_until_done(c: RefCounted,max_ticks: int=600) -> void:
 for tick in max_ticks:
  c.advance(1./120)
  if c.baked_count>0 and c.mode!='BAKED' and c.last_bake.get('completed',false):return
func launch_roof(c: RefCounted,location: Vector3=Vector3(-30,0,0),roll: float=0,normal: Vector3=Vector3.UP) -> void:
 var g: RefCounted=c.solver;var old: Transform3D=Player.frame(g.points)
 var forward:=Vector3.RIGHT-normal*normal.dot(Vector3.RIGHT)
 if forward.length()<.1:forward=Vector3.BACK
 forward=forward.normalized()
 var target:=Basis(forward,normal,forward.cross(normal).normalized())*Basis(Vector3.RIGHT,PI+deg_to_rad(roll))
 var rotation: Basis=target*old.basis.transposed()
 for i in g.points.size():g.points[i]=rotation*(g.points[i]-old.origin)+location
 for w in g.wheels.wheels:w.rotation=(rotation.get_rotation_quaternion()*w.rotation).normalized();w.previous_rotation=w.rotation
 if g.panels_runtime_enabled:
  var snapshot: Dictionary=g.panels.capture()
  snapshot=preload('res://scripts/panel_snapshot.gd').transformed(snapshot,rotation,location-rotation*old.origin)
  g.panels.restore(snapshot)
 for iteration in 5:
  g.panels.synchronize_inactive();var low:=INF
  for p in Pose.probes(g):low=minf(low,Ground.gap(g,p.position,p.radius).distance)
  for i in g.points.size():g.points[i]+=normal*(.04-low)
 for i in g.points.size():g.velocities[i]=forward*20-normal*1.5
 g.panels.synchronize_inactive();g.effects.synchronize();c.compact.capture_shape()
 if c.mode!='BAKED':c.mode='DRIVE';g.compact_active=true
func invariant(c: RefCounted,key: String) -> void:
 checks[key+'_no_solver']=c.full_steps==0 and c.solver.step_count==0 and c.solver.panels.active_steps==0 and c.solver.effects.glass.membrane_solve_steps==0 and c.solver.effects.interior.cloth_steps==0
 checks[key+'_mass_finite']=absf(c.solver.owned_mass_kg()-1210)<.001 and Array(c.solver.points).all(func(p):return p.is_finite())
func _ring() -> void:
 for angle in [0.,45.,90.,135.,180.,225.,270.,315.]:
  var c:=car();var heading:=Basis(Vector3.UP,deg_to_rad(angle));var radial: Vector3=heading*Vector3.RIGHT
  c.reset(60,radial*69)
  for i in c.solver.points.size():c.solver.points[i]=heading*c.solver.rest[i]+radial*69;c.solver.velocities[i]=radial*16.6667
  for w in c.solver.wheels.wheels:w.rotation=heading.get_rotation_quaternion();w.previous_rotation=w.rotation
  c.solver.panels.synchronize_inactive();c.solver.effects.synchronize();c.compact.capture_shape()
  run_until_done(c)
  var key: String='ring_'+str(roundi(angle));checks[key+'_hit']=c.baked_count==1 and c.last_bake.get('contact_family','')=='arena_ring' and c.last_bake.get('completed',false)
  checks[key+'_deforms']=c.solver.plastic_work>100
  invariant(c,key);runs.append({'case':key,'last_bake':c.last_bake,'work_j':c.solver.plastic_work})
  print('WORLD_RING ',angle,' count=',c.baked_count,' full=',c.full_steps)
func _ramps() -> void:
 for feature in Terrain.new().features:
  var c:=car();var location:=Vector3(feature.start+feature.length*.25,0,feature.z)
  var s: Vector4=c.solver.floor_sample(location);location.y=s.w
  launch_roof(c,location,-30,Vector3(s.x,s.y,s.z).normalized())
  run_until_done(c)
  var key: String='ramp_'+feature.id;checks[key+'_hit']=c.baked_count==1 and c.last_bake.get('completed',false)
  invariant(c,key);runs.append({'case':key,'last_bake':c.last_bake,'reject':c.roof_landing_sensor.last_rejection})
  print('WORLD_RAMP ',feature.id,' count=',c.baked_count,' full=',c.full_steps)
func _stack() -> void:
 var c:=car();c.reset(60,Vector3(69,0,0));run_until_done(c)
 var graph_id: int=c.solver.get_instance_id();var before: Dictionary=c.solver.capture()
 var front_before: float=c.solver.station_center(6).distance_to(c.solver.station_center(3))
 launch_roof(c);var first_count: int=c.baked_count
 for tick in 600:c.advance(1./120)
 # Stiffer roofs can physically separate and strike again before this window
 # ends. Require the first later roof hit to complete, not exactly one hit.
 var first_roof: Dictionary=c.impact_history[first_count] if c.impact_history.size()>first_count else {}
 checks.wall_then_roof=first_roof.get('contact_family','')=='roof_landing_floor' and first_roof.get('completed',false)
 checks.same_graph_stacked=c.solver.get_instance_id()==graph_id
 checks.prior_work_retained=c.solver.plastic_work>=float(before.plastic_work)
 var no_heal:=true
 for i in c.solver.links.size():no_heal=no_heal and c.solver.links[i].damage+1e-6>=before.link_damage[i] and (not before.broken[i] or c.solver.links[i].broken)
 for id in before.effects.glass.panes:no_heal=no_heal and c.solver.effects.glass.panes[id].stage>=before.effects.glass.panes[id].stage
 checks.prior_damage_and_glass_retained=no_heal
 checks.front_crush_geometry_retained=c.solver.station_center(6).distance_to(c.solver.station_center(3))<=front_before+.05
 var count_after_roof: int=c.baked_count
 for tick in 240:c.advance(1./120)
 checks.sustained_contact_not_repeated=c.baked_count==count_after_roof
 # Lift physically clear of the ground, then make a new incoming contact.
 for i in c.solver.points.size():c.solver.points[i].y+=3;c.solver.velocities[i]=Vector3(0,-1,0)
 c.solver.panels.synchronize_inactive();c.compact.capture_shape()
 for tick in 24:c.advance(1./120)
 launch_roof(c)
 for tick in 600:c.advance(1./120)
 checks.separation_allows_new_landing=c.baked_count>count_after_roof
 invariant(c,'stacked')
 runs.append({'case':'wall_roof_next_landing','last_bake':c.last_bake,'history':c.impact_history,'impacts':c.baked_count,'before_front_span_m':front_before,'after_front_span_m':c.solver.station_center(6).distance_to(c.solver.station_center(3))})
 print('WORLD_STACK impacts=',c.baked_count,' no_healing=',no_heal)
func _during() -> void:
 var c:=car();c.reset(60,Vector3(69,0,0))
 for tick in 100:
  c.advance(1./120)
  if c.mode=='BAKED' and c.crash_player.time>.2:break
 checks.first_hit_is_incremental=c.crash_player is Player
 var front_before: float=c.solver.station_center(6).distance_to(c.solver.station_center(3))
 launch_roof(c)
 for tick in 840:c.advance(1./120)
 checks.roof_during_wall_playback=c.baked_count>=2 and c.impact_history.any(func(hit):return hit.get('overlay',false)) and c.mode!='BAKED'
 checks.overlay_keeps_front_crush=c.solver.station_center(6).distance_to(c.solver.station_center(3))<=front_before+.05
 invariant(c,'during_playback');runs.append({'case':'roof_during_wall','impacts':c.baked_count,'last_bake':c.last_bake,'history':c.impact_history})
func _rejection() -> void:
 var c:=car();launch_roof(c)
 for i in c.solver.velocities.size():c.solver.velocities[i]=Vector3(0,80,0)
 c.compact.capture_shape();var denied: Dictionary=c.roof_landing_sensor.event(c,1./120,c.roof_landing_library)
 checks.rejected_contact_does_not_latch=denied.is_empty() and not c.roof_landing_sensor.latched
 for i in c.solver.velocities.size():c.solver.velocities[i]=Vector3(20,-1,0)
 c.compact.capture_shape();run_until_done(c)
 checks.later_valid_contact_still_works=c.baked_count==1
func _wheel_masking() -> void:
 var c:=car();launch_roof(c)
 var w: Variant=c.solver.wheels.wheels[0]
 var support: Vector3=c.solver.wheels.support(w,Vector3.DOWN)
 c.solver.points[w.node].y=c.solver.floor_sample(c.solver.points[w.node]).w-support.y-.001
 c.solver.velocities[w.node]=Vector3(20,-1,0);c.compact.capture_shape()
 var early: Dictionary=Ground.packet(c,.05,true)
 checks.fixture_has_earlier_tire_contact=not early.is_empty() and early.signature.first_contacts.all(func(hit):return hit.source=='wheel')
 checks.tire_contact_alone_not_roof_damage=c.roof_landing_sensor.event(c,.001,c.roof_landing_library).is_empty() and not c.roof_landing_sensor.latched
 checks.earlier_tire_does_not_hide_roof=c.roof_landing_sensor.event(c,.05,c.roof_landing_library).get('selection',{}).get('accepted',false)
func _run() -> void:
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification/world_damage'))
 _ring();_ramps();_stack();_during();_rejection();_wheel_masking()
 var passed: bool=checks.values().all(func(v):return v)
 FileAccess.open('res://verification/world_damage/validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':runs,'scope':'Approximate incremental local baked shapes; same physical root/wheels. Authored exact wall and conditioned path remains available; arbitrary histories use approximate additive deformation.'},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('WORLD_DAMAGE_VERIFIED ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
