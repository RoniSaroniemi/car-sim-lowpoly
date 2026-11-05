extends SceneTree
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Player=preload('res://scripts/baked_crash_player.gd')
var checks: Dictionary={}
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 for name_ in ['roof_flat_35','roof_corner_35']:
  var data: Dictionary=Clip.read('res://bakes/roof/'+name_+'.crashclip')
  checks[name_+'_present']=not data.is_empty()
  if data.is_empty():continue
  checks[name_+'_compatible_v3_1920hz']=Clip.input_compatibility(data).compatible and data.metadata.version==3 and data.metadata.physics_hz==1920 and data.metadata.family=='roof_floor'
  var car:=Vehicle.new();car.setup()
  var rotation:=Basis(Vector3.UP,.7);var origin:=Vector3(11,3,-7)
  Clip.apply(car.solver,data,0,origin,rotation)
  var player:=Player.new();player.attach_live(car,[data],data.metadata.signature,{'accepted':true,'index':0})
  checks[name_+'_full3d_continuous_registration']=player.pose_registration_error_m<.00001 and player.handoff_position_jump_m<.00001 and player.handoff_velocity_jump_mps<.0001
  var counters: Array=[car.solver.effects.glass.membrane_solve_steps,car.solver.effects.interior.live_steps]
  var max_error:=0.0
  for sample in 300:
   player.advance(1.0/120)
   if sample<12:continue
   for node in car.solver.points.size():
    max_error=maxf(max_error,car.solver.points[node].distance_to(rotation*data.frames[sample+1].points[node]+origin))
  checks[name_+'_all_registered_samples_match']=max_error<.0001
  checks[name_+'_no_live_solves']=car.solver.step_count==0 and counters==[car.solver.effects.glass.membrane_solve_steps,car.solver.effects.interior.live_steps] and player.state=='COMPLETE'
 var passed: bool=checks.size()==10 and checks.values().all(func(value):return value)
 FileAccess.open('res://verification/roof_bank_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'scope':'Saved roof recordings with full roll/pitch/yaw registration. Floor contact triggering is separately gated by the runtime.'},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('ROOF_BANK_VERIFIED ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
