extends SceneTree
## Read-only campaign audit. Never authors clips or steps live physics.
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const OUTPUT='res://verification/bake_campaign/asset_audit.json'
const POSITION_EPS=.0001
const SCALAR_EPS=.0001
var directory: String='res://bakes'
var only: PackedStringArray=[]
var expected_count:=126
var allow_incomplete:=false
var current_hashes: Dictionary={}
var records: Array=[]
var seen_ids: Dictionary={}

func _initialize() -> void:call_deferred('_run')
func _files(path: String) -> Array:
 var result: Array=[];var folder:=DirAccess.open(path)
 if folder==null:return result
 var names:=folder.get_files();names.sort()
 for name in names:
  if name.ends_with('.crashclip'):result.append(path.path_join(name))
 var children:=folder.get_directories();children.sort()
 for child in children:result.append_array(_files(path.path_join(child)))
 return result
func _fail(row: Dictionary,key: String,detail: Variant=true) -> void:
 if not row.failures.has(key):row.failures[key]=detail
func _finite(value: Variant,path: String='') -> String:
 if value is float:
  # VehicleSurface uses -INF solely as a documented no-contact timestamp.
  if path.ends_with('.surface.last_change') and value==-INF:return ''
  return '' if is_finite(value) else path
 if value is Vector2 or value is Vector3 or value is Vector4 or value is Quaternion or value is Basis or value is Transform3D:
  return '' if value.is_finite() else path
 if value is Dictionary:
  for key in value:
   var bad: String=_finite(value[key],path+'.'+str(key))
   if bad!='':return bad
 elif value is Array or value is PackedVector2Array or value is PackedVector3Array or value is PackedVector4Array or value is PackedFloat32Array or value is PackedFloat64Array:
  for i in value.size():
   var bad: String=_finite(value[i],path+'['+str(i)+']')
   if bad!='':return bad
 return ''
func _vector_error(a: PackedVector3Array,b: PackedVector3Array) -> float:
 if a.size()!=b.size():return INF
 var error:=0.
 for i in a.size():error=maxf(error,a[i].distance_to(b[i]))
 return error
func _counters(g: RefCounted) -> Dictionary:
 return {'body':g.step_count,'panel_cage':g.panels.active_steps,'glass_membrane':g.effects.glass.membrane_solve_steps,'interior_live':g.effects.interior.live_steps,'interior_seat':g.effects.interior.seat_steps,'airbag_cloth':g.effects.interior.cloth_steps}
func _hash_mismatches(metadata: Dictionary) -> Dictionary:
 var result: Dictionary={}
 for field in ['input_sha256','surface_input_sha256']:
  if field=='input_sha256' and metadata.get(field,{}).is_empty():result['missing_input_fingerprints']=true
  for path in metadata.get(field,{}):
   if not current_hashes.has(path):current_hashes[path]=FileAccess.get_sha256('res://'+path)
   if current_hashes[path]!=metadata[field][path]:result[path]={'recorded':metadata[field][path],'current':current_hashes[path]}
 return result
func _observe(row: Dictionary,frame: Dictionary,initial: Dictionary,g: RefCounted) -> void:
 var obs: Dictionary=row.observed
 for id in frame.effects.glass.panes:
  var pane: Dictionary=frame.effects.glass.panes[id]
  if not obs.glass.has(id):obs.glass[id]={'maximum_stage':0,'maximum_crack':0.,'maximum_open_cells':0,'final_stage':0,'final_retained_cells':0}
  var out: Dictionary=obs.glass[id]
  out.maximum_stage=maxi(out.maximum_stage,pane.stage);out.maximum_crack=maxf(out.maximum_crack,pane.crack)
  out.maximum_open_cells=maxi(out.maximum_open_cells,Array(pane.mask).count(0));out.final_stage=pane.stage;out.final_retained_cells=Array(pane.mask).count(1)
  obs.glass_maximum_stage=maxi(obs.glass_maximum_stage,pane.stage)
 for p in frame.panels.panels:
  if not obs.panels.has(p.id):obs.panels[p.id]={'ever_unlatched':false,'ever_detached':false,'maximum_plastic_work_j':0.,'maximum_pairwise_shape_change_m':0.,'final_anchor_broken':[],'final_latched':true,'final_detached':false}
  var out: Dictionary=obs.panels[p.id]
  var template: Dictionary=initial.panels.panels.filter(func(part):return part.id==p.id)[0]
  out.ever_unlatched=out.ever_unlatched or not p.latched;out.ever_detached=out.ever_detached or p.detached
  out.maximum_plastic_work_j=maxf(out.maximum_plastic_work_j,p.plastic_work)
  out.final_anchor_broken=p.anchors.map(func(a):return a.broken);out.final_latched=p.latched;out.final_detached=p.detached
  for a in p.points.size():
   for b in a:out.maximum_pairwise_shape_change_m=maxf(out.maximum_pairwise_shape_change_m,absf(p.points[a].distance_to(p.points[b])-template.points[a].distance_to(template.points[b])))
 for index in frame.wheels.size():
  if obs.wheels.size()<=index:obs.wheels.append({'index':index,'ever_detached':false,'final_detached':false,'final_knuckle_broken':false,'maximum_compression_m':0.,'maximum_permanent_alignment_deg':0.})
  var wheel: Dictionary=frame.wheels[index];var out: Dictionary=obs.wheels[index]
  out.ever_detached=out.ever_detached or wheel.detached;out.final_detached=wheel.detached;out.final_knuckle_broken=wheel.joint_broken
  out.maximum_compression_m=maxf(out.maximum_compression_m,wheel.peak_compression)
  out.maximum_permanent_alignment_deg=maxf(out.maximum_permanent_alignment_deg,rad_to_deg(acos(clampf(wheel.alignment.dot(Vector3.BACK),-1,1))))
 for a in g.rest.size():
  if g.wheels.by_node.has(a):continue
  for b in a:
   if g.wheels.by_node.has(b):continue
   var change: float=absf(frame.points[a].distance_to(frame.points[b])-initial.points[a].distance_to(initial.points[b]))
   obs.maximum_body_pairwise_distance_change_m=maxf(obs.maximum_body_pairwise_distance_change_m,change)
 obs.airbag_deployed=obs.airbag_deployed or frame.effects.interior.airbag.triggered
 obs.maximum_airbag_deployment=maxf(obs.maximum_airbag_deployment,frame.effects.interior.airbag.deployment)
 for seat in frame.effects.interior.seats:obs.maximum_seat_plastic_angle_deg=maxf(obs.maximum_seat_plastic_angle_deg,absf(rad_to_deg(seat.plastic_angle)))
func _apply_check(row: Dictionary,data: Dictionary,index: int,g: RefCounted) -> void:
 var frame: Dictionary=data.frames[index]
 var rotation:=Basis.from_euler(Vector3(.29,.73,-.21));var origin:=Vector3(41,3,-17)
 Clip.apply(g,data,float(index)/float(data.metadata.sample_hz),origin,rotation)
 var current: Dictionary=g.capture();var max_body:=0.;var max_panel:=0.;var max_velocity:=0.;var max_rigid:=0.;var max_glass:=0.;var max_interior:=0.;var max_wheel:=0.
 for i in g.points.size():
  max_body=maxf(max_body,g.points[i].distance_to(rotation*frame.points[i]+origin))
  max_velocity=maxf(max_velocity,g.velocities[i].distance_to(rotation*frame.velocities[i]))
 for source in frame.panels.panels:
  var p: Dictionary=g.panels.find(source.id)
  for i in source.points.size():
   max_panel=maxf(max_panel,p.points[i].distance_to(rotation*source.points[i]+origin))
   max_velocity=maxf(max_velocity,p.velocity[i].distance_to(rotation*source.velocity[i]))
  if p.active!=source.active or p.detached!=source.detached or p.latched!=source.latched:_fail(row,'panel_discrete_'+str(index)+'_'+p.id)
  if p.anchors.map(func(a):return a.broken)!=source.anchors.map(func(a):return a.broken):_fail(row,'panel_anchors_'+str(index)+'_'+p.id)
  if p.get('closing_engaged',false)!=source.get('closing_engaged',false) or p.get('closing_supports',[]).map(func(s):return s.broken)!=source.get('closing_supports',[]).map(func(s):return s.broken):_fail(row,'panel_closing_topology_'+str(index)+'_'+p.id)
  for k in source.edges.size():
   if absf(p.edges[k].length-source.edges[k].length)>SCALAR_EPS or absf(p.edges[k].damage-source.edges[k].damage)>SCALAR_EPS:_fail(row,'panel_plastic_state_'+str(index)+'_'+p.id)
  if p.get('frozen_local',PackedVector3Array())!=source.get('frozen_local',PackedVector3Array()):_fail(row,'panel_frozen_local_'+str(index)+'_'+p.id)
  if source.has('reduced_data'):
   var s: Dictionary=source.reduced_data;var d: Dictionary=p.reduced_data
   max_rigid=maxf(max_rigid,d.center.distance_to(rotation*s.center+origin))
   max_rigid=maxf(max_rigid,1-absf(d.rotation.dot(rotation.get_rotation_quaternion()*s.rotation)))
   for field in ['linear','omega','old_mount_velocity']:
    if s.has(field):max_velocity=maxf(max_velocity,d[field].distance_to(rotation*s[field]))
   if d.offsets!=s.offsets or d.inverse_inertia!=s.inverse_inertia:_fail(row,'panel_reference_local_'+str(index)+'_'+p.id)
 for id in frame.effects.glass.panes:
  var a: Dictionary=frame.effects.glass.panes[id];var b: Dictionary=current.effects.glass.panes[id]
  if a.stage!=b.stage or a.mask!=b.mask or a.broken!=b.broken or a.released!=b.released or a.events!=b.events:_fail(row,'glass_topology_'+str(index)+'_'+id)
  max_glass=maxf(max_glass,_vector_error(a.nodes,b.nodes));max_glass=maxf(max_glass,_vector_error(a.velocities,b.velocities))
 var ia: Dictionary=frame.effects.interior;var ib: Dictionary=current.effects.interior
 if ia.airbag.triggered!=ib.airbag.triggered or ia.deployment_event_id!=ib.deployment_event_id:_fail(row,'interior_discrete_'+str(index))
 if ia.airbag.triggered:
  max_interior=maxf(max_interior,_vector_error(ia.airbag.points,ib.airbag.points))
  max_interior=maxf(max_interior,_vector_error(ia.airbag.velocities,ib.airbag.velocities))
 for i in ia.seats.size():
  for key in ['angle','omega','plastic_angle','plastic_work']:max_interior=maxf(max_interior,absf(ia.seats[i][key]-ib.seats[i][key]))
 for i in frame.wheels.size():
  max_wheel=maxf(max_wheel,1-absf(current.wheels[i].rotation.dot(rotation.get_rotation_quaternion()*frame.wheels[i].rotation)))
  max_wheel=maxf(max_wheel,current.wheels[i].angular_velocity.distance_to(rotation*frame.wheels[i].angular_velocity))
  if current.wheels[i].detached!=frame.wheels[i].detached:_fail(row,'wheel_discrete_'+str(index))
 var sample: Dictionary={'index':index,'body_position_error_m':max_body,'panel_position_error_m':max_panel,'velocity_error_mps':max_velocity,'reduced_pose_error':max_rigid,'glass_state_error':max_glass,'interior_state_error':max_interior,'wheel_state_error':max_wheel,'mass_kg':g.owned_mass_kg(),'solver_counts':_counters(g)}
 row.replay_samples.append(sample)
 if max_body>POSITION_EPS or max_panel>POSITION_EPS or max_rigid>POSITION_EPS:_fail(row,'registered_pose_'+str(index),sample)
 if max_velocity>SCALAR_EPS or max_glass>SCALAR_EPS or max_interior>SCALAR_EPS or max_wheel>SCALAR_EPS:_fail(row,'restored_state_'+str(index),sample)
 if absf(g.owned_mass_kg()-1210)>.001:_fail(row,'replay_owned_mass_'+str(index),g.owned_mass_kg())
 if not _counters(g).values().all(func(count):return count==0):_fail(row,'live_solvers_'+str(index),_counters(g))
func _audit(path: String) -> Dictionary:
 var began: int=Time.get_ticks_usec()
 var row: Dictionary={'path':path,'id':path.get_file().get_basename(),'failures':{},'pending':false,'replay_samples':[],'observed':{'glass':{},'glass_maximum_stage':0,'panels':{},'wheels':[],'maximum_body_pairwise_distance_change_m':0.,'airbag_deployed':false,'maximum_airbag_deployment':0.,'maximum_seat_plastic_angle_deg':0.}}
 var data: Dictionary=Clip.read(path)
 if data.is_empty():_fail(row,'readable_compressed_variant');row.pending=allow_incomplete;return row
 row.id=data.metadata.get('id',row.id);row['bytes']=FileAccess.get_file_as_bytes(path).size();row['metadata']=data.metadata.duplicate(true)
 # Large conditioned descriptors remain in the file, not this audit report.
 if row.metadata.has('conditioned'):row.metadata.conditioned={'chain_id':row.metadata.conditioned.chain_id,'step':row.metadata.conditioned.step}
 var mismatches: Dictionary=_hash_mismatches(data.metadata)
 if not mismatches.is_empty():_fail(row,'exact_source_hashes',mismatches)
 if data.metadata.get('panels_schema',0)!=1:_fail(row,'panels_schema_1')
 if allow_incomplete and (not mismatches.is_empty() or data.metadata.get('panels_schema',0)!=1):row.pending=true;return row
 if data.frames.size()!=301:_fail(row,'301_samples',data.frames.size())
 if data.frames.is_empty():return row
 var vehicle:=Vehicle.new();vehicle.setup('res://vehicles/niva.json',false)
 var g: RefCounted=vehicle.solver;var maximum_mass_error:=0.;var donor_error:=0.
 for index in data.frames.size():
  var frame: Dictionary=data.frames[index]
  if not frame.has('panels') or not frame.has('mass_nodes') or not frame.has('effects') or not frame.effects.has_all(['glass','interior','surface']):_fail(row,'complete_snapshot_'+str(index));continue
  if frame.get('panels_schema',0)!=1 or frame.panels.panels.size()!=4 or frame.effects.glass.panes.size()!=6:_fail(row,'complete_component_schema_'+str(index));continue
  var bad: String=_finite(frame,'frame')
  if bad!='':_fail(row,'finite_snapshot_'+str(index),bad)
  var masses: PackedFloat32Array=g.rest_masses.duplicate();var owned:=0.
  for mass_ in frame.mass_nodes:
   owned+=mass_
   if mass_<=0:_fail(row,'positive_mass_nodes_'+str(index))
  for p in frame.panels.panels:
   var definition: Dictionary=g.panels.find(p.id)
   if p.active:
    owned+=definition.mass
    for node in definition.reservation:masses[node]-=float(definition.reservation[node])
  maximum_mass_error=maxf(maximum_mass_error,absf(owned-1210))
  var reported_mass: float=frame.panels.get('mass',NAN)
  if not is_finite(reported_mass):_fail(row,'finite_reported_mass_'+str(index))
  else:maximum_mass_error=maxf(maximum_mass_error,absf(reported_mass-1210))
  if frame.mass_nodes.size()!=masses.size():_fail(row,'mass_node_count_'+str(index))
  else:
   for i in masses.size():donor_error=maxf(donor_error,absf(masses[i]-frame.mass_nodes[i]))
  _observe(row,frame,data.frames[0],g)
 row['maximum_owned_mass_error_kg']=maximum_mass_error;row['maximum_mass_donor_error_kg']=donor_error
 if maximum_mass_error>.001 or donor_error>.001:_fail(row,'single_owned_mass',{'total_error':maximum_mass_error,'donor_error':donor_error})
 if row.failures.is_empty():
  for index in [0,150,300]:_apply_check(row,data,index,g)
 row['audit_cpu_ms']=(Time.get_ticks_usec()-began)/1000.
 return row
func _run() -> void:
 var explicit_count:=false
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with('--directory='):directory=arg.trim_prefix('--directory=')
  if arg.begins_with('--only='):only=arg.trim_prefix('--only=').split(',')
  if arg.begins_with('--expect-count='):expected_count=int(arg.trim_prefix('--expect-count='));explicit_count=true
  if arg=='--allow-incomplete':allow_incomplete=true
 if not only.is_empty() and not explicit_count:expected_count=-1
 var files: Array=_files(directory);var selected:=0;var audited:=0;var pending:=0;var failures:=0
 for path in files:
  if not only.is_empty() and path.get_file().get_basename() not in only:continue
  var row: Dictionary=_audit(path);selected+=1
  if seen_ids.has(row.id):_fail(row,'unique_clip_id',row.id)
  seen_ids[row.id]=true;records.append(row)
  if row.pending:pending+=1
  else:
   audited+=1
   if not row.failures.is_empty():failures+=1
  print('RECORDED_ASSET_AUDIT ',row.id,' ', 'PENDING' if row.pending else 'PASS' if row.failures.is_empty() else 'FAIL',' ',JSON.stringify(row.failures))
 var missing: Array=[]
 for id in only:
  if not seen_ids.has(id):missing.append(id)
 var complete: bool=pending==0 and (expected_count<0 or audited==expected_count) and missing.is_empty()
 var passed: bool=failures==0 and missing.is_empty() and (complete or allow_incomplete) and audited>0
 var report: Dictionary={'passed':passed,'complete':complete,'directory':directory,'only':only,'expected_count':expected_count,'discovered':files.size(),'selected':selected,'audited':audited,'pending':pending,'failed':failures,'missing_requested_ids':missing,'samples_per_clip':301,'registration_samples':[0,150,300],'registration_euler_rad':[.29,.73,-.21],'registration_origin_m':[41,3,-17],'position_tolerance_m':POSITION_EPS,'state_tolerance':SCALAR_EPS,'scope':'Read-only compressed-disk/all-frame physical-state and mass audit; full3D replay at three exact sample times. Outcomes are observations, not required crash damage. Surface.last_change=-INF is its documented no-contact clock sentinel. No live solves or bake/source writes.','records':records}
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
 FileAccess.open(OUTPUT,FileAccess.WRITE).store_string(JSON.stringify(report,'  '))
 print('RECORDED_BANK_AUDIT ',passed,' complete=',complete,' audited=',audited,' pending=',pending,' failed=',failures,' report=',OUTPUT)
 quit(0 if passed else 1)
