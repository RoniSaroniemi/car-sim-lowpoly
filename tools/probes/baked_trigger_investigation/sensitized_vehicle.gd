extends 'res://tools/probes/baked_trigger_investigation/audit_vehicle.gd'
## Investigation only: a cheap forecast arms a larger classification manifold.
## Production runtime is untouched. Trigger still requires the original next-step contact.
var armed:=false
var arm_deadline:=0.0
var cheap_forecast_checks:=0
var widened_activations:=0
var used_band:=0.0
func _contact_event(horizon: float) -> Dictionary:
 var event: Dictionary=super._contact_event(horizon)
 if not event.is_empty():return event
 if not solver.barrier_enabled or not basic_reason().is_empty():armed=false;return {}
 var motion: Vector3=velocity()
 var offset: Vector3=(solver.barrier_min-compact.center).max(compact.center-solver.barrier_max).max(Vector3.ZERO)
 if offset.length_squared()>pow(3.5+motion.length()*.066,2):armed=false;return {}
 cheap_forecast_checks+=1
 if is_finite(nodal_toi(.066)):armed=true;arm_deadline=solver.simulated_time+.1
 elif solver.simulated_time>arm_deadline:armed=false
 if not armed:return {}
 # Reuse the actual contact classifier's existing geometry/material guards.
 var contact: Dictionary=diagnose(horizon)
 if not contact.possible or contact.reason!='bank_match':return {}
 var toi: float=contact.toi_s
 var before: PackedVector3Array=solver.points.duplicate()
 for i in solver.points.size():solver.points[i]+=solver.velocities[i]*toi
 var signature: Dictionary={};var selection: Dictionary={}
 for band in [.05,.10]:
  signature=band_signature(motion,band)
  selection=_choose_speed_bin(signature)
  if selection.get('accepted',false):used_band=band;break
 solver.points=before
 if not selection.get('accepted',false):return {}
 widened_activations+=1
 return {'toi':toi,'signature':signature,'selection':selection}
