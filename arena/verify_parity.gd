extends SceneTree
const Vehicle=preload('res://arena/vehicle.gd')
const Terrain=preload('res://arena/terrain.gd')
var checks: Dictionary={}
var runs: Array=[]
func _initialize() -> void:call_deferred('_run')
func _car() -> RefCounted:
 var car:=Vehicle.new();car.setup();car.solver.terrain=Terrain.new();return car
func _finite(car: RefCounted) -> bool:
 return car.solver.points.to_byte_array().size()>0 and Array(car.solver.points).all(func(p):return p.is_finite())
func _run() -> void:
 var probe:=_car();probe.solver.barrier_enabled=false
 var hit: Dictionary=probe.solver.static_contact(Vector3(75.9,1,0),.4)
 checks['provider_works_without_main_barrier']=hit.source=='arena_ring' and absf(float(hit.distance)-.1)<.00001 and hit.normal.distance_to(Vector3.LEFT)<.00001
 hit=probe.solver.static_contact(Vector3(76.1,1,0),.4)
 checks['provider_signed_center_distance']=absf(float(hit.distance)+.1)<.00001
 hit=probe.solver.static_contact(Vector3.ZERO,.4)
 checks['provider_empty_query_contract']=hit.source=='none' and is_inf(float(hit.distance)) and hit.normal==Vector3.ZERO
 probe.solver.barrier_enabled=true;hit=probe.solver.static_contact(Vector3(39.9,1,0),.4)
 checks['compatible_wall_source_identified']=hit.source=='barrier' and absf(float(hit.distance)-.1)<.00001
 for spec in [[60.,0.],[120.,0.],[120.,20.],[120.,-20.]]:
  var car:=_car();car.reset_wall_approach(spec[0],spec[1])
  for tick in 540:car.advance(1.0/120)
  var id_: String='wall_%d_%d'%[spec[0],spec[1]]
  checks[id_+'_actual_bake']=car.baked_count==1 and car.last_bake.get('completed',false)
  checks[id_+'_zero_heavy_forecast']=car.full_steps==0 and car.forecast.checks==0
  checks[id_+'_finite']=_finite(car)
  runs.append({'case':id_,'bake':car.last_bake,'stats':car.statistics()})
 var car:=_car();car.start_baked_sequence()
 for tick in 1800:
  car.advance(1.0/120)
  if car.baked_count==3 and not car.sequence_active:break
 checks['three_conditioned_impacts']=car.baked_count==3 and not car.sequence_active and car.full_steps==0
 runs.append({'case':'conditioned_sequence','stats':car.statistics(),'notice':car.sequence_notice})
 for mode in [true,false]:
  car=_car();car.baked_enabled=mode;car.solver.barrier_enabled=false;car.reset(55,Vector3(69,0,0))
  for tick in 420:car.advance(1.0/120)
  var radius:=Vector2(car.compact.center.x,car.compact.center.z).length()
  checks['ring_%s_retains'%str(mode)]=radius<77.5 and _finite(car)
  checks['ring_%s_correct_damage_path'%str(mode)]=car.baked_count==1 and car.last_bake.get('incremental',false) if mode else car.baked_count==0
  checks['ring_%s_mode'%str(mode)]=car.full_steps==0 if mode else car.full_steps>0
  runs.append({'case':'ring_baked_'+str(mode),'radius_m':radius,'work_j':car.solver.plastic_work,'stats':car.statistics()})
 car=_car();car.baked_enabled=false;car.reset_wall_approach(60,0)
 for tick in 420:car.advance(1.0/120)
 checks['live_wall_deforms']=car.full_steps>0 and car.solver.plastic_work>100 and car.baked_count==0 and _finite(car)
 runs.append({'case':'live_wall60','work_j':car.solver.plastic_work,'stats':car.statistics()})
 # Exercise actual HUD signals and its reset/staging entry points.
 var scene: Node=load('res://arena/colosseum.tscn').instantiate();root.add_child(scene)
 scene.set_physics_process(false);scene.set_process(false)
 scene.power_control.value=330;scene.grip_control.value=.37
 scene.quality_control.select(2);scene.quality_control.item_selected.emit(2)
 scene.bake_toggle.button_pressed=false
 scene._reset();scene._stage_feature(2);scene._pair_start(0);scene._start_head_on(60,0)
 checks['hud_power_grip_persist_staging']=scene.car.dynamics.parameters.power_w==330000 and absf(scene.car.dynamics.parameters.tire_friction-.37)<.0001
 checks['hud_quality_persists']=absf(scene.car.solver.config.fixed_step_s-1.0/1920)<.0000001
 checks['hud_live_toggle_persists']=not scene.car.baked_enabled
 scene._start_body_test('roof_corner');checks['hud_roof_fixture_live']=scene.body_fixture_active and scene.car.mode=='FULL' and not scene.car.baked_enabled
 scene._reset();scene._start_mount_test();checks['hud_mount_fixture_active']=scene.mount_demo.active
 checks['panel_widget_integration_container']=scene.panel_controls!=null and scene.panel_controls.name=='PanelControls'
 checks['panel_widget_uses_shared_vehicle']=scene.panel_controls.vehicle==scene.car and scene.panel_controls.labels.size()==4
 scene.panel_controls._command('door_left',70)
 for tick in 120:scene.car.advance(1.0/120)
 checks['panel_widget_opens_actual_panel']=not scene.car.panel_state('door_left').latched
 scene.queue_free()
 var tuning: Array=[]
 for power in [55.,660.]:
  car=_car();car.set_engine_power_kw(power);car.reset(0,Vector3(-60,0,0));car.set_controls(1,0,0)
  for tick in 240:car.advance(1.0/120)
  tuning.append(car.velocity().length())
 checks['power_changes_actual_acceleration']=float(tuning[1])>float(tuning[0])*1.25
 var braking: Array=[]
 for grip in [.2,1.2]:
  car=_car();car.set_tire_friction(grip);car.reset(60,Vector3(-60,0,0));car.set_controls(0,1,0)
  for tick in 240:car.advance(1.0/120)
  braking.append(car.velocity().length())
 checks['friction_changes_actual_braking']=float(braking[0])>float(braking[1])+2
 var passed: bool=checks.values().all(func(v):return v)
 var report: Dictionary={'passed':passed,'checks':checks,'runs':runs,'power_end_speed_mps':tuning,'braking_end_speed_mps':braking}
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification'))
 FileAccess.open('res://verification/arena_parity.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('ARENA_PARITY_VERIFIED ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
