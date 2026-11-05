extends 'res://scripts/multiaxis_crash_recorder.gd'
const LandingCases=preload('res://scripts/roof_landing_cases.gd')
const LandingGeometry=preload('res://scripts/roof_landing_geometry.gd')
const FloorWake=preload('res://scripts/panel_floor_wake.gd')
var landing_spec: Dictionary={}
func start_landing(spec: Dictionary,quality: int=4) -> void:
 super.start('top',float(spec.down_mps)*3.6,quality)
 landing_spec=spec.duplicate(true)
 LandingCases.place(vehicle,spec)
 var g: RefCounted=vehicle.solver
 g.barrier_enabled=false;g.terrain=null;vehicle.mode='FULL';g.compact_active=false
 g.config.enforce_symmetry=false
 vehicle.before_step.connect(func(h):FloorWake.step(g,h))
 descriptor={'key':spec.id,'azimuth_deg':0,'roof_landing_spec':spec,'contact_policy':'body_tire_panel_floor_first_contact'}
 initial_metrics=_outcome()
func _register_contact(toi: float) -> void:
 super._register_contact(toi)
 if completed:return
 signature=LandingGeometry.signature(vehicle.solver)
 if signature.is_empty():_fail('Missing roof-landing signature')
func _complete() -> void:
 super._complete()
 if result.is_empty():return
 result.metadata.id=landing_spec.id;result.metadata.family='roof_landing_floor'
 result.metadata['landing_spec']=landing_spec
 result.metadata['physics_recipe']='roof_landing_floor_wake_v1'
 result.metadata['forward_speed_kmh']=landing_spec.forward_kmh
 result.metadata['downward_speed_mps']=landing_spec.down_mps
 for path in ['scripts/panel_floor_wake.gd','scripts/roof_landing_geometry.gd','scripts/roof_landing_cases.gd','scripts/roof_landing_recorder.gd']:
  result.metadata.input_sha256[path]=FileAccess.get_sha256('res://'+path)
