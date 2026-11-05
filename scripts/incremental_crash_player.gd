extends RefCounted
## Add recorded local shape changes to the existing damaged, physical car.
## Root motion and wheel contacts remain owned by the lightweight runtime.
const RoofResponse=preload('res://scripts/roof_landing_response.gd')
const States=preload('res://scripts/conditioned_crash_transitions.gd')
var owner: WeakRef
var data: Dictionary={}
var time:=0.0
var state: String='REPLAY'
var full_steps:=0
var handoff_position_jump_m:=0.0
var handoff_velocity_jump_mps:=0.0
var pose_registration_error_m:=0.0
var replay_rotation:=Basis.IDENTITY
var applied:=PackedVector3Array()
var damage_before: Dictionary={}
var surface_before: Dictionary={}
var player_cpu_us:=0
var damage_scale:=1.0
var roof_overlay: Dictionary={}
var duration:=2.5
var damage_tethers: Array=[]
static func frame(points: PackedVector3Array) -> Transform3D:
 var x: Vector3=(points[12]+points[13]-points[4]-points[5]).normalized()
 var z: Vector3=points[5]-points[4];z=(z-x*x.dot(z)).normalized()
 return Transform3D(Basis(x,z.cross(x).normalized(),z).orthonormalized(),(points[4]+points[5]+points[12]+points[13])*.25)
static func prepare(g: RefCounted,raw: Dictionary) -> void:
 var clip: Dictionary=RoofResponse.prepare(g,raw) if raw.metadata.get('family','')=='roof_landing_floor' else raw
 if clip.has('_incremental_track'):return
 var first: Transform3D=frame(clip.frames[0].points)
 var reference:=PackedVector3Array()
 for point in clip.frames[0].points:reference.append(first.affine_inverse()*point)
 var track: Array=[]
 for saved in clip.frames:
  var current: Transform3D=frame(saved.points);var delta:=PackedVector3Array()
  for i in saved.points.size():delta.append(current.affine_inverse()*saved.points[i]-reference[i])
  track.append(delta)
 clip['_incremental_track']=track
func attach_live(vehicle: RefCounted,library: Array,_signature: Dictionary,selection: Dictionary) -> void:
 owner=weakref(vehicle);data=library[int(selection.index)]
 if data.metadata.get('family','')=='roof_landing_floor':data=RoofResponse.prepare(vehicle.solver,data)
 assert(data.has('_incremental_track'),'Prepare additive tracks at setup')
 time=0;state='REPLAY';applied.resize(vehicle.solver.points.size());applied.fill(Vector3.ZERO)
 damage_before=vehicle.solver.capture();surface_before=vehicle.solver.effects.surface.capture()
 damage_scale=float(selection.get('damage_scale',1))
 for i in vehicle.solver.links.size():
  var edge: Variant=vehicle.solver.links[i]
  if vehicle.solver.wheels.by_node.has(edge.a) or vehicle.solver.wheels.by_node.has(edge.b):continue
  if float(damage_before.lengths[i])<float(edge.original)-.005:
   damage_tethers.append({'a':edge.a,'b':edge.b,'maximum':vehicle.solver.points[edge.a].distance_to(vehicle.solver.points[edge.b])})
 duration=float(data.metadata.duration_s)
 vehicle.solver.compact_active=true;vehicle.compact.capture_shape()
func advance(dt: float) -> void:
 if state=='COMPLETE':return
 var began:=Time.get_ticks_usec();var vehicle: RefCounted=owner.get_ref();var g: RefCounted=vehicle.solver
 if roof_overlay.is_empty() and data.metadata.get('family','')!='roof_landing_floor':
  var roof_event: Dictionary=vehicle.roof_landing_sensor.event(vehicle,dt,vehicle.roof_landing_library)
  if not roof_event.is_empty():
   roof_overlay={'data':RoofResponse.prepare(g,vehicle.roof_landing_library[int(roof_event.selection.index)]),'start':time+float(roof_event.toi),'scale':float(roof_event.selection.get('damage_scale',1))}
   duration=maxf(duration,float(roof_overlay.start)+float(roof_overlay.data.metadata.duration_s))
   vehicle.baked_count+=1
   for edge in g.links:
    if g.wheels.by_node.has(edge.a) or g.wheels.by_node.has(edge.b):continue
    if float(edge.length)<float(edge.original)-.005:damage_tethers.append({'a':edge.a,'b':edge.b,'maximum':g.points[edge.a].distance_to(g.points[edge.b])})
   vehicle.last_bake['roof_overlay']={'id':roof_overlay.data.metadata.id,'time_s':time,'closing_speed_mps':roof_event.signature.closing_speed_mps,'roof_stiffness':roof_event.selection.roof_stiffness,'damage_scale':roof_overlay.scale}
   vehicle.impact_history.append({'id':roof_overlay.data.metadata.id,'contact_family':'roof_landing_floor','incremental':true,'overlay':true,'start_time_s':g.simulated_time,'parent_id':data.metadata.id,'roof_stiffness':roof_event.selection.roof_stiffness,'damage_scale':roof_overlay.scale})
   vehicle.world_impact_sensor.latches['terrain_body']=true
 vehicle._advance_incremental_root(dt)
 time=minf(time+dt,duration)
 var sample: float=clampf(time*float(data.metadata.sample_hz),0,data.frames.size()-1)
 var a:=floori(sample);var b:=mini(ceili(sample),data.frames.size()-1);var t: float=sample-a
 var current: Transform3D=frame(g.points);var track: Array=data._incremental_track
 var next:=PackedVector3Array();next.resize(g.points.size())
 for i in g.points.size():
  var target: Vector3=track[a][i].lerp(track[b][i],t)*damage_scale
  if not roof_overlay.is_empty():
   var roof_sample: float=clampf((time-float(roof_overlay.start))*120,0,roof_overlay.data.frames.size()-1)
   var ra:=floori(roof_sample);var rb:=mini(ceili(roof_sample),roof_overlay.data.frames.size()-1)
   target+=roof_overlay.data._incremental_track[ra][i].lerp(roof_overlay.data._incremental_track[rb][i],roof_sample-ra)*float(roof_overlay.scale)
  # Retain wheel physical ownership, rather than teleporting wheel centres.
  if g.wheels.by_node.has(i):continue
  var increment: Vector3=target-applied[i]
  # Bound individual control-point movement on a large, already folded shape.
  if increment.length()>.08:increment=increment.normalized()*.08
  var local: Vector3=current.affine_inverse()*g.points[i]
  var candidate: Vector3=local+increment
  if g.rest[i].y>1.15:candidate.y=minf(local.y,maxf(candidate.y,.12))
  g.points[i]=current*candidate;next[i]=applied[i]+(candidate-local)
  g.node_damage[i]=maxf(g.node_damage[i],float(data.frames[a].damage[i]))
 applied=next
 # New clips must not geometrically lengthen already crushed members. These
 # few old-damage envelopes project shape only; no force/XPBD solve is run.
 for iteration in 5:
  for tether in damage_tethers:
   var delta: Vector3=g.points[tether.b]-g.points[tether.a];var length: float=delta.length()
   if length<=float(tether.maximum)+.001:continue
   var correction: Vector3=delta*((length-float(tether.maximum))/maxf(.00001,length))
   var wa: float=g.inverse_masses[tether.a];var wb: float=g.inverse_masses[tether.b]
   g.points[tether.a]+=correction*wa/(wa+wb);g.points[tether.b]-=correction*wb/(wa+wb)
 for i in g.links.size():
  var edge: Variant=g.links[i]
  edge.damage=maxf(edge.damage,float(data.frames[a].link_damage[i]))
  edge.broken=edge.broken or bool(data.frames[a].broken[i])
  if g.wheels.by_node.has(edge.a) or g.wheels.by_node.has(edge.b):continue
  var recorded_change: float=(data.frames[a].lengths[i]-data.frames[0].lengths[i])*damage_scale
  var wanted: float=damage_before.lengths[i]+recorded_change
  if recorded_change<0:edge.length=minf(edge.length,maxf(.02,wanted))
  else:edge.length=maxf(edge.length,wanted)
 g.plastic_work=maxf(g.plastic_work,float(damage_before.plastic_work)+maxf(0,float(data.frames[a].plastic_work)-float(data.frames[0].plastic_work)))
 States.irreversible_floor(g,damage_before)
 for i in g.wheels.wheels.size():
  if data.frames[a].wheels[i].detached and not g.wheels.wheels[i].detached:g.wheels.detach(g.wheels.wheels[i],'incremental_recorded_mount_failure')
 # Existing glass/interior damage remains owned and never reset by a new clip.
 # Scalar baked wear is accumulated; no membrane/cage/cloth solver is called.
 g.effects.surface.observe()
 g.effects.surface.retain(surface_before)
 var glass: Dictionary=g.effects.glass.capture();var changed:=false
 for id in glass.panes:
  var incoming: Dictionary=data.frames[a].effects.glass.panes.get(id,{})
  if int(incoming.get('stage',0))>int(glass.panes[id].stage):glass.panes[id]=incoming.duplicate(true);changed=true
 if changed:
  glass.time_s=g.effects.glass.clock
  g.effects.glass.restore_interpolated(glass,glass,0)
 var interior: Dictionary=g.effects.interior.capture();var incoming_interior: Dictionary=data.frames[a].effects.interior
 var interior_changed:=false
 for i in interior.seats.size():
  if float(incoming_interior.seats[i].plastic_work)>float(interior.seats[i].plastic_work):interior.seats[i]=incoming_interior.seats[i].duplicate(true);interior_changed=true
 if not damage_before.effects.interior.airbag.get('triggered',false) and incoming_interior.airbag.get('triggered',false):
  interior.airbag=incoming_interior.airbag.duplicate(true);interior.deployment_event_id=incoming_interior.deployment_event_id;interior_changed=true
 if interior_changed:g.effects.interior.restore_interpolated(interior,interior,0)
 vehicle.compact.capture_shape();g.panels.synchronize_inactive()
 vehicle._rigid_body_contacts(maxf(.00001,dt));g.panels.synchronize_inactive()
 vehicle._fit_incremental_contacts()
 player_cpu_us+=Time.get_ticks_usec()-began
 if time>=duration-1e-8:state='COMPLETE'
