extends SceneTree
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Interior=preload('res://scripts/vehicle_interior.gd')
const SkinView=preload('res://scripts/structural_skin.gd')
var checks: Dictionary={}
var runs: Array=[]
var evidence_frames: Array=[]
func _initialize() -> void:call_deferred('_run')
func run_crash(speed: float,settings: Dictionary={}) -> Dictionary:
 var car:=Vehicle.new();car.setup('res://vehicles/niva.json',false);car.solver.config.enforce_symmetry=false;car.reset(speed)
 var effects:=Interior.new();effects.setup(car.solver,settings)
 var samples: Array=[];var peak:=0.0;var finite:=true
 for step in 1440:
  car.step(1.0/480)
  var before: PackedVector3Array=car.solver.points.duplicate()
  effects.step_live(1.0/480)
  checks['interior_does_not_move_chassis']=checks.get('interior_does_not_move_chassis',true) and before==car.solver.points
  for seat in effects.seats:peak=maxf(peak,absf(seat.angle));finite=finite and is_finite(seat.angle)
  for point in effects.bag.points:finite=finite and point.is_finite()
  if step%4==3:samples.append({'body':car.solver.capture(),'interior':effects.capture()})
 var run: Dictionary={'speed_kmh':speed,'airbag_enabled':effects.airbag_enabled,'deployed':effects.bag.triggered,'deployment_event_id':effects.deployment_event_id,'cloth_steps':effects.cloth_steps,'peak_seat_deflection_deg':rad_to_deg(peak),'permanent_seat_deflection_deg':rad_to_deg(effects.seats[0].plastic_angle),'max_neck_error_m':effects.bag.maximum_anchor_error,'finite':finite,'mass_kg':car.solver.config.mass_kg,'nodes':car.solver.points.size(),'profile_id':effects.profile_id}
 runs.append(run)
 var key: String=str(speed)+('_disabled' if not effects.airbag_enabled else '')
 checks[key+'_finite']=finite
 checks[key+'_mass_and_nodes_unchanged']=car.solver.config.mass_kg==1210 and car.solver.points.size()==38
 if speed<25:checks['low_speed_airbag_suppressed']=not effects.bag.triggered and effects.cloth_steps==0
 elif effects.airbag_enabled:
  checks[key+'_frontal_airbag_deploys']=effects.bag.triggered and effects.deployment_event_id==1 and effects.cloth_steps>0
  checks[key+'_seat_responds']=peak>deg_to_rad(1)
  checks[key+'_neck_anchored']=effects.bag.maximum_anchor_error<.00001
 else:checks['equipment_toggle_suppresses_airbag']=not effects.bag.triggered and effects.cloth_steps==0
 if speed==120 and effects.airbag_enabled:
  evidence_frames=samples
  var file:=FileAccess.open_compressed('res://verification/interior_live_roundtrip.fx',FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD);file.store_var(samples);file.close()
  file=FileAccess.open_compressed('res://verification/interior_live_roundtrip.fx',FileAccess.READ,FileAccess.COMPRESSION_ZSTD)
  var decoded: Array=file.get_var(false);file.close()
  var previous_live: int=effects.live_steps;var previous_cloth: int=effects.cloth_steps
  effects.begin_playback(decoded[0].interior)
  var error:=0.0;var angle_error:=0.0
  for sample in decoded:
   effects.restore_interpolated(sample.interior,sample.interior,0)
   var actual: Dictionary=effects.capture()
   for i in effects.seats.size():angle_error=maxf(angle_error,absf(actual.seats[i].angle-sample.interior.seats[i].angle))
   if effects.bag.triggered:
    for i in effects.bag.points.size():error=maxf(error,effects.bag.points[i].distance_to(sample.interior.airbag.points[i]))
  checks['disk_replay_attachment_local_poses_exact']=error<.000001 and angle_error<.000001
  checks['playback_runs_no_cloth_or_seat_solve']=effects.live_steps==previous_live and effects.cloth_steps==previous_cloth
  var final: Dictionary=decoded[-1].interior
  effects.begin_playback(final)
  checks['conditioned_initial_keeps_seat_and_airbag']=effects.seats[0].plastic_angle!=0 and effects.bag.triggered and effects.deployment_event_id==1
  effects.restore_interpolated({}, {},0)
  checks['legacy_frames_are_intact']=not effects.bag.triggered and effects.seats[0].angle==0
  effects.begin_playback(final);effects.reset()
  checks['repair_clears_irreversible_state']=not effects.bag.triggered and effects.seats[0].plastic_angle==0 and effects.deployment_event_id==0
 return {'car':car,'effects':effects}
func _run() -> void:
 run_crash(20)
 run_crash(60)
 var high: Dictionary=run_crash(120)
 run_crash(120,{'airbag':{'enabled':false}})
 var car:=Vehicle.new();car.setup('res://vehicles/niva.json',true);car.solver.barrier_enabled=false;car.reset(60,Vector3(-30,0,0))
 var effects:=Interior.new();effects.setup(car.solver);car.set_controls(0,1,0)
 for step in 480:car.step(1.0/480);effects.step_live(1.0/480)
 checks['ordinary_braking_does_not_deploy']=not effects.bag.triggered and effects.cloth_steps==0
 checks['ordinary_braking_keeps_seat_elastic']=absf(effects.seats[0].plastic_angle)<.0001
 var view:=Node3D.new();view.set_script(SkinView);root.add_child(view);view.setup(car.solver,car.profile.model)
 var visual: Node3D=effects.create_visual(view,view.body);view.add_child(visual)
 checks['actual_car_front_seat_groups_extracted']=visual.seat_groups.size()==4 and visual.split_triangles==3352
 checks['original_interior_triangles_preserved']=visual.original_triangles==12498
 for group in visual.seat_groups:checks['group_has_actual_original_geometry']=checks.get('group_has_actual_original_geometry',true) and group.node.mesh.get_surface_count()>0
 view.queue_free()
 var evidence:=FileAccess.open_compressed('res://verification/interior_car_evidence.fx',FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD);evidence.store_var(evidence_frames);evidence.close()
 checks['all_four_crash_cases_completed']=runs.size()==4
 var passed: bool=checks.values().all(func(value):return value)
 var report: Dictionary={'passed':passed,'checks':checks,'runs':runs,'scope':'Actual vehicle graph, one-way interior controller, optional demonstration airbag. Physical parameters are game approximations; no occupant safety calibration.'}
 FileAccess.open('res://verification/vehicle_interior_validation.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('VEHICLE_INTERIOR_VERIFIED ',passed,' checks=',checks.size(),' runs=',JSON.stringify(runs))
 quit(0 if passed else 1)
