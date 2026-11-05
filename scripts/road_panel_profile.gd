extends RefCounted
## One explicit conservative game profile for real driving and frontal authoring.
const ID='road_panels_v2'
static func apply(system: RefCounted,repair: bool=false) -> void:
 for p in system.panels:
  if repair:
   for key in ['closing_supports','impact_evidence','angular_mount','frozen_local','reduced_data','reduced_mode','reduced']:
    p.erase(key)
   p['reduced']=false;p['reduced_mode']='asleep_closed';p['closing_engaged']=true
  p['profile_id']=ID;p.hinge_strength_n=16000.0;p.latch_strength_n=8000.0;p.failure_delay_s=.045;p['lower_strength_fraction']=.60
  if not p.has('closing_supports'):system.configure_closing_seats(p)
  p['local_failure']=true
  if not p.has('impact_evidence'):p['impact_evidence']={'last_contact_s':-1.0,'was_closed':true,'inward_alignment':0.0,'max_inward_m':0.0,'max_outward_m':0.0,'plastic_m':0.0,'lever_m':0.0,'patch_mask':0,'max_contact_force_n':0.0,'current_inward_m':0.0}
  p['contact_step_mask']=0;p['contact_step_normal']=Vector3.ZERO;p['contact_step_force']=0.0;p['contact_step_lever']=0.0
  if not p.has('angular_mount'):p['angular_mount']={'rest_axis':Vector3.UP if p.side!=0 else Vector3.FORWARD,'stiffness_nm_rad':4500.0,'yield_nm':900.0,'break_nm':6500.0,'damping_nms_rad':140.0,'overload_s':0.0,'plastic_rad':0.0,'plastic_work_j':0.0,'peak_nm':0.0,'lambda':Vector3.ZERO,'step_peak_nm':0.0,'yielded':false,'max_plastic_rad':deg_to_rad(30)}
