extends SceneTree
const Vehicle=preload('res://scripts/driving_vehicle.gd')
const Coverage=preload('res://scripts/baked_contact_coverage.gd')
var checks: Dictionary={}
func _initialize() -> void:call_deferred('_run')
func context(car: RefCounted,z: float) -> Dictionary:
 car.reset(120,Vector3(37.9,0,z))
 var packet: Dictionary=car.contact_sensor.event(car.solver,car.velocity(),1.0/120)
 if packet.is_empty():return {}
 return Coverage.describe(car.solver,packet,packet.signature)
func _run() -> void:
 var car:=Vehicle.new();car.setup()
 car.solver.barrier_min=Vector3(40,0,-8);car.solver.barrier_max=Vector3(41,3,8)
 var full: Dictionary=context(car,0)
 checks['full_context']=full.get('full_width',false) and full.full_height
 checks['legacy_full_only']=Coverage.compatible(full,{}).accepted
 var partial: Dictionary=context(car,8)
 checks['partial_context']=not partial.get('full_width',true) and partial.overlap>.1 and partial.overlap<.9
 checks['legacy_never_partial']=not Coverage.compatible(partial,{}).accepted
 checks['partial_self_matches']=Coverage.compatible(partial,partial).accepted
 var tiny: Dictionary=partial.duplicate(true);tiny.overlap=.01;tiny.kept_interval=[0,.01]
 checks['tiny_is_not_half']=not Coverage.compatible(tiny,partial).accepted
 var other: Dictionary=partial.duplicate(true);other.edge_side='left' if partial.edge_side=='right' else 'right'
 checks['clipped_side_matters']=not Coverage.compatible(other,partial).accepted
 var shifted: Dictionary=partial.duplicate(true)
 car.solver.barrier_min+=Vector3(120,0,50);car.solver.barrier_max+=Vector3(120,0,50)
 car.reset(120,Vector3(157.9,0,58))
 var packet: Dictionary=car.contact_sensor.event(car.solver,car.velocity(),1.0/120)
 var translated: Dictionary=Coverage.describe(car.solver,packet,packet.signature)
 checks['translation_independent']=Coverage.compatible(translated,partial).accepted and absf(translated.overlap-partial.overlap)<.0001
 var low: Dictionary=partial.duplicate(true);low.full_height=false
 checks['height_requires_recording']=not Coverage.compatible(low,partial).accepted
 var end_: Dictionary=partial.duplicate(true);end_.feature='end_face'
 checks['end_face_requires_recording']=not Coverage.compatible(end_,partial).accepted
 var bad_profile: Dictionary=partial.duplicate(true);bad_profile.mass_kg+=5
 checks['mass_profile_identity']=not Coverage.compatible(bad_profile,partial).accepted
 var passed: bool=checks.values().all(func(value):return value)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification'))
 FileAccess.open('res://verification/contact_coverage_schema.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'checks':checks,'full':full,'partial':partial},'\t'))
 for key in checks:
  if not checks[key]:print('FAILED ',key)
 print('CONTACT_COVERAGE_SCHEMA ',passed,' checks=',checks.size())
 quit(0 if passed else 1)
