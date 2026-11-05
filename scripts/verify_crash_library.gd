extends SceneTree
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Player=preload('res://scripts/baked_crash_player.gd')
const Recorder=preload('res://scripts/crash_bake_recorder.gd')
const Zones=preload('res://scripts/impact_zone_grid.gd')
var checks: Dictionary={}
var runs: Array=[]
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var three_only: bool='--three-only' in OS.get_cmdline_user_args()
 var all_clips: Array=Clip.read_library()
 var library: Array=all_clips.slice(0,3) if three_only else all_clips
 checks['complete_library']=library.size()==Clip.specifications(three_only).size()
 if library.is_empty():quit(1);return
 for data in library:
  var id: String=data.metadata.id
  checks[id+'_inputs_compatible']=Clip.input_compatibility(data).compatible
  checks[id+'_frames']=data.frames.size()==301
  checks[id+'_exact_impact_speed']=absf(float(data.metadata.signature.closing_speed_mps)*3.6-float(data.metadata.speed_kmh))<.0001
  var player:=Player.new();player.setup_library(library,data.metadata.heading_deg,data.metadata.speed_kmh)
  for i in 600:
   player.advance(1.0/120)
   if player.state in ['COMPLETE','REJECTED']:break
  checks[id+'_selected_correct_clip']=player.state=='COMPLETE' and player.match_result.get('id','')==id
  checks[id+'_no_solver_steps']=player.vehicle.solver.step_count==0
  checks[id+'_continuous_handoff']=player.handoff_position_jump_m<.00001
  var origin:=Vector3(data.metadata.origin[0],data.metadata.origin[1],data.metadata.origin[2])
  var error:=0.0;var damage_error:=0.0;var wheels_error:=0.0;var flags:=true;var finite:=true
  for f in data.frames.size():
   Clip.apply(player.vehicle.solver,data,float(f)/120,origin)
   var actual: Dictionary=player.vehicle.solver.capture()
   var expected: Dictionary=data.frames[f]
   flags=flags and actual.broken==expected.broken and actual.lengths==expected.lengths
   for i in actual.points.size():
    error=maxf(error,actual.points[i].distance_to(expected.points[i]+origin))
    damage_error=maxf(damage_error,absf(actual.damage[i]-expected.damage[i]))
    finite=finite and actual.points[i].is_finite() and actual.velocities[i].is_finite()
   for i in actual.wheels.size():
    wheels_error=maxf(wheels_error,1-absf(actual.wheels[i].rotation.dot(expected.wheels[i].rotation)))
    wheels_error=maxf(wheels_error,absf(angle_difference(actual.wheels[i].spin,expected.wheels[i].spin)))
    flags=flags and actual.wheels[i].detached==expected.wheels[i].detached
  checks[id+'_all_saved_poses_damage_wheels_match']=finite and error<.00001 and damage_error<.00001 and wheels_error<.00001 and flags
  # Final registered replay must match the transformed saved deformation.
  player.apply_pose(float(data.metadata.duration_s))
  var replay_error:=0.0
  for i in player.vehicle.solver.points.size():
   var expected: Vector3=player.replay_rotation*data.frames[-1].points[i]+player.origin
   replay_error=maxf(replay_error,player.vehicle.solver.points[i].distance_to(expected))
  checks[id+'_registered_replay_matches']=replay_error<.00001
  var peak_damage:=0.0
  for frame in data.frames:
   for damage in frame.damage:peak_damage=maxf(peak_damage,damage)
  checks[id+'_whole_body_damage_recorded']=peak_damage>.001
  runs.append({'id':id,'angle_deg':data.metadata.heading_deg,'speed_kmh':data.metadata.speed_kmh,'selected':player.match_result.get('id',''),'score':player.match_result.get('score',0),'zone_overlap':player.match_result.get('zone_overlap',0),'handoff_jump_m':player.handoff_position_jump_m,'registration_correction_m':player.pose_registration_error_m,'max_sample_error_m':error,'max_registered_replay_error_m':replay_error,'solver_steps':player.vehicle.solver.step_count,'playback_cpu_ms':player.player_cpu_us/1000.0,'record_cpu_ms':data.metadata.record_cpu_ms,'zones':data.metadata.signature.zones,'final_metrics':player.vehicle.solver.metrics()})
  print('LIBRARY_CASE ',id,' selected=',player.match_result.get('id','NONE'),' score=',player.match_result.get('score',0),' registered_error=',replay_error)
 # Exercise unrecorded angles: classifier must choose at contact, independently of UI choice.
 for test in [{'angle':5.0,'expected':'frontal_120'},{'angle':17.0,'expected':'front_left_20_120'},{'angle':-17.0,'expected':'front_right_20_120'}]:
  var player:=Player.new();player.setup_library(library,test.angle,120)
  for i in 500:player.advance(1.0/120)
  checks['unrecorded_%s_selects_nearest'%test.angle]=player.state=='COMPLETE' and player.match_result.get('id','')==test.expected and player.vehicle.solver.step_count==0 and player.handoff_position_jump_m<.00001
  print('NEAREST_CASE ',test.angle,' ',JSON.stringify(player.match_result))
 if not three_only:
  for speed in [60.0,120.0]:
   for angle in range(15,360,30):
    var player:=Player.new();player.setup_library(library,wrapf(angle,-180,180),speed)
    for i in 500:player.advance(1.0/120)
    var matched: bool=player.state=='COMPLETE' and player.match_result.get('accepted',false)
    var error: float=absf(rad_to_deg(angle_difference(deg_to_rad(angle),deg_to_rad(float(player.data.metadata.heading_deg)))))
    checks['between_%d_%d_matches_local_angle_speed'%[angle,roundi(speed)]]=matched and error<=18 and player.data.metadata.speed_kmh==speed and player.vehicle.solver.step_count==0 and player.handoff_position_jump_m<.00001
    print('BETWEEN_CASE ',angle,'/',speed,' selected=',player.match_result.get('id','NONE'),' error=',error)
    if not matched:print('UNMATCHED_SIGNATURE ',JSON.stringify(player.incoming),' scores=',JSON.stringify(player.match_result))
 var zones:=Zones.new()
 var wrong: Dictionary=library[0].metadata.signature.duplicate(true)
 wrong.incident_impulse_proxy_ns*=.25
 checks['incompatible_severity_rejected']=not zones.choose(wrong,library).accepted
 checks['empty_contact_rejected']=not zones.choose({},library).accepted
 var passed: bool=checks.values().all(func(c):return c)
 var report: Dictionary={'passed':passed,'checks':checks,'runs':runs,'clip_count':library.size(),'scope':'Controlled wall-normal slams; full-body and wheel state baked, no live solve in replay. Intermediate-angle registration is an approximation.'}
 FileAccess.open('res://verification/crash_library_validation.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
 print('CRASH_LIBRARY_VERIFIED ',passed,' checks=',checks.size())
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 quit(0 if passed else 1)
