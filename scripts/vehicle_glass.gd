extends RefCounted
## Six real pane controllers. Glass is an authored cosmetic effect; car mass stays owned by graph.
const Attachment=preload('res://scripts/car_attachment.gd')
const Membrane=preload('res://scripts/glass_membrane.gd')
const Visual=preload('res://scripts/vehicle_glass_visual.gd')
const GRID_X=20
const GRID_Y=13
const DEBRIS_CAP=192
var graph: WeakRef
var settings: Dictionary={}
var profile: Dictionary={}
var panes: Dictionary={}
var debris: Array=[]
var clock:=0.0
var emitted: Dictionary={}
var playback_clock: float=-INF
var membrane_solve_steps:=0
var total_live_cpu_us:=0
var total_debris_cpu_us:=0
var collision_count:=0
var peak_debris:=0
var profile_id: String=''
var live_accumulator:=0.0

func setup(owner: RefCounted,options: Dictionary={}) -> void:
 graph=weakref(owner);settings=options.duplicate(true)
 var path: String=settings.get('profile','res://vehicles/niva_glass.json')
 profile=JSON.parse_string(FileAccess.get_file_as_string(path));profile_id=profile.id
 for raw in profile.panes:
  var u:=_v3(raw.u_axis);var v:=_v3(raw.v_axis);var n:=_v3(raw.normal)
  var bounds: Array=raw.uv_bounds
  var origin: Vector3=_v3(raw.origin)+u*(float(bounds[0])+float(bounds[1]))*.5+v*(float(bounds[2])+float(bounds[3]))*.5
  var pane: Dictionary={'raw':raw,'rest_frame':Transform3D(Basis(u,v,n),origin),'node_rest':PackedVector3Array(),'node_bind':[],'last_corners':PackedVector3Array(),'last_velocity':Vector3.ZERO}
  for y in Membrane.NY+1:
   for x in Membrane.NX+1:
    var p: Vector3=_rest_at(pane,Vector2(float(x)/Membrane.NX,float(y)/Membrane.NY))
    pane.node_rest.append(p);pane.node_bind.append(Attachment.binding(owner,p))
  panes[raw.id]=pane
 reset()

static func _v3(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
func _rest_at(pane: Dictionary,uv: Vector2) -> Vector3:
 var raw: Dictionary=pane.raw
 var bounds: Array=raw.uv_bounds
 return _v3(raw.origin)+_v3(raw.u_axis)*lerpf(bounds[0],bounds[1],uv.x)+_v3(raw.v_axis)*lerpf(bounds[2],bounds[3],uv.y)
func _frame(pane: Dictionary,frames: Array) -> Transform3D:
 var g: RefCounted=graph.get_ref()
 var rest_frame: Transform3D=pane.rest_frame
 var current: Transform3D=Attachment.frame_with_rotations(g,rest_frame.origin,frames)
 return Transform3D(current.basis*rest_frame.basis,current.origin)
func _node_world(pane: Dictionary,frames: Array) -> PackedVector3Array:
 var result:=PackedVector3Array();var g: RefCounted=graph.get_ref()
 for i in pane.node_rest.size():result.append(Attachment.mapped(g,pane.node_rest[i],pane.node_bind[i],frames))
 return result
func _corner_world(pane: Dictionary,frames: Array) -> PackedVector3Array:
 var result:=PackedVector3Array();var g: RefCounted=graph.get_ref()
 for i in [0,Membrane.NX,Membrane.NY*(Membrane.NX+1),pane.node_rest.size()-1]:result.append(Attachment.mapped(g,pane.node_rest[i],pane.node_bind[i],frames))
 return result
func _body_velocity(pane: Dictionary) -> Vector3:
 var g: RefCounted=graph.get_ref();var bind: Dictionary=Attachment.binding(g,pane.rest_frame.origin)
 var result:=Vector3.ZERO
 for i in bind.ids.size():result+=g.velocities[bind.ids[i]]*bind.weights[i]
 return result

func reset() -> void:
 debris.clear();emitted.clear();clock=0;live_accumulator=0;playback_clock=-INF
 membrane_solve_steps=0;total_live_cpu_us=0;total_debris_cpu_us=0;collision_count=0;peak_debris=0
 for id in panes:
  var pane: Dictionary=panes[id]
  pane.stage=0;pane.crack=0.0;pane.seed=1009+panes.keys().find(id)*127;pane.generation=0
  pane.hit_uv=Vector2(.5,.5);pane.mask=PackedByteArray();pane.mask.resize(GRID_X*GRID_Y*2);pane.mask.fill(1)
  pane.nodes_local=PackedVector3Array();pane.vel_local=PackedVector3Array();pane.broken=PackedByteArray();pane.released=PackedByteArray()
  pane.events=[];pane.membrane=null;pane.release_cursor=0;pane.last_tear_count=-1;pane.last_released_count=-1;pane.mask_revision=0
 synchronize()
func synchronize() -> void:
 live_accumulator=0
 var g: RefCounted=graph.get_ref()
 if g==null:return
 var frames: Array=Attachment.rotations(g)
 for pane in panes.values():
  var all: PackedVector3Array=_node_world(pane,frames)
  pane.last_corners=PackedVector3Array([all[0],all[Membrane.NX],all[Membrane.NY*(Membrane.NX+1)],all[-1]])
  pane.last_velocity=_body_velocity(pane)

func _frame_strain(pane: Dictionary,points: PackedVector3Array) -> float:
 var corners: Array=[0,Membrane.NX,Membrane.NY*(Membrane.NX+1),pane.node_rest.size()-1]
 var pairs: Array=[[0,1],[2,3],[0,2],[1,3],[0,3],[1,2]]
 var strain:=0.0
 for pair in pairs:
  var a: int=corners[pair[0]];var b: int=corners[pair[1]]
  var rest_length: float=pane.node_rest[a].distance_to(pane.node_rest[b])
  var distance: float=points[pair[0]].distance_to(points[pair[1]]) if points.size()==4 else points[a].distance_to(points[b])
  strain=maxf(strain,absf(distance/maxf(.001,rest_length)-1))
 return strain

func hit_window(id: String,severity: float=1.0,piercing: bool=false,uv: Vector2=Vector2(.5,.5)) -> bool:
 if not panes.has(id):return false
 var g: RefCounted=graph.get_ref();var frames: Array=Attachment.rotations(g)
 var pane: Dictionary=panes[id]
 _hit(pane,clampf(severity,0,2),piercing,uv,frames,true)
 return true
func _hit(pane: Dictionary,severity: float,piercing: bool,uv: Vector2,frames: Array,tool: bool) -> void:
 pane.crack=maxf(pane.crack,clampf(severity/.6,0,1));pane.hit_uv=uv
 if severity<.15:return
 pane.generation=maxi(1,int(pane.generation));pane.stage=maxi(1,int(pane.stage))
 if pane.raw.material=='laminated':
  if pane.membrane==null:_start_membrane(pane,frames,severity if tool else 0,piercing,uv)
  elif tool:pane.membrane.load_again(severity,piercing,uv)
 else:
  if severity<.4:return
  var partial: bool=bool(pane.raw.settings.get('film_retention',false)) and severity<1.05
  _temper_mask(pane,uv,partial)
  pane.stage=3 if partial else 4
  var event_id: String='%s:%d:tempered'%[pane.raw.id,pane.generation]
  if not pane.events.any(func(event):return event.id==event_id):
   var frame: Transform3D=_frame(pane,frames)
   var event: Dictionary={'id':event_id,'time':clock,'kind':'tempered','seed':pane.seed,'uv':uv,'velocity_local':frame.basis.inverse()*pane.last_velocity}
   pane.events.append(event);_emit(pane,event,frames)

func _start_membrane(pane: Dictionary,frames: Array,severity: float,piercing: bool,uv: Vector2) -> void:
 var transform: Transform3D=_frame(pane,frames)
 var targets: PackedVector3Array=_node_world(pane,frames)
 var membrane:=Membrane.new()
 membrane.setup_pane(pane.raw.width_m,pane.raw.height_m,transform,targets,pane.last_velocity,severity,piercing,uv,pane.seed)
 if pane.nodes_local.size()==membrane.points.size():
  for i in membrane.points.size():
   membrane.points[i]=transform*pane.nodes_local[i]
   if pane.vel_local.size()==membrane.points.size():membrane.velocity[i]=transform.basis*pane.vel_local[i]
  if pane.broken.size()==membrane.bonds.size():
   for i in membrane.bonds.size():membrane.bonds[i].broken=bool(pane.broken[i])
  if pane.released.size()==membrane.released.size():membrane.released=pane.released.duplicate()
 pane.membrane=membrane
 pane.last_tear_count=-1;pane.last_released_count=-1

func step_live(dt: float) -> void:
 clock+=dt;live_accumulator+=dt;playback_clock=-INF
 if live_accumulator+1e-10<1.0/120:return
 dt=live_accumulator;live_accumulator=0
 var began: int=Time.get_ticks_usec()
 var g: RefCounted=graph.get_ref()
 if g==null:return
 var frames: Array=Attachment.rotations(g)
 for pane in panes.values():
  var targets: PackedVector3Array=_node_world(pane,frames) if pane.membrane!=null else _corner_world(pane,frames)
  var strain: float=_frame_strain(pane,targets)
  var threshold: float=pane.raw.settings.get('crack_frame_strain',.015)
  if strain>threshold and pane.stage==0:_hit(pane,clampf(strain/threshold*.6,.6,1.8),false,Vector2(.5,.5),frames,false)
  if pane.membrane!=null:
   if targets.size()!=pane.node_rest.size():targets=_node_world(pane,frames)
   var membrane: RefCounted=pane.membrane
   membrane.attachment=_frame(pane,frames);membrane.boundary_targets=targets
   var previous_steps: int=membrane.solve_steps
   membrane.advance(dt);membrane_solve_steps+=membrane.solve_steps-previous_steps
   _cache_membrane(pane,frames)
  pane.last_velocity=_body_velocity(pane)
 total_live_cpu_us+=Time.get_ticks_usec()-began
func _cache_membrane(pane: Dictionary,frames: Array) -> void:
 var m: RefCounted=pane.membrane;var attachment: Transform3D=_frame(pane,frames)
 var inverse: Transform3D=attachment.affine_inverse();pane.nodes_local=PackedVector3Array();pane.vel_local=PackedVector3Array()
 for i in m.points.size():pane.nodes_local.append(inverse*m.points[i]);pane.vel_local.append(attachment.basis.inverse()*m.velocity[i])
 pane.broken=PackedByteArray()
 for bond in m.bonds:pane.broken.append(1 if bond.broken else 0)
 pane.released=m.released.duplicate()
 var torn: int=m.broken_count();var released_count: int=Array(m.released).count(1)
 if torn!=pane.last_tear_count or released_count!=pane.last_released_count:
  var mask:=PackedByteArray();mask.resize(GRID_X*GRID_Y*2);mask.fill(1)
  for i in mask.size():
   var uv: Vector2=_cell_uv(i)
   if not _retained_rim(pane,uv):
    mask[i]=1 if m.visible(Vector3((uv.x-.5)*pane.raw.width_m,(uv.y-.5)*pane.raw.height_m,0)) else 0
  pane.mask=mask;pane.mask_revision+=1;pane.last_tear_count=torn;pane.last_released_count=released_count
 pane.stage=maxi(int(pane.stage),3 if torn>0 else 2)
 while pane.release_cursor<m.release_events.size():
  var source: Dictionary=m.release_events[pane.release_cursor]
  var event: Dictionary={'id':'%s:%d:patch:%d'%[pane.raw.id,pane.generation,pane.release_cursor],'time':clock,'kind':'laminate_patch','seed':pane.seed+pane.release_cursor,'position_local':inverse*source.position,'velocity_local':attachment.basis.inverse()*source.velocity,'size':source.size}
  pane.events.append(event);_emit(pane,event,frames);pane.release_cursor+=1;pane.stage=4

func _cell_uv(index: int) -> Vector2:
 var cell: int=index/2;var x: int=cell%GRID_X;var y: int=cell/GRID_X
 var offset: float=1.0/3 if index%2==0 else 2.0/3
 return Vector2((x+offset)/GRID_X,(y+offset)/GRID_Y)
func _retained_rim(pane: Dictionary,uv: Vector2) -> bool:
 var outline: Array=pane.raw.outline_uv
 var distance:=INF
 for i in outline.size():
  var a:=Vector2(outline[i][0],outline[i][1]);var b:=Vector2(outline[(i+1)%outline.size()][0],outline[(i+1)%outline.size()][1])
  var d: Vector2=b-a;var t: float=clampf((uv-a).dot(d)/maxf(.00001,d.length_squared()),0,1)
  distance=minf(distance,uv.distance_to(a+d*t))
 return distance<.025
func _temper_mask(pane: Dictionary,uv: Vector2,partial: bool) -> void:
 var mask: PackedByteArray=pane.mask.duplicate()
 for i in mask.size():
  var p: Vector2=_cell_uv(i)
  if not _retained_rim(pane,p) and (not partial or p.distance_to(uv)<.28):mask[i]=0
 pane.mask=mask;pane.mask_revision+=1

func _emit(pane: Dictionary,event: Dictionary,frames: Array) -> void:
 if emitted.has(event.id):return
 emitted[event.id]=true
 var transform: Transform3D=_frame(pane,frames)
 var rng:=RandomNumberGenerator.new();rng.seed=int(event.seed)
 if event.kind=='laminate_patch':
  _particle(transform*event.position_local,transform.basis*event.velocity_local,event.size,3.0,rng)
 else:
  var cells: Array=[]
  for i in pane.mask.size():
   if pane.mask[i]==0:cells.append(i)
  var count: int=mini(96,mini(DEBRIS_CAP-debris.size(),cells.size()))
  for j in count:
   var uv: Vector2=_cell_uv(cells[floori(float(j)*cells.size()/count)])
   var local: Vector3=Vector3((uv.x-.5)*pane.raw.width_m,(uv.y-.5)*pane.raw.height_m,.004)
   var velocity_local: Vector3=event.velocity_local+Vector3(rng.randf_range(-1,1),rng.randf_range(.2,1.8),rng.randf_range(.5,2.5))
   _particle(transform*local,transform.basis*velocity_local,rng.randf_range(.008,.018),rng.randf_range(2.1,3.2),rng)
func _particle(position_: Vector3,velocity_: Vector3,size: float,life: float,rng: RandomNumberGenerator) -> void:
 if debris.size()>=DEBRIS_CAP:return
 debris.append({'position':position_,'velocity':velocity_,'rotation':Vector3(rng.randf()*TAU,rng.randf()*TAU,rng.randf()*TAU),'spin':Vector3(rng.randf_range(-4,4),rng.randf_range(-4,4),rng.randf_range(-4,4)),'size':size,'life':life})
 peak_debris=maxi(peak_debris,debris.size())
func step_debris(dt: float) -> void:
 var began: int=Time.get_ticks_usec();var g: RefCounted=graph.get_ref()
 if g==null:return
 for piece in debris:
  piece.life-=dt;piece.velocity.y-=9.81*dt;piece.position+=piece.velocity*dt;piece.rotation+=piece.spin*dt
  var floor_: Vector4=g.floor_sample(piece.position)
  if piece.position.y-piece.size<floor_.w:
   piece.position.y=floor_.w+piece.size
   if piece.velocity.y<0:piece.velocity.y*=-.2;piece.velocity.x*=.75;piece.velocity.z*=.75;collision_count+=1
  if g.barrier_enabled:
   var hit: Dictionary=g.barrier_distance(piece.position)
   if hit.distance<piece.size:
    piece.position+=hit.normal*(piece.size-hit.distance)
    var inward: float=piece.velocity.dot(hit.normal)
    if inward<0:piece.velocity-=hit.normal*inward*1.2;collision_count+=1
 debris=debris.filter(func(piece):return piece.life>0)
 total_debris_cpu_us+=Time.get_ticks_usec()-began

func capture() -> Dictionary:
 var states: Dictionary={}
 for id in panes:
  var p: Dictionary=panes[id]
  states[id]={'material':p.raw.material,'stage':p.stage,'crack':p.crack,'seed':p.seed,'generation':p.generation,'hit_uv':p.hit_uv,'mask':p.mask.duplicate(),'nodes':p.nodes_local.duplicate(),'velocities':p.vel_local.duplicate(),'broken':p.broken.duplicate(),'released':p.released.duplicate(),'events':p.events.duplicate(true)}
 return {'version':1,'profile_id':profile_id,'time_s':clock,'panes':states}
func begin_playback(initial_state: Dictionary) -> void:
 reset()
 _restore(initial_state,initial_state,0,false)
 for pane in panes.values():
  for event in pane.events:emitted[event.id]=true
 playback_clock=clock
func restore_interpolated(a: Dictionary,b: Dictionary,alpha: float) -> void:
 var time: float=lerpf(float(a.get('time_s',0)),float(b.get('time_s',0)),alpha)
 var backwards: bool=time<playback_clock-1e-8
 if backwards:
  debris.clear();emitted.clear()
  _restore(a,b,alpha,false)
  for pane in panes.values():
   for event in pane.events:emitted[event.id]=true
 else:_restore(a,b,alpha,true)
 playback_clock=time
func _restore(a: Dictionary,b: Dictionary,alpha: float,emit_new: bool) -> void:
 clock=lerpf(float(a.get('time_s',0)),float(b.get('time_s',0)),alpha)
 var frames: Array=Attachment.rotations(graph.get_ref())
 for id in panes:
  var pane: Dictionary=panes[id]
  if not a.get('panes',{}).has(id):continue
  var source: Dictionary=a.panes[id];var target: Dictionary=b.get('panes',{}).get(id,source)
  pane.membrane=null
  for key in ['stage','crack','seed','generation','hit_uv']:pane[key]=source.get(key,pane[key])
  var changed: bool=pane.mask!=source.get('mask',pane.mask)
  for key in ['mask','broken','released']:pane[key]=source.get(key,pane[key]).duplicate()
  pane.nodes_local=source.get('nodes',PackedVector3Array()).duplicate();pane.vel_local=source.get('velocities',PackedVector3Array()).duplicate()
  if pane.nodes_local.size()==target.get('nodes',[]).size():
   for i in pane.nodes_local.size():pane.nodes_local[i]=pane.nodes_local[i].lerp(target.nodes[i],alpha)
  pane.events=source.get('events',[]).duplicate(true)
  if changed:pane.mask_revision+=1
  if emit_new:
   for event in pane.events:_emit(pane,event,frames)
func create_visual(skin_view: Node3D,model_root: Node3D) -> Node3D:
 var node:=Node3D.new();node.set_script(Visual);node.setup(self,skin_view,model_root)
 return node
func statistics() -> Dictionary:
 return {'membrane_solve_steps':membrane_solve_steps,'live_cpu_ms':total_live_cpu_us/1000.0,'debris_cpu_ms':total_debris_cpu_us/1000.0,'debris_count':debris.size(),'peak_debris':peak_debris,'particle_cap':DEBRIS_CAP,'collision_count':collision_count,'emitted_events':emitted.size()}

func input_fingerprints() -> Dictionary:
 var result: Dictionary={}
 for path in ['scripts/vehicle_glass.gd','scripts/glass_membrane.gd','scripts/car_attachment.gd','scripts/vehicle_glass_visual.gd','scripts/vehicle_glass.gdshader','vehicles/niva_glass.json','assets/Niva_2121_LOD0.glb']:
  result[path]=FileAccess.get_sha256('res://'+path)
 return result
