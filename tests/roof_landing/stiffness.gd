extends SceneTree
const Driving=preload('res://scripts/driving_vehicle.gd')
const Tuning=preload('res://scripts/roof_stiffness_tuning.gd')
const Cases=preload('res://scripts/roof_landing_cases.gd')
const Fixture=preload('res://scripts/body_impact_fixture.gd')
const Response=preload('res://scripts/roof_landing_response.gd')
var checks: Dictionary={}
var runs: Array=[]
func _initialize() -> void:call_deferred('_run')
func height(c: RefCounted) -> float:
 return (c.solver.points[10].distance_to(c.solver.points[8])+c.solver.points[11].distance_to(c.solver.points[9]))*.5
func baked(value: float) -> float:
 var c:=Driving.new();c.setup();c.set_roof_stiffness(value);c.solver.barrier_enabled=false
 Cases.place(c,{'roll_deg':0.,'forward_kmh':60.,'down_mps':4.,'roll_rate':0.},.04)
 var before:=height(c);var minimum:=before;var prepared: int=Response.preparations
 for tick in 420:
  c.advance(1./120);minimum=minf(minimum,height(c))
 var key: String='baked_'+str(value)
 checks[key+'_triggered']=c.baked_count>=1 and c.impact_history[0].get('completed',false)
 checks[key+'_captured_tuning']=c.impact_history[0].roof_stiffness==value and is_equal_approx(c.impact_history[0].damage_scale,1.0/value)
 checks[key+'_zero_solves']=c.full_steps==0 and c.solver.step_count==0 and c.solver.panels.active_steps==0 and c.solver.effects.glass.membrane_solve_steps==0 and c.solver.effects.interior.cloth_steps==0
 checks[key+'_no_rebuild']=Response.preparations==prepared
 checks[key+'_mass_finite']=absf(c.solver.owned_mass_kg()-1210)<.001 and Array(c.solver.points).all(func(p):return p.is_finite())
 runs.append({'mode':'baked','stiffness':value,'height_loss_m':before-minimum,'impacts':c.baked_count,'full_steps':c.full_steps})
 print('ROOF_STIFFNESS ',JSON.stringify(runs[-1]))
 return before-minimum
func live(value: float) -> float:
 var c:=Driving.new();c.setup();c.set_roof_stiffness(value)
 Fixture.start(c,'roof_flat',.01,true,4.0)
 var before:=height(c);var minimum:=before
 for tick in 90:
  c.advance(1./120);minimum=minf(minimum,height(c))
 var key: String='live_'+str(value)
 checks[key+'_actually_solved']=c.full_steps>0 and c.solver.step_count>0
 checks[key+'_mass_finite']=absf(c.solver.owned_mass_kg()-1210)<.001 and Array(c.solver.points).all(func(p):return p.is_finite())
 runs.append({'mode':'live','stiffness':value,'height_loss_m':before-minimum,'full_steps':c.full_steps})
 print('ROOF_STIFFNESS ',JSON.stringify(runs[-1]))
 return before-minimum
func parameters() -> void:
 var c:=Driving.new();c.setup();checks.stronger_default=c.roof_stiffness==3
 c.set_roof_stiffness(4);c.reset();checks.repair_keeps_tuning=c.roof_stiffness==4
 c.set_roof_stiffness(-2);checks.lower_bound=c.roof_stiffness==.5
 c.set_roof_stiffness(100);checks.upper_bound=c.roof_stiffness==8
 c.set_roof_stiffness(NAN);checks.invalid_uses_default=c.roof_stiffness==Tuning.DEFAULT
 var g: RefCounted=c.solver;Tuning.apply_live(g,1)
 var index: int=g.get_meta('roof_tuning_indices')[0];var rail_index:=-1
 for i in g.links.size():
  if i not in g.get_meta('roof_tuning_indices'):rail_index=i;break
 var rail: float=g.links[rail_index].stiffness_n_per_m
 var weak: float=g.links[index].stiffness_n_per_m;var weak_yield: float=g.links[index].yield_n
 Tuning.apply_live(g,4)
 checks.live_stiffness_and_yield_scale=is_equal_approx(g.links[index].stiffness_n_per_m,weak*4) and is_equal_approx(g.links[index].yield_n,weak_yield*4)
 Tuning.apply_live(g,4);checks.live_idempotent=is_equal_approx(g.links[index].stiffness_n_per_m,weak*4)
 checks.rails_unchanged=g.links[rail_index].stiffness_n_per_m==rail
 Fixture.apply_experimental_materials(g);Tuning.apply_live(g,4)
 checks.fixture_replacement_reapplies=is_equal_approx(g.links[index].stiffness_n_per_m,weak*4)
 c.set_simulation_quality(4);Tuning.apply_live(g,4)
 checks.quality_keeps_damping_consistent=is_equal_approx(g.links[index].damping_fraction,1-exp(-g.links[index].damping_ns_per_m*g.links[index].weight_sum*g.config.fixed_step_s))
 # A slider change must not rescale an already running clip or heal geometry.
 Cases.place(c,{'roll_deg':0.,'forward_kmh':60.,'down_mps':4.,'roll_rate':0.},.04)
 c.set_roof_stiffness(1)
 for tick in 60:
  c.advance(1./120)
  if c.mode=='BAKED':break
 var points: PackedVector3Array=g.points.duplicate();c.set_roof_stiffness(8)
 checks.active_hit_keeps_captured_scale=c.mode=='BAKED' and c.crash_player.damage_scale==1
 checks.slider_does_not_repair_current_shape=points==g.points
func ui() -> void:
 for path in ['res://arena/colosseum.tscn','res://driving.tscn']:
  var scene: Node=load(path).instantiate();root.add_child(scene);scene.set_process(false);scene.set_physics_process(false)
  var c: RefCounted=scene.car if path.contains('arena') else scene.vehicle
  checks[path+'_slider_default']=scene.roof_control is HSlider and scene.roof_control.value==3
  scene.roof_control.value=3.5
  checks[path+'_slider_wired']=c.roof_stiffness==3.5
  scene._reset();checks[path+'_reset_keeps_setting']=c.roof_stiffness==3.5 and scene.roof_control.value==3.5
  scene.queue_free()
func _run() -> void:
 parameters()
 var soft:=baked(1);var normal:=baked(2);var default_loss:=baked(3);var stiff:=baked(4)
 checks.baked_monotonic=soft>normal+.04 and normal>default_loss+.04 and default_loss>stiff+.02
 var live_soft:=live(1);var live_stiff:=live(4)
 checks.live_resists_more=live_soft>live_stiff+.005
 ui()
 var passed: bool=checks.values().all(func(value):return value)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification/roof_stiffness'))
 FileAccess.open('res://verification/roof_stiffness/validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'runs':runs,'scope':'Baked roof shape scale vs true live roof-member tuning. Existing recordings are immutable; this is not newly simulated material interpolation.'},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('ROOF_STIFFNESS_VERIFIED ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
