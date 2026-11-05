extends RefCounted
## Deterministic live-only orientations for multiaxis structural inspection.
const CASES=['roof_flat','roof_corner','side_wall']
static func descriptor(case_name: String='roof_corner',impact_speed_mps: float=-1,clearance: float=1.0) -> Dictionary:
 assert(case_name in CASES)
 var frame:=Basis.IDENTITY
 var velocity:=Vector3.ZERO
 if case_name=='side_wall':
  frame=Basis(Vector3.UP,PI*.5)
  velocity=Vector3(80.0/3.6 if impact_speed_mps<0 else impact_speed_mps,0,0)
 else:
  frame=Basis(Vector3.RIGHT,PI)
  if case_name=='roof_corner':frame=Basis(Vector3.BACK,deg_to_rad(15))*Basis(Vector3.RIGHT,PI+deg_to_rad(20))
  velocity=Vector3(3 if case_name=='roof_corner' else 0,-(8.0 if impact_speed_mps<0 else impact_speed_mps),0)
 var rotation: Quaternion=frame.get_rotation_quaternion()
 return {'version':1,'case':case_name,'family':'side_wall' if case_name=='side_wall' else 'roof_floor','material_profile':'niva_multiaxis_v1','material_profile_version':1,'rotation_xyzw':[rotation.x,rotation.y,rotation.z,rotation.w],'initial_velocity_mps':[velocity.x,velocity.y,velocity.z],'clearance_m':clearance,'barrier_enabled':case_name=='side_wall','flat_floor_y':0.0,'roof_start_x':-12.0,'wall_start_offset_x':-5.0,'scope':'Initial pose/loading descriptor. Actual contact speed must be measured or normalized separately when baking.'}
static func start(vehicle: RefCounted,case_name: String='roof_corner',clearance: float=1.0,experimental: bool=true,impact_speed_mps: float=-1) -> void:
 if 'baked_enabled' in vehicle:vehicle.baked_enabled=false
 restore(vehicle)
 vehicle.set_meta('body_fixture_adaptive_enabled',vehicle.adaptive_enabled)
 vehicle.set_meta('body_fixture_barrier_enabled',vehicle.solver.barrier_enabled)
 if experimental:apply_experimental_materials(vehicle.solver)
 else:apply_baseline_materials(vehicle.solver)
 vehicle.adaptive_enabled=false
 vehicle.reset(0,Vector3.ZERO)
 var g: RefCounted=vehicle.solver
 g.config.enforce_symmetry=false;g.compact_active=false;vehicle.mode='FULL'
 var spec: Dictionary=descriptor(case_name,impact_speed_mps,clearance)
 var q: Array=spec.rotation_xyzw
 var frame:=Basis(Quaternion(q[0],q[1],q[2],q[3]))
 var v: Array=spec.initial_velocity_mps
 var velocity:=Vector3(v[0],v[1],v[2])
 var origin:=Vector3.ZERO
 g.barrier_enabled=spec.barrier_enabled
 if case_name=='side_wall':origin=Vector3(g.barrier_min.x+spec.wall_start_offset_x,0,0)
 else:
  var minimum:=INF
  for i in g.rest.size():minimum=minf(minimum,(frame*g.rest[i]).y-g.radii[i])
  origin=Vector3(spec.roof_start_x,clearance-minimum,0)
 for i in g.points.size():g.points[i]=frame*g.rest[i]+origin;g.velocities[i]=velocity
 for wheel in g.wheels.wheels:
  wheel.rotation=frame.get_rotation_quaternion();wheel.previous_rotation=wheel.rotation
  wheel.angular_velocity=Vector3.ZERO;wheel.spin_speed=0
 g.initial_energy=g.kinetic_energy();g.maximum_energy=g.initial_energy
 vehicle.compact.capture_shape()
static func restore(vehicle: RefCounted) -> void:
 restore_materials(vehicle.solver)
 if vehicle.has_meta('body_fixture_adaptive_enabled'):
  vehicle.adaptive_enabled=vehicle.get_meta('body_fixture_adaptive_enabled')
  vehicle.remove_meta('body_fixture_adaptive_enabled')
 if vehicle.has_meta('body_fixture_barrier_enabled'):
  vehicle.solver.barrier_enabled=vehicle.get_meta('body_fixture_barrier_enabled')
  vehicle.remove_meta('body_fixture_barrier_enabled')
static func _apply_config(g: RefCounted,definition: Dictionary) -> void:
 assert(definition.nodes.size()==g.points.size() and definition.links.size()==g.links.size())
 var step_s: float=g.config.fixed_step_s
 var quality: int=int(g.config.get('simulation_quality_multiplier',1))
 g.config=definition.duplicate(true)
 g.config.fixed_step_s=step_s
 g.config['simulation_quality_multiplier']=quality
 for i in g.links.size():
  var link=g.links[i];var raw: Dictionary=definition.links[i]
  assert(link.a==raw.a and link.b==raw.b)
  link.kind=raw.kind;link.stiffness_n_per_m=raw.stiffness_n_per_m;link.yield_n=raw.yield_n
  link.max_compression=raw.max_compression;link.max_extension=raw.max_extension
  link.damping_ns_per_m=raw.damping_ns_per_m
  link.compliance=1.0/link.stiffness_n_per_m
  link.damping_fraction=1-exp(-link.damping_ns_per_m*link.weight_sum*float(g.config.fixed_step_s))
static func apply_experimental_materials(g: RefCounted) -> void:
 if not g.has_meta('multiaxis_original_config'):g.set_meta('multiaxis_original_config',g.config.duplicate(true))
 var definition: Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://structures/niva_multiaxis_live.json'))
 _apply_config(g,definition)
static func apply_baseline_materials(g: RefCounted) -> void:
 if not g.has_meta('multiaxis_original_config'):g.set_meta('multiaxis_original_config',g.config.duplicate(true))
 var definition: Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://structures/niva_front_bench_baseline.json'))
 _apply_config(g,definition)
static func restore_materials(g: RefCounted) -> void:

 if not g.has_meta('multiaxis_original_config'):return
 _apply_config(g,g.get_meta('multiaxis_original_config'))
 g.remove_meta('multiaxis_original_config')
static func metrics(g: RefCounted) -> Dictionary:
 var cabin_height:=0.0;var cabin_width:=0.0
 var roof_spans: Array=[]
 for pair in [[2,3],[6,7],[10,11],[14,15],[28,29]]:roof_spans.append(g.points[pair[0]].distance_to(g.points[pair[1]]))
 for pair in [[4,6],[5,7],[8,10],[9,11],[12,28],[13,29]]:cabin_height+=g.points[pair[0]].distance_to(g.points[pair[1]])/6
 for pair in [[4,5],[6,7],[8,9],[10,11],[28,29]]:cabin_width+=g.points[pair[0]].distance_to(g.points[pair[1]])/5
 var kinds: Dictionary={}
 for link in g.links:
  if not kinds.has(link.kind):kinds[link.kind]={'yielded':0,'max_damage':0.0,'plastic_length_change_m':0.0}
  if link.damage>.001:kinds[link.kind].yielded+=1
  kinds[link.kind].max_damage=maxf(kinds[link.kind].max_damage,link.damage)
  kinds[link.kind].plastic_length_change_m+=absf(link.length-link.original)
 var minimum_floor:=INF;var finite:=true
 for i in g.points.size():
  finite=finite and g.points[i].is_finite() and g.velocities[i].is_finite()
  if g.config.nodes[i].group!='wheel':minimum_floor=minf(minimum_floor,g.points[i].y-g.radii[i])
 return {'roof_spans_m':roof_spans,'cabin_height_m':cabin_height,'cabin_width_m':cabin_width,'by_kind':kinds,'plastic_work_kj':g.plastic_work/1000,'minimum_floor_clearance_m':minimum_floor,'finite':finite,'kinetic_kj':g.kinetic_energy()/1000,'maximum_kinetic_kj':g.maximum_energy/1000,'wheel_states':g.wheels.metrics()}
