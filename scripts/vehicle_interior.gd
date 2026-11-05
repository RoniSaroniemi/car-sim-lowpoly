extends RefCounted
## Cosmetic one-way seat/cloth response: never adds a second vehicle mass owner.
const Seat=preload('res://scripts/interior_seat.gd')
const Bag=preload('res://scripts/airbag_cloth.gd')
const Attachment=preload('res://scripts/car_attachment.gd')
const Visual=preload('res://scripts/vehicle_interior_visual.gd')
var graph: WeakRef
var config: Dictionary={}
var profile_path: String='res://vehicles/niva_interior.json'
var profile_id: String=''
var seats: Array=[]
var bag: RefCounted
var airbag_enabled:=true
var clock:=0.0
var event_time:=-1.0
var deployment_event_id:=0
var live_steps:=0
var cloth_steps:=0
var seat_steps:=0
var playback_updates:=0
var last_deceleration:=0.0
var delta_v_exposure:=0.0
var previous_velocity:=Vector3.ZERO
var previous_mount_velocity: Array=[]
var cloth_accumulator:=0.0
var playback:=false
var revision:=0

static func _vector(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
static func _merge(base: Dictionary,overrides: Dictionary) -> Dictionary:
 var result: Dictionary=base.duplicate(true)
 for key in overrides:
  if result.get(key) is Dictionary and overrides[key] is Dictionary:result[key]=_merge(result[key],overrides[key])
  else:result[key]=overrides[key]
 return result

func setup(owner: RefCounted,settings: Dictionary={}) -> void:
 graph=weakref(owner)
 var path: String=settings.get('profile_path','res://vehicles/niva_interior.json')
 profile_path=path
 var defaults: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
 config=_merge(defaults,settings)
 profile_id=str(config.id)+':'+JSON.stringify(config,'',true).sha256_text().left(12)
 airbag_enabled=bool(config.airbag.enabled)
 seats.clear()
 for item in config.seats:
  var seat:=Seat.new();seat.setup(item);seats.append(seat)
 bag=Bag.new();bag.setup(config.airbag)
 reset()

func reset() -> void:
 revision+=1
 for seat in seats:seat.reset()
 if bag!=null:bag.reset()
 clock=0;event_time=-1;deployment_event_id=0;delta_v_exposure=0;cloth_accumulator=0
 live_steps=0;cloth_steps=0;seat_steps=0;playback_updates=0;playback=false;last_deceleration=0
 synchronize()

func synchronize() -> void:
 var g: RefCounted=graph.get_ref()
 if g==null:return
 previous_velocity=_body_velocity(g)
 previous_mount_velocity.clear()
 for item in config.seats:previous_mount_velocity.append(_floor_velocity(_vector(item.mount)))
 cloth_accumulator=0

func _body_velocity(g: RefCounted) -> Vector3:
 var momentum:=Vector3.ZERO;var mass:=0.0
 for i in 28:momentum+=g.velocities[i]*g.masses[i];mass+=g.masses[i]
 return momentum/maxf(.001,mass)

func _floor_weights(p: Vector3) -> Dictionary:
 var g: RefCounted=graph.get_ref()
 var station:=0
 for i in 6:
  if p.x>=float(g.config.station_x[i]):station=i
 var t: float=clampf((p.x-float(g.config.station_x[station]))/float(g.config.station_x[station+1]-g.config.station_x[station]),0,1)
 var ids:=PackedInt32Array();var weights:=PackedFloat32Array()
 for q in 2:
  var s: int=station+q;var width: float=g.config.station_half_width[s]
  var z: float=clampf((p.z+width)/(2*width),0,1)
  for side in 2:ids.append(s*4+side);weights.append((t if q else 1-t)*(z if side else 1-z))
 return {'ids':ids,'weights':weights,'station':station,'t':t}

func _floor_velocity(p: Vector3) -> Vector3:
 var g: RefCounted=graph.get_ref();var bind: Dictionary=_floor_weights(p);var result:=Vector3.ZERO
 for j in bind.ids.size():result+=g.velocities[bind.ids[j]]*bind.weights[j]
 return result

func seat_mount(index: int) -> Transform3D:
 var g: RefCounted=graph.get_ref()
 var origin: Vector3=_vector(config.seats[index].mount)
 var bind: Dictionary=_floor_weights(origin)
 var mapped:=Vector3.ZERO
 for j in bind.ids.size():mapped+=g.points[bind.ids[j]]*bind.weights[j]
 var s: int=bind.station;var t: float=bind.t
 var a: Vector3=(g.points[s*4]+g.points[s*4+1])*.5
 var b: Vector3=(g.points[(s+1)*4]+g.points[(s+1)*4+1])*.5
 var x: Vector3=(b-a).normalized()
 var left: Vector3=g.points[s*4].lerp(g.points[(s+1)*4],t)
 var right: Vector3=g.points[s*4+1].lerp(g.points[(s+1)*4+1],t)
 var z: Vector3=(right-left).normalized();z=(z-x*x.dot(z)).normalized()
 var basis:=Basis.IDENTITY
 if x.length()>.1 and z.length()>.1:basis=Basis(x,z.cross(x).normalized(),x.cross(z.cross(x)).normalized())
 return Transform3D(basis,mapped-basis*origin)

func airbag_mount() -> Transform3D:
 var g: RefCounted=graph.get_ref()
 var local_hub: Vector3=_vector(config.airbag.hub)
 var frame: Transform3D=Attachment.frame(g,local_hub)
 var axis: Vector3=_vector(config.airbag.axis).normalized()
 var side:=Vector3.BACK;var up: Vector3=side.cross(axis).normalized();side=axis.cross(up).normalized()
 return frame*Transform3D(Basis(axis,up,side),Vector3.ZERO)

func _frontal_contact(forward: Vector3) -> bool:
 var g: RefCounted=graph.get_ref()
 for i in 28:
  if g.contact_wall[i] and -g.wall_normals[i].dot(forward)>.5:return true
 return false

func step_live(dt: float) -> void:
 var g: RefCounted=graph.get_ref()
 if g==null or dt<=0:return
 playback=false;clock+=dt;live_steps+=1;revision+=1
 var gravity:=Vector3.DOWN*float(g.config.gravity_mps2)
 var motion: Vector3=_body_velocity(g)
 var acceleration: Vector3=(motion-previous_velocity)/dt
 var forward: Vector3=seat_mount(0).basis.x
 var proper_deceleration: float=-(acceleration-gravity).dot(forward)
 last_deceleration=proper_deceleration
 var previous_forward_speed: float=previous_velocity.dot(forward)
 previous_velocity=motion
 for i in seats.size():
  var mount_velocity: Vector3=_floor_velocity(_vector(config.seats[i].mount))
  var mount_acceleration: Vector3=(mount_velocity-previous_mount_velocity[i])/dt
  var deceleration: float=clampf(-(mount_acceleration-gravity).dot(seat_mount(i).basis.x),-800,800)
  seats[i].step(dt,deceleration);seat_steps+=1;previous_mount_velocity[i]=mount_velocity
 var window: float=config.airbag.get('delta_v_window_s',.055)
 delta_v_exposure=delta_v_exposure*exp(-dt/window)+maxf(0,proper_deceleration)*dt
 var contact: bool=_frontal_contact(forward) or not bool(config.airbag.get('require_frontal_wall_contact',true))
 if airbag_enabled and not bag.triggered and contact and proper_deceleration>=float(config.airbag.minimum_deceleration_mps2) and delta_v_exposure>=float(config.airbag.minimum_delta_v_mps) and maxf(motion.dot(forward),previous_forward_speed)>=float(config.airbag.minimum_forward_speed_mps):
  bag.trigger();event_time=clock;deployment_event_id=1
 if airbag_enabled and bag.triggered:
  cloth_accumulator+=dt
  var relative: Vector3=airbag_mount().basis.transposed()*(gravity-acceleration)
  while cloth_accumulator>=1.0/240-1e-10:
   bag.step(1.0/240,relative);cloth_steps+=1;cloth_accumulator-=1.0/240

func step_debris(_dt: float) -> void:pass

func capture() -> Dictionary:
 var states: Array=[]
 for seat in seats:states.append(seat.capture())
 return {'version':1,'profile_id':profile_id,'clock':clock,'seats':states,'airbag':bag.capture(),'airbag_enabled':airbag_enabled,'deployment_event_id':deployment_event_id,'event_time':event_time}

func begin_playback(initial_state: Dictionary) -> void:
 playback=true
 restore_interpolated(initial_state,initial_state,0)

func restore_interpolated(a: Dictionary,b: Dictionary,alpha: float) -> void:
 playback=true;playback_updates+=1;revision+=1
 if a.is_empty():
  for seat in seats:seat.reset()
  bag.reset();clock=0;deployment_event_id=0;event_time=-1
  return
 clock=lerpf(a.get('clock',0),b.get('clock',a.get('clock',0)),alpha)
 var aa: Array=a.get('seats',[]);var bb: Array=b.get('seats',aa)
 for i in seats.size():
  var sa: Dictionary=aa[i] if i<aa.size() else {}
  var sb: Dictionary=bb[i] if i<bb.size() else sa
  seats[i].restore(sa,sb,alpha)
 bag.restore(a.get('airbag',{}),b.get('airbag',a.get('airbag',{})),alpha)
 var discrete: Dictionary=b if alpha>=1 else a
 deployment_event_id=discrete.get('deployment_event_id',0);event_time=discrete.get('event_time',-1)
 airbag_enabled=bool(discrete.get('airbag_enabled',airbag_enabled))

func input_fingerprints() -> Dictionary:
 var result: Dictionary={}
 for path in ['scripts/vehicle_interior.gd','scripts/interior_seat.gd','scripts/airbag_cloth.gd','scripts/interior_geometry.gd','scripts/vehicle_interior_visual.gd','scripts/car_attachment.gd']:
  result[path]=FileAccess.get_sha256('res://'+path)
 result[profile_path.trim_prefix('res://')]=FileAccess.get_sha256(profile_path)
 return result

func irreversible_state() -> Dictionary:
 var state: Array=[]
 for seat in seats:state.append({'id':seat.id,'plastic_angle':seat.plastic_angle,'plastic_work':seat.plastic_work})
 return {'profile_id':profile_id,'seats':state,'airbag_deployed':bag.triggered,'deployment_event_id':deployment_event_id}

func create_visual(skin_view: Node3D,model_root: Node3D) -> Node3D:
 var node:=Node3D.new();node.set_script(Visual);node.setup(self,skin_view,model_root);return node
