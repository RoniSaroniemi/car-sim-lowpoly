extends RefCounted
## Damage-conditioned clip selection. This module never steps a physics solver.
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Grid=preload('res://scripts/impact_zone_grid.gd')
const DIRECTORY='res://bakes/conditioned'
const BODY_SHAPE_TOLERANCE_M=.025
const ATTACHED_WHEEL_TOLERANCE_M=.15
const LENGTH_TOLERANCE=0.00002
const DAMAGE_TOLERANCE=0.000002

static func digest(value: Variant) -> String:
 var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256)
 context.update(var_to_bytes(value));return context.finish().hex_encode()

static func effects_owner(graph: RefCounted) -> RefCounted:
 for property in graph.get_property_list():
  if str(property.name)=='effects':return graph.get('effects')
 return null

static func capture(graph: RefCounted) -> Dictionary:
 var state: Dictionary=graph.capture()
 var effects: RefCounted=effects_owner(graph)
 if not state.has('effects') and effects!=null:state['effects']=effects.capture()
 return state

static func core_frame(points: PackedVector3Array) -> Transform3D:
 # The supported family is frontal Niva damage; rear lower rails are its datum.
 var x: Vector3=(points[8]+points[9]-points[0]-points[1]).normalized()
 var z: Vector3=(points[1]+points[5]+points[9]-points[0]-points[4]-points[8]).normalized()
 z=(z-x*x.dot(z)).normalized()
 if x.length()<.5 or z.length()<.5:return Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO)
 return Transform3D(Basis(x,z.cross(x).normalized(),x.cross(z.cross(x)).normalized()),(points[4]+points[5])*.5)

static func _effect_transient(key: String) -> bool:
 key=key.to_lower()
 if key in ['time','time_s','clock','elapsed','elapsed_s','age','age_s','t','dt','tick','ticks','positions','points','node_positions','previous','previous_positions','velocities','node_velocities','angular_velocity','rotation','rotations','frame','mount_frame','anchor_frame','world_transform','pose','angle','angles','theta','omega','angular_speed','event_time','trigger_time','deployment','particles','debris','particle_positions','emission_cursor','playback','paused','recording','live_steps','playback_steps','simulation_steps','solver_steps','cpu_ms','cpu_us']:return true
 return key.begins_with('last_') or key.ends_with('_cpu_us') or key.ends_with('_cpu_ms') or key.ends_with('_clock')

static func irreversible_effects(value: Variant,key: String='') -> Variant:
 if _effect_transient(key):return null
 if value is Dictionary:
  var result: Dictionary={};var keys: Array=value.keys();keys.sort()
  for child in keys:
   var item: Variant=irreversible_effects(value[child],str(child))
   if item!=null:result[str(child)]=item
  return result
 if value is Array:
  var result: Array=[]
  for item in value:
   var pruned: Variant=irreversible_effects(item,key)
   if pruned!=null:result.append(pruned)
  return result
 if value is PackedVector2Array or value is PackedVector3Array or value is PackedVector4Array:return null
 if value is Vector2 or value is Vector3 or value is Quaternion or value is Basis or value is Transform3D:return null
 if value is float:return snappedf(value,.000001)
 if value is PackedFloat32Array or value is PackedFloat64Array:
  if not ('plastic' in key or 'damage' in key or 'strain' in key):return null
  var result: Array=[]
  for item in value:result.append(snappedf(item,.000001))
  return result
 return value

static func _material_key(graph: RefCounted) -> String:
 var links: Array=[]
 for link in graph.links:links.append([link.a,link.b,link.original,link.stiffness_n_per_m,link.yield_n,link.max_compression,link.max_extension,link.damping_ns_per_m])
 return digest({'profile':graph.config.get('material_profile','legacy_front_bench'),'profile_version':graph.config.get('material_profile_version',0),'mass_kg':graph.config.mass_kg,'rest':graph.rest,'links':links,'hardening':graph.hardening,'wheel_profiles':graph.config.wheel_assemblies})

static func detached_wheel_indices(graph: RefCounted) -> PackedInt32Array:
 var indices:=PackedInt32Array()
 for index in graph.wheels.wheels.size():
  if graph.wheels.wheels[index].detached:indices.append(index)
 return indices

static func detached_nodes(graph: RefCounted) -> PackedInt32Array:
 var nodes:=PackedInt32Array()
 for index in detached_wheel_indices(graph):nodes.append(graph.wheels.wheels[index].node)
 return nodes

static func describe(graph: RefCounted,frame: Dictionary={}) -> Dictionary:
 var state: Dictionary=capture(graph) if frame.is_empty() else frame
 var transform: Transform3D=core_frame(state.points)
 if absf(transform.basis.determinant())<.5:return {'version':1,'valid':false,'reason':'degenerate_rear_reference'}
 var inverse: Transform3D=transform.affine_inverse()
 var shape:=PackedVector3Array()
 for point in state.points:shape.append(inverse*point)
 var wheels: Array=[]
 for wheel in state.wheels:
  wheels.append({'detached':wheel.detached,'joint_broken':wheel.joint_broken,'lateral_rest':wheel.lateral_rest,'alignment':wheel.alignment})
 var effects: Variant=irreversible_effects(state.get('effects',{}))
 var descriptor: Dictionary={'version':1,'valid':true,'material_sha256':_material_key(graph),'shape':shape,'lengths':state.lengths.duplicate(),'damage':state.damage.duplicate(),'link_damage':state.link_damage.duplicate(),'broken':state.broken.duplicate(),'wheels':wheels,'effects':effects,'effects_sha256':digest(effects)}
 # A diagnostic/cache key. Compatibility uses measured residuals, not hash equality.
 descriptor['state_key']=digest({'material':descriptor.material_sha256,'lengths':descriptor.lengths,'damage':descriptor.damage,'links':descriptor.link_damage,'broken':descriptor.broken,'wheels':wheels,'effects':descriptor.effects_sha256})
 return descriptor

static func stamp(clip: Dictionary,initial_snapshot: Dictionary,graph: RefCounted,chain_id: String='front_60_60_120',step: int=0) -> void:
 var initial: Dictionary=clip.frames[0] if initial_snapshot.is_empty() else initial_snapshot
 clip.metadata['conditioned']={'version':1,'chain_id':chain_id,'step':step,'from_state':describe(graph,initial),'to_state':describe(graph,clip.frames[-1]),'body_shape_tolerance_m':BODY_SHAPE_TOLERANCE_M,'attached_wheel_tolerance_m':ATTACHED_WHEEL_TOLERANCE_M,'length_tolerance':LENGTH_TOLERANCE,'damage_tolerance':DAMAGE_TOLERANCE}

static func _compatible_descriptors(graph: RefCounted,actual: Dictionary,expected: Dictionary,limits: Dictionary) -> Dictionary:
 var result: Dictionary={'accepted':false,'reason':'incompatible_state','shape_max_m':INF,'attached_wheel_max_m':INF,'length_error':INF,'damage_error':INF}
 if not actual.get('valid',false) or not expected.get('valid',false):result.reason='invalid_state_descriptor';return result
 if actual.material_sha256!=expected.material_sha256:result.reason='material_profile';return result
 if actual.shape.size()!=expected.shape.size() or actual.lengths.size()!=expected.lengths.size():result.reason='topology';return result
 if actual.broken!=expected.broken:result.reason='broken_links';return result
 if actual.wheels.size()!=expected.wheels.size():result.reason='wheel_count';return result
 for index in actual.wheels.size():
  var a: Dictionary=actual.wheels[index];var b: Dictionary=expected.wheels[index]
  if a.detached!=b.detached or a.joint_broken!=b.joint_broken:result.reason='wheel_attachment';return result
  if absf(a.lateral_rest-b.lateral_rest)>.0001 or a.alignment.distance_to(b.alignment)>.0001:result.reason='permanent_wheel_alignment';return result
 if actual.effects_sha256!=expected.effects_sha256:result.reason='irreversible_effects';return result
 var body:=0.0;var wheel:=0.0;var lengths:=0.0;var damage:=0.0
 for index in actual.shape.size():
  if graph.wheels.by_node.has(index):
   var wheel_index: int=graph.wheels.by_node[index]
   if not actual.wheels[wheel_index].detached:wheel=maxf(wheel,actual.shape[index].distance_to(expected.shape[index]))
  else:body=maxf(body,actual.shape[index].distance_to(expected.shape[index]))
  damage=maxf(damage,absf(actual.damage[index]-expected.damage[index]))
 for index in actual.lengths.size():
  lengths=maxf(lengths,absf(actual.lengths[index]-expected.lengths[index])/maxf(.001,graph.links[index].original))
  damage=maxf(damage,absf(actual.link_damage[index]-expected.link_damage[index]))
 result.shape_max_m=body;result.attached_wheel_max_m=wheel;result.length_error=lengths;result.damage_error=damage
 if body>float(limits.get('body_shape_tolerance_m',BODY_SHAPE_TOLERANCE_M)):result.reason='body_shape';return result
 if wheel>float(limits.get('attached_wheel_tolerance_m',ATTACHED_WHEEL_TOLERANCE_M)):result.reason='attached_wheel_pose';return result
 if lengths>float(limits.get('length_tolerance',LENGTH_TOLERANCE)):result.reason='plastic_lengths';return result
 if damage>float(limits.get('damage_tolerance',DAMAGE_TOLERANCE)):result.reason='irreversible_damage';return result
 result.accepted=true;result.reason='conditioned_state_matched';return result

static func compatible(graph: RefCounted,clip: Dictionary,current_snapshot: Dictionary={}) -> Dictionary:
 if not clip.metadata.has('conditioned'):return {'accepted':false,'reason':'not_a_conditioned_transition'}
 var transition: Dictionary=clip.metadata.conditioned
 if transition.get('version',0)!=1:return {'accepted':false,'reason':'conditioned_version'}
 return _compatible_descriptors(graph,describe(graph,current_snapshot),transition.from_state,transition)

static func choose(graph: RefCounted,signature: Dictionary,library: Array,current_snapshot: Dictionary={}) -> Dictionary:
 var best: Dictionary={'accepted':false,'reason':'no_compatible_conditioned_transition','index':-1,'score':0.0,'candidates':[]}
 if signature.is_empty():return best
 var actual: Dictionary=describe(graph,current_snapshot)
 var supported: Array=[];var nearest:=INF
 var speed: float=float(signature.closing_speed_mps)*3.6
 if speed<35 or speed>175:return best
 for index in library.size():
  var clip: Dictionary=library[index]
  if not clip.metadata.has('conditioned'):continue
  if clip.metadata.conditioned.get('version',0)!=1:
   best.candidates.append({'id':clip.metadata.id,'index':index,'accepted':false,'reason':'conditioned_version'});continue
  var state: Dictionary=_compatible_descriptors(graph,actual,clip.metadata.conditioned.from_state,clip.metadata.conditioned)
  if not state.accepted:
   best.candidates.append({'id':clip.metadata.id,'index':index,'accepted':false,'reason':state.reason});continue
  var speed_ratio: float=speed/maxf(.001,float(clip.metadata.speed_kmh))
  if speed_ratio<.85 or speed_ratio>1.15:
   best.candidates.append({'id':clip.metadata.id,'index':index,'accepted':false,'reason':'conditioned_speed_not_covered'});continue
  supported.append({'index':index,'state':state})
  nearest=minf(nearest,absf(float(clip.metadata.speed_kmh)-speed))
 var grid:=Grid.new()
 for item in supported:
  var index: int=item.index;var clip: Dictionary=library[index]
  if absf(float(clip.metadata.speed_kmh)-speed)>nearest+.0001:continue
  var normalized: Dictionary=signature.duplicate(true)
  normalized.incident_impulse_proxy_ns*=float(clip.metadata.speed_kmh)/speed
  var match_result: Dictionary=grid.match_signature(normalized,clip.metadata.signature)
  match_result['index']=index;match_result['id']=clip.metadata.id;match_result['state']=item.state
  match_result['actual_impact_kmh']=speed;match_result['recorded_speed_kmh']=clip.metadata.speed_kmh
  match_result['impulse_ratio']=speed/float(clip.metadata.speed_kmh)
  match_result['conditioned_chain']=clip.metadata.conditioned.chain_id;match_result['conditioned_step']=clip.metadata.conditioned.step
  best.candidates.append(match_result.duplicate(true))
  if match_result.accepted and (not best.accepted or match_result.score>best.score):
   var candidates: Array=best.candidates
   best=match_result.duplicate(true);best['candidates']=candidates
 return best

static func next_supported(graph: RefCounted,library: Array,current_snapshot: Dictionary={}) -> Dictionary:
 var actual: Dictionary=describe(graph,current_snapshot)
 var result: Dictionary={'accepted':false,'reason':'no_supported_next_state','index':-1}
 for index in library.size():
  var clip: Dictionary=library[index]
  if not clip.metadata.has('conditioned') or clip.metadata.conditioned.get('version',0)!=1:continue
  var match_result: Dictionary=_compatible_descriptors(graph,actual,clip.metadata.conditioned.from_state,clip.metadata.conditioned)
  if match_result.accepted and (not result.accepted or int(clip.metadata.conditioned.step)<int(result.step)):
   result={'accepted':true,'reason':'supported_fixture','index':index,'id':clip.metadata.id,'speed':clip.metadata.speed_kmh,'angle':clip.metadata.heading_deg,'chain':clip.metadata.conditioned.chain_id,'step':clip.metadata.conditioned.step}
 return result

static func irreversible_floor(graph: RefCounted,state: Dictionary) -> void:
 for index in graph.node_damage.size():graph.node_damage[index]=maxf(graph.node_damage[index],state.damage[index])
 for index in graph.links.size():
  graph.links[index].damage=maxf(graph.links[index].damage,state.link_damage[index])
  graph.links[index].broken=graph.links[index].broken or bool(state.broken[index])
 graph.plastic_work=maxf(graph.plastic_work,float(state.plastic_work))
 for index in graph.wheels.wheels.size():
  if state.wheels[index].detached:graph.wheels.detach(graph.wheels.wheels[index],state.wheels[index].detach_reason)
  graph.wheels.wheels[index].joint_broken=graph.wheels.wheels[index].joint_broken or state.wheels[index].joint_broken

static func read_library(directory: String=DIRECTORY) -> Array:
 var clips: Array=[]
 var catalog_path: String=directory+'/catalog.json'
 if not FileAccess.file_exists(catalog_path):return clips
 var catalog: Variant=JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
 if not catalog is Dictionary or catalog.get('version',0)!=1:return clips
 for record in catalog.records:
  var clip: Dictionary=Clip.read(directory+'/'+str(record.file))
  if not clip.is_empty():clips.append(clip)
 return clips

static func save_library(clips: Array,directory: String=DIRECTORY) -> void:
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
 var records: Array=[]
 for clip in clips:
  var file_name: String=str(clip.metadata.id)+'.crashclip'
  var file:=FileAccess.open_compressed(directory+'/'+file_name,FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD)
  assert(file!=null);file.store_var(clip);file.close()
  var metadata: Dictionary=clip.metadata.duplicate(true)
  # Large state descriptors belong in compressed clips, not the human catalog.
  records.append({'id':metadata.id,'file':file_name,'speed_kmh':metadata.speed_kmh,'heading_deg':metadata.heading_deg,'chain':metadata.conditioned.chain_id,'step':metadata.conditioned.step,'from_key':metadata.conditioned.from_state.state_key,'to_key':metadata.conditioned.to_state.state_key})
 FileAccess.open(directory+'/catalog.json',FileAccess.WRITE).store_string(JSON.stringify({'version':1,'records':records},'\t'))
