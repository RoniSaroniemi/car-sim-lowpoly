extends RefCounted
## Shared arena wall / terrain impacts, independent of the test-wall axis.
const Ground=preload('res://scripts/ground_impact_geometry.gd')
const Geometry=preload('res://scripts/roof_landing_geometry.gd')
const Grid=preload('res://scripts/impact_zone_grid.gd')
var last_rejection: String=''
var latches: Dictionary={}
var checks:=0
func reset() -> void:latches.clear();last_rejection='';checks=0
func _static_gap(g: RefCounted,point: Vector3,radius: float) -> Dictionary:
 var hit: Dictionary=g.static_contact(point,radius)
 hit=hit.duplicate();hit.distance=float(hit.distance)-radius
 return hit
func event(vehicle: RefCounted,h: float,library: Array) -> Dictionary:
 checks+=1
 var g: RefCounted=vehicle.solver
 if vehicle.sequence_active:return {}
 var body_frame: Basis=Geometry.basis(g)
 var events: Array=[]
 var floor_risk:=false
 for i in [0,1,8,9,12,13,24,25,2,3,26,27]:
  var future: Vector3=g.points[i]+g.velocities[i]*h
  if Ground.gap(g,future,g.radii[i]).distance<.02:floor_risk=true;break
 var floor_packet: Dictionary=Ground.packet(vehicle,h,false) if floor_risk else {}
 if not floor_packet.is_empty() and not floor_packet.signature.first_contacts.all(func(p):return p.source=='wheel'):
  floor_packet['source']='terrain_body';events.append(floor_packet)
 var reach: float=3.5+vehicle.compact.linear_velocity.length()*h
 var nearby: Dictionary=g.static_contact(vehicle.compact.center,reach)
 if float(nearby.distance)<reach:
  g.panels.synchronize_inactive();var probes: Array=Geometry.probes(g)
  var earliest:=INF;var normal:=Vector3.ZERO;var point:=Vector3.ZERO;var source: String='none';var contacts: Array=[]
  for p in probes:
   if p.source=='wheel':continue
   var start: Dictionary=_static_gap(g,p.position,p.radius)
   var future: Dictionary=Ground.motion(vehicle,p,h)
   var ending: Dictionary=_static_gap(g,future.position,p.radius)
   if minf(float(start.distance),float(ending.distance))>.00001:continue
   if future.velocity.dot(ending.normal)>=-.1:continue
   var low:=0.;var high:=h
   if start.distance<=.00001:high=0
   else:
    for step in 12:
     var middle: float=(low+high)*.5
     if _static_gap(g,Ground.motion(vehicle,p,middle).position,p.radius).distance<=.000001:high=middle
     else:low=middle
   if high<earliest:
    earliest=high
    var m: Dictionary=Ground.motion(vehicle,p,high);var hit: Dictionary=_static_gap(g,m.position,p.radius)
    normal=hit.normal;point=m.position-normal*p.radius;source=hit.source
  if is_finite(earliest):
   var weights: Dictionary={};var total:=0.0;var speed_sum:=0.;var rest_centroid:=Vector3.ZERO
   for p in probes:
    if p.source=='wheel':continue
    var m: Dictionary=Ground.motion(vehicle,p,earliest)
    var hit: Dictionary=_static_gap(g,m.position,p.radius)
    if hit.distance>.035 or hit.normal.dot(normal)<.7:continue
    var id: int=Grid.new().zone(p.rest)
    weights[id]=float(weights.get(id,0))+p.mass;total+=p.mass
    speed_sum+=maxf(0,-m.velocity.dot(normal))*p.mass;rest_centroid+=p.rest*p.mass
   if total>0:
    var zones: Array=[]
    for id in weights:zones.append({'id':id,'weight':weights[id]/total})
    var local: Vector3=body_frame.transposed()*normal
    events.append({'toi':earliest,'source':source,'rigid_contact':true,'world_normal':normal,'world_point':point,'damage_center_local':rest_centroid/total,'signature':{'normal':[local.x,local.y,local.z],'world_normal':[normal.x,normal.y,normal.z],'closing_speed_mps':speed_sum/total,'zones':zones}})
 # A rejection never latches a voxel. Only a successful contact is held until
 # physical separation; the car can then hit the same target again.
 for key in latches.keys():
  var clear:=true
  for p in Geometry.probes(g):
   if p.source=='wheel':continue
   var distance: float=Ground.gap(g,p.position,p.radius).distance if key=='terrain_body' else float(_static_gap(g,p.position,p.radius).distance)
   if distance<.15:clear=false;break
  if clear:latches.erase(key)
 events.sort_custom(func(a,b):return a.toi<b.toi)
 for packet in events:
  var source: String=packet.source
  if source in latches:continue
  # Pristine finite test-wall contacts retain their authored footprint gates.
  if source=='barrier' and vehicle._is_pristine():continue
  var speed: float=packet.signature.closing_speed_mps
  if speed<1.5:continue
  var normal: Array=packet.signature.normal;var n:=Vector3(normal[0],normal[1],normal[2])
  var best: Dictionary={};var score:=-INF
  for i in library.size():
   var clip: Dictionary=library[i]
   if clip.metadata.has('contact_coverage') or not clip.get('_input_compatibility',{}).get('compatible',false):continue
   var sn: Array=clip.metadata.signature.normal
   var alignment: float=n.dot(Vector3(sn[0],sn[1],sn[2]))
   var severity: float=absf(log(maxf(.01,speed*3.6/float(clip.metadata.speed_kmh))))
   var candidate: float=alignment-.15*severity
   if candidate>score:
    score=candidate
    best={'accepted':true,'index':i,'id':clip.metadata.id,'library_kind':'world_incremental','incremental':true,'contact_family':source,'score':candidate,'actual_impact_kmh':speed*3.6,'recorded_speed_kmh':clip.metadata.speed_kmh,'damage_scale':clampf(speed*3.6/float(clip.metadata.speed_kmh),.15,1.5),'damage_center_local':packet.get('damage_center_local',Vector3.ZERO)}
  if best.is_empty():last_rejection='world_recordings_missing';continue
  latches[source]=true;packet.selection=best;packet['rigid_contact']=true
  return packet
 return {}
