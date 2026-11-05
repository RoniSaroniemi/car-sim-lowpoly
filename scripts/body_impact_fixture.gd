extends RefCounted
## Deterministic live-only orientations for multiaxis structural inspection.
const CASES=['roof_flat','roof_corner','side_wall']
static func start(vehicle: RefCounted,case_name: String='roof_corner',clearance: float=1.0,experimental: bool=true) -> void:
 if 'baked_enabled' in vehicle:vehicle.baked_enabled=false
 restore(vehicle)
 vehicle.set_meta('body_fixture_adaptive_enabled',vehicle.adaptive_enabled)
 vehicle.set_meta('body_fixture_barrier_enabled',vehicle.solver.barrier_enabled)
 if experimental:apply_experimental_materials(vehicle.solver)
 vehicle.adaptive_enabled=false
 vehicle.reset(0,Vector3.ZERO)
 var g: RefCounted=vehicle.solver
 g.config.enforce_symmetry=false
 g.compact_active=false
 vehicle.mode='FULL'
 var basis:=Basis.IDENTITY
 var velocity:=Vector3.ZERO
 var origin:=Vector3.ZERO
 if case_name=='side_wall':
  basis=Basis(Vector3.UP,PI*.5)
  velocity=Vector3(80.0/3.6,0,0)
  origin=Vector3(g.barrier_min.x-5,0,0)
  g.barrier_enabled=true
 else:
  basis=Basis(Vector3.RIGHT,PI)
  if case_name=='roof_corner':basis=Basis(Vector3.BACK,deg_to_rad(15))*Basis(Vector3.RIGHT,PI+deg_to_rad(20))
  velocity=Vector3(3,-8,0) if case_name=='roof_corner' else Vector3(0,-8,0)
  var minimum:=INF
  for i in g.rest.size():minimum=minf(minimum,(basis*g.rest[i]).y-g.radii[i])
  origin=Vector3(-12,clearance-minimum,0)
  g.barrier_enabled=false
 for i in g.points.size():
  g.points[i]=basis*g.rest[i]+origin
  g.velocities[i]=velocity
 for wheel in g.wheels.wheels:
  wheel.rotation=basis.get_rotation_quaternion();wheel.previous_rotation=wheel.rotation
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
 g.config=definition.duplicate(true)
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
