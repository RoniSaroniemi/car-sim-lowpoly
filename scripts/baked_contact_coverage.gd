extends RefCounted
## Translation-independent finite-wall footprint. Clip matching owns no dynamics.
const Grid=preload('res://scripts/impact_zone_grid.gd')
const SCHEMA=1
const OVERLAP_TOLERANCE=.15
const INTERVAL_TOLERANCE=.16
static func _array(v: Vector3) -> Array:return [v.x,v.y,v.z]
static func _normal(signature: Dictionary) -> Vector3:
 var n: Array=signature.get('world_normal',[-1.0,0.0,0.0])
 return Vector3(n[0],n[1],n[2]).normalized()

static func describe(g: RefCounted,packet: Dictionary,signature: Dictionary) -> Dictionary:
 if signature.is_empty():return {'schema':SCHEMA,'valid':false,'reason':'empty_contact'}
 var normal: Vector3=_normal(signature)
 var body: Basis=Grid.new().body_basis(g)
 # +tangent follows the body's +Z (right) projected onto the wall face.
 # For the supported frontal 0±30° family, low tangent is body-left.
 var tangent: Vector3=body.z-normal*body.z.dot(normal)
 tangent.y=0
 if tangent.length()<.2:tangent=Vector3.UP.cross(normal)
 if tangent.length()<.2:return {'schema':SCHEMA,'valid':false,'reason':'vertical_face'}
 tangent=tangent.normalized()
 var low:=INF;var high:=-INF;var bottom:=INF;var top:=-INF
 var toi: float=packet.get('toi',0)
 for i in g.points.size():
  if g.wheels.by_node.has(i) and g.wheels.wheels[g.wheels.by_node[i]].detached:continue
  var point: Vector3=g.points[i]+g.velocities[i]*toi
  var radius: float=g.radii[i]
  low=minf(low,point.dot(tangent)-radius);high=maxf(high,point.dot(tangent)+radius)
  bottom=minf(bottom,point.y-radius);top=maxf(top,point.y+radius)
 if high-low<.1:return {'schema':SCHEMA,'valid':false,'reason':'degenerate_footprint'}
 var obstacle_low:=INF;var obstacle_high:=-INF
 for x in [g.barrier_min.x,g.barrier_max.x]:
  for z in [g.barrier_min.z,g.barrier_max.z]:
   var p:=Vector3(x,0,z)
   obstacle_low=minf(obstacle_low,p.dot(tangent));obstacle_high=maxf(obstacle_high,p.dot(tangent))
 var span: float=high-low
 var a: float=clampf((obstacle_low-low)/span,0,1)
 var b: float=clampf((obstacle_high-low)/span,0,1)
 var overlap: float=maxf(0,b-a)
 var clipped_left: bool=a>.005
 var clipped_right: bool=b<.995
 var side: String='both' if clipped_left and clipped_right else ('left' if clipped_left else ('right' if clipped_right else 'none'))
 var full_height: bool=top<=g.barrier_max.y+.02 and bottom>=g.barrier_min.y-.15
 var feature: String='end_face' if absf(normal.z)>.99 else ('front_face' if absf(normal.x)>.99 else 'corner')
 var anchor:=Vector3.ZERO
 for i in range(8,12):anchor+=(g.points[i]+g.velocities[i]*toi)*.25
 var centroid: Array=signature.get('contact_centroid_world',_array(anchor))
 var local_centroid: Vector3=body.transposed()*(Vector3(centroid[0],centroid[1],centroid[2])-anchor)
 return {'schema':SCHEMA,'valid':true,'source':'barrier_box','feature':feature,'edge_side':side,'overlap':overlap,'kept_interval':[a,b],'full_width':side=='none','full_height':full_height,'height_interval':[clampf((g.barrier_min.y-bottom)/maxf(.1,top-bottom),0,1),clampf((g.barrier_max.y-bottom)/maxf(.1,top-bottom),0,1)],'body_tangent_span_m':span,'normal_local':signature.normal,'tangent_local':_array(body.transposed()*tangent),'contact_centroid_local':_array(local_centroid),'wall_size_m':_array(g.barrier_max-g.barrier_min),'material_profile':g.config.get('material_profile','legacy'),'mass_kg':g.config.mass_kg,'node_count':g.points.size(),'wheel_count':g.wheels.wheels.size()}

static func compatible(actual: Dictionary,recorded: Dictionary={}) -> Dictionary:
 var result: Dictionary={'accepted':false,'reason':'coverage_missing'}
 if not actual.get('valid',false):result.reason=actual.get('reason','invalid_footprint');return result
 if actual.source!='barrier_box':result.reason='contact_source';return result
 if recorded.is_empty():
  # Historical recordings are full-wall only. Missing metadata is never
  # interpreted as permission to play a full crush against a tiny wall corner.
  result.accepted=actual.full_width and actual.full_height and actual.feature=='front_face'
  result.reason='legacy_full_wall' if result.accepted else 'no_partial_wall_recording'
  return result
 if int(recorded.get('schema',0))!=SCHEMA or recorded.get('source','')!='barrier_box':result.reason='coverage_schema';return result
 if not actual.full_height or not recorded.get('full_height',false):result.reason='no_short_wall_recording';return result
 if actual.feature=='end_face' or recorded.get('feature','')=='end_face':result.reason='no_end_face_recording';return result
 if actual.material_profile!=recorded.get('material_profile','') or absf(actual.mass_kg-float(recorded.get('mass_kg',0)))>.01 or actual.node_count!=int(recorded.get('node_count',0)) or actual.wheel_count!=int(recorded.get('wheel_count',0)):
  result.reason='coverage_profile';return result
 if actual.edge_side!=recorded.get('edge_side','none'):result.reason='clipped_side';return result
 var error: float=absf(actual.overlap-float(recorded.overlap))
 var interval: float=maxf(absf(actual.kept_interval[0]-recorded.kept_interval[0]),absf(actual.kept_interval[1]-recorded.kept_interval[1]))
 result['overlap_error']=error;result['interval_error']=interval
 if error>OVERLAP_TOLERANCE or interval>INTERVAL_TOLERANCE:result.reason='overlap_outside_bank';return result
 var span_ratio: float=actual.body_tangent_span_m/maxf(.01,float(recorded.body_tangent_span_m))
 if span_ratio<.65 or span_ratio>1.5:result.reason='footprint_scale';return result
 # Translation and the far-away end of a wide wall do not alter this one-edge
 # family; wall thickness does. The reviewed family is a roughly1m solid box.
 var depth_ratio: float=float(actual.wall_size_m[0])/maxf(.01,float(recorded.wall_size_m[0]))
 if depth_ratio<.5 or depth_ratio>2:result.reason='wall_thickness';return result
 result.accepted=true;result.reason='footprint_matched';result['score']=1-minf(1,error/OVERLAP_TOLERANCE)*.15
 return result

static func choose(signature: Dictionary,coverage: Dictionary,library: Array,actual_speed_kmh: float) -> Dictionary:
 var best: Dictionary={'accepted':false,'reason':'no_coverage_recording','index':-1,'score':0.0}
 var nearest:=0.0;var distance:=INF
 for clip in library:
  var delta: float=absf(float(clip.metadata.speed_kmh)-actual_speed_kmh)
  if delta<distance:distance=delta;nearest=float(clip.metadata.speed_kmh)
 var normalized: Dictionary=signature.duplicate(true)
 normalized.incident_impulse_proxy_ns*=nearest/maxf(.001,actual_speed_kmh)
 var grid:=Grid.new()
 for index in library.size():
  var clip: Dictionary=library[index]
  if not clip.get('_input_compatibility',{}).get('compatible',true):continue
  if float(clip.metadata.speed_kmh)!=nearest:continue
  var footprint: Dictionary=compatible(coverage,clip.metadata.get('contact_coverage',{}))
  if not footprint.accepted:continue
  var match_: Dictionary=grid.match_signature(normalized,clip.metadata.signature)
  if not match_.accepted:continue
  var score: float=match_.score*float(footprint.get('score',1))
  if not best.accepted or score>best.score:
   best=match_.duplicate();best.index=index;best.id=clip.metadata.id;best.score=score
   best['coverage']=coverage;best['recorded_coverage']=clip.metadata.get('contact_coverage',{})
   best['coverage_reason']=footprint.reason;best['actual_impact_kmh']=actual_speed_kmh;best['recorded_speed_kmh']=nearest
   best['impulse_ratio']=actual_speed_kmh/maxf(.001,nearest)
 return best
