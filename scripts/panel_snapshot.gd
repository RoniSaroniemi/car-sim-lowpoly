extends RefCounted
## World fields are registered once. Rest bindings, plastic rest axes and rigid
## offsets/inertia remain in their recorded component reference frame.
const SCHEMA=1
static func transformed(source: Dictionary,rotation: Basis,translation: Vector3) -> Dictionary:
 var state: Dictionary=source.duplicate(true)
 var q: Quaternion=rotation.get_rotation_quaternion()
 for p in state.get('panels',[]):
  for i in p.points.size():p.points[i]=rotation*p.points[i]+translation;p.velocity[i]=rotation*p.velocity[i]
  if p.has('reduced_data'):
   var d: Dictionary=p.reduced_data
   d.center=rotation*d.center+translation;d.rotation=(q*d.rotation).normalized()
   for field in ['linear','omega','old_mount_velocity']:
    if d.has(field):d[field]=rotation*d[field]
  if p.has('impact_evidence'):
   for field in ['normal','contact_normal']:
    if p.impact_evidence.has(field):p.impact_evidence[field]=rotation*p.impact_evidence[field]
 return state
static func interpolated(a: Dictionary,b: Dictionary,t: float) -> Dictionary:
 var state: Dictionary=a.duplicate(true)
 for index in state.get('panels',[]).size():
  var p: Dictionary=state.panels[index];var next: Dictionary=b.panels[index]
  for i in p.points.size():p.points[i]=p.points[i].lerp(next.points[i],t);p.velocity[i]=p.velocity[i].lerp(next.velocity[i],t)
  p.angle=lerp_angle(p.angle,next.angle,t)
  p.target=lerpf(p.target,next.target,t)
  # Ownership/failures/events sample a; no fractional reattachment or failure.
  if p.has('reduced_data') and next.has('reduced_data'):
   var d: Dictionary=p.reduced_data;var nd: Dictionary=next.reduced_data
   d.center=d.center.lerp(nd.center,t);d.rotation=d.rotation.slerp(nd.rotation,t).normalized()
   for field in ['linear','omega','old_mount_velocity']:
    if d.has(field) and nd.has(field):d[field]=d[field].lerp(nd[field],t)
 state.time=lerpf(a.time,b.time,t)
 return state
static func descriptor(snapshot: Dictionary,body_frame: Transform3D) -> Array:
 var result: Array=[]
 for p in snapshot.get('panels',[]):
  var inverse: Transform3D=body_frame.affine_inverse();var shape:=PackedVector3Array()
  if not p.detached:
   for point_ in p.points:shape.append(inverse*point_)
  result.append({'id':p.id,'profile':p.get('profile_id',''),'active':p.active,'detached':p.detached,'latched':p.latched,'closing':p.get('closing_engaged',false),'anchors':p.anchors.map(func(a):return a.broken),'seats':p.get('closing_supports',[]).map(func(s):return s.broken),'lengths':p.edges.map(func(e):return e.length),'damage':p.edges.map(func(e):return e.damage),'angular_rest':p.get('angular_mount',{}).get('rest_axis',Vector3.UP),'angular_torn':p.get('angular_mount',{}).get('torn',false),'shape':shape,'plastic_work':p.plastic_work})
 return result
static func compatible(actual: Array,expected: Array) -> String:
 if actual.size()!=expected.size():return 'panel_schema'
 for i in actual.size():
  var a: Dictionary=actual[i];var b: Dictionary=expected[i]
  for key in ['id','profile','detached','latched','closing','anchors','seats','angular_torn']:
   if a[key]!=b[key]:return 'panel_'+key
  # Canonical closed frozen/condensed and full cage use the same material shape;
  # runtime ownership is reconstructed once, not compared by transient mode.
  if absf(a.plastic_work-b.plastic_work)>.01:return 'panel_plastic_work'
  if a.angular_rest.distance_to(b.angular_rest)>.0001:return 'panel_angular_rest'
  for k in a.lengths.size():
   if absf(a.lengths[k]-b.lengths[k])>.00002 or absf(a.damage[k]-b.damage[k])>.000002:return 'panel_plastic_shape'
  if not a.detached:
   for k in a.shape.size():
    if a.shape[k].distance_to(b.shape[k])>.025:return 'panel_pose'
 return ''
static func retain_failures(system: RefCounted,previous: Dictionary) -> void:
 for old in previous.get('panels',[]):
  var p: Dictionary=system.find(old.id)
  p.plastic_work=maxf(p.plastic_work,old.plastic_work)
  for k in p.anchors.size():p.anchors[k].broken=p.anchors[k].broken or old.anchors[k].broken
  for k in p.get('closing_supports',[]).size():p.closing_supports[k].broken=p.closing_supports[k].broken or old.get('closing_supports',[])[k].broken
  if p.anchors[2].broken:p.latched=false
  var old_mount: Dictionary=old.get('angular_mount',{})
  if old_mount.get('plastic_rad',0)>p.get('angular_mount',{}).get('plastic_rad',0):
   p.angular_mount.rest_axis=old_mount.rest_axis;p.angular_mount.plastic_rad=old_mount.plastic_rad
  if old_mount.get('torn',false):p.angular_mount.torn=true
