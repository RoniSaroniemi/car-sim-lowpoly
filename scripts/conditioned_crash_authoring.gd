extends RefCounted
## Offline conditioned transitions using the shared vehicle/effects and clip format.
const Vehicle=preload('res://scripts/vehicle_simulation.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const States=preload('res://scripts/conditioned_crash_transitions.gd')
const Grid=preload('res://scripts/impact_zone_grid.gd')
const CHAIN_ID='front_60_60_120'
const FOLLOWUPS=[{'speed':60.0,'angle':20.0},{'speed':120.0,'angle':-20.0}]

static func _is_detached(graph: RefCounted,index: int) -> bool:
 return graph.wheels.by_node.has(index) and graph.wheels.wheels[graph.wheels.by_node[index]].detached

static func prepare(graph: RefCounted,spec: Dictionary,wall_x: float=INF) -> Dictionary:
 # External fixture moves the attached car, not any released wheel. No repair.
 if not is_finite(wall_x):wall_x=graph.barrier_min.x
 var before: Dictionary=States.capture(graph)
 var center: Vector3=graph.station_center(2)
 var rotation: Basis=Basis(Vector3.UP,deg_to_rad(spec.angle))*Grid.new().body_basis(graph).transposed()
 for index in graph.points.size():
  if not _is_detached(graph,index):graph.points[index]=rotation*(graph.points[index]-center)
 for wheel in graph.wheels.wheels:
  if wheel.detached:continue
  wheel.rotation=(rotation.get_rotation_quaternion()*wheel.rotation).normalized()
  wheel.previous_rotation=wheel.rotation;wheel.angular_velocity=Vector3.ZERO
  wheel.spin_speed=-float(spec.speed)/3.6*Grid.new().body_basis(graph).x.dot(Vector3.RIGHT)/wheel.radius
 var lowest:=INF;var leading: float=-INF
 for index in graph.points.size():
  if _is_detached(graph,index):continue
  lowest=minf(lowest,graph.points[index].y-graph.radii[index])
  leading=maxf(leading,graph.points[index].x+graph.radii[index])
 var shift:=Vector3(wall_x-leading-.001,-lowest,0)
 for index in graph.points.size():
  if not _is_detached(graph,index):
   graph.points[index]+=shift;graph.velocities[index]=Vector3(float(spec.speed)/3.6,0,0)
 graph.old_points=graph.points.duplicate();graph.contact_wall.fill(0);graph.contact_floor.fill(0)
 graph.simulated_time=0;graph.impact_started=false;graph.impact_time=-1;graph.compact_active=false
 for link in graph.links:link.lambda=0;link.peak_force=0
 graph.initial_energy=graph.kinetic_energy();graph.maximum_energy=graph.initial_energy
 var effects: RefCounted=States.effects_owner(graph)
 if effects!=null:
  if effects.has_method('resume_live'):effects.resume_live()
  effects.synchronize()
 return before

static func _record_next(vehicle: RefCounted,spec: Dictionary,index: int,chain_id: String=CHAIN_ID) -> Dictionary:
 var graph: RefCounted=vehicle.solver
 var previous: Dictionary=prepare(graph,spec)
 var initial: Dictionary=States.capture(graph)
 var origin: Vector3=graph.station_center(2)
 var signature: Dictionary=Grid.new().signature(graph,Vector3(spec.speed/3.6,0,0))
 if signature.is_empty():push_error('Conditioned fixture produced no contact signature');return {}
 var frames: Array=[Clip.local_frame(graph,origin)]
 var before_steps: int=graph.step_count
 var began: int=Time.get_ticks_usec()
 var hz: int=roundi(1.0/float(graph.config.fixed_step_s))
 var stride: int=hz/120
 for step in roundi(2.5*hz):
  vehicle.step(1.0/hz)
  if (step+1)%stride==0:frames.append(Clip.local_frame(graph,origin))
 var metadata: Dictionary={'version':3,'id':chain_id+'_step_%d'%index,'heading_deg':spec.angle,'speed_kmh':spec.speed,'duration_s':2.5,'sample_hz':120,'physics_hz':hz,'quality_multiplier':int(graph.config.get('simulation_quality_multiplier',1)),'origin':[origin.x,origin.y,origin.z],'signature':signature,'full_solver_steps':graph.step_count-before_steps,'record_cpu_ms':float(Time.get_ticks_usec()-began)/1000,'structure_sha256':FileAccess.get_sha256('res://structure.json'),'wheel_solver_sha256':FileAccess.get_sha256('res://scripts/wheel_physics.gd'),'material_profile':graph.config.get('material_profile','unknown'),'scope':'Transition continues prior recorded damaged state. Fixture repositions/relaunches attached car; existing released wheel nodes remain world-owned. Effects attachment-local state is preserved.'}
 var clip: Dictionary={'metadata':metadata,'frames':frames}
 States.stamp(clip,initial,graph,chain_id,index)
 # Regression evidence, not another runtime state source.
 metadata['preparation_preserved_lengths']=initial.lengths==previous.lengths
 metadata['preparation_preserved_broken']=initial.broken==previous.broken
 metadata['preparation_preserved_effects']=States.irreversible_effects(initial.get('effects',{}))==States.irreversible_effects(previous.get('effects',{}))
 return clip

static func validate_prefix(first_clip: Dictionary) -> Dictionary:
 if first_clip.is_empty():return {'accepted':false,'reason':'missing_prefix'}
 if int(first_clip.metadata.get('version',0))<3:return {'accepted':false,'reason':'prefix_requires_version3'}
 if absf(float(first_clip.metadata.get('speed_kmh',0))-60)>.001 or absf(float(first_clip.metadata.get('heading_deg',0)))>.001:return {'accepted':false,'reason':'prefix_requires_60_frontal'}
 if first_clip.frames.is_empty() or not first_clip.frames.all(func(frame):return frame.has('effects')):return {'accepted':false,'reason':'prefix_requires_effects_snapshots'}
 if first_clip.metadata.get('structure_sha256','')!=FileAccess.get_sha256('res://structure.json'):return {'accepted':false,'reason':'prefix_body_fingerprint'}
 if first_clip.metadata.get('wheel_solver_sha256','')!=FileAccess.get_sha256('res://scripts/wheel_physics.gd'):return {'accepted':false,'reason':'prefix_wheel_fingerprint'}
 var fingerprints: Dictionary=first_clip.metadata.get('input_sha256',{})
 if fingerprints.is_empty():return {'accepted':false,'reason':'prefix_missing_input_fingerprints'}
 for path in fingerprints:
  if fingerprints[path]!=FileAccess.get_sha256('res://'+path):return {'accepted':false,'reason':'prefix_input_fingerprint:'+str(path)}
 var definition: Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://structure.json'))
 if definition.get('material_profile','')!='niva_multiaxis_v1':return {'accepted':false,'reason':'requires_promoted_multiaxis_profile'}
 return {'accepted':true,'reason':'current_prefix'}

static func build(first_clip: Dictionary,chain_id: String=CHAIN_ID) -> Array:
 var validation: Dictionary=validate_prefix(first_clip)
 if not validation.accepted:push_error(str(validation.reason));return []
 var vehicle=Vehicle.new();vehicle.setup('res://vehicles/niva.json',false)
 vehicle.set_simulation_quality(int(first_clip.metadata.get('quality_multiplier',1)))
 var graph: RefCounted=vehicle.solver
 graph.config.enforce_symmetry=false;graph.set_impact_mode(0)
 if States.effects_owner(graph)==null:push_error('Conditioned authoring requires active effects controllers');return []
 var initial: Dictionary=first_clip.duplicate(true)
 initial.metadata.id=chain_id+'_step_0'
 States.stamp(initial,{},graph,chain_id,0)
 var clips: Array=[initial]
 var source_origin:=Vector3(first_clip.metadata.origin[0],first_clip.metadata.origin[1],first_clip.metadata.origin[2])
 var effects: RefCounted=States.effects_owner(graph)
 if effects!=null:effects.begin_playback(first_clip.frames[-1].get('effects',{}))
 Clip.apply(graph,first_clip,float(first_clip.metadata.duration_s),source_origin)
 for index in FOLLOWUPS.size():
  var clip: Dictionary=_record_next(vehicle,FOLLOWUPS[index],index+1,chain_id)
  if clip.is_empty():return []
  clip.metadata['input_sha256']=first_clip.metadata.get('input_sha256',{}).duplicate(true)
  clip.metadata['conditioned_author_sha256']=FileAccess.get_sha256('res://scripts/conditioned_crash_authoring.gd')
  clips.append(clip)
  print('CONDITIONED_TRANSITION_RECORDED ',clip.metadata.id,' work_kj=',graph.plastic_work/1000.0,' source_effects=',clip.frames[0].has('effects'))
 return clips
