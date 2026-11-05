extends 'res://scripts/crash_bake_recorder.gd'
## Finite one-edge author. Uses standard snapshots/final metadata, including
## whichever panels/effects have been integrated into the shared frozen source.
const Coverage=preload('res://scripts/baked_contact_coverage.gd')
const Partial=preload('res://scripts/partial_crash_library.gd')
var clipped_side: String='left'
var requested_overlap:=.5
var initial_coverage: Dictionary={}
func start_partial(angle: float,speed: float,side: String,overlap: float) -> void:
 clipped_side=side;requested_overlap=overlap
 start(angle,speed)
 var g: RefCounted=vehicle.solver
 for i in g.points.size():g.points[i].x+=6
 g.config.enforce_symmetry=false
 g.barrier_min=Vector3(0,0,-8);g.barrier_max=Vector3(1,3,8)
 var low:=INF;var high:=-INF
 for i in g.points.size():
  low=minf(low,g.points[i].z-g.radii[i]);high=maxf(high,g.points[i].z+g.radii[i])
 var shift: float=g.barrier_min.z-(high-overlap*(high-low)) if side=='left' else g.barrier_max.z-(low+overlap*(high-low))
 for i in g.points.size():g.points[i].z+=shift
 _synchronize_aux(g)
 vehicle.compact.capture_shape()
 initial_coverage={}

func _synchronize_aux(g: RefCounted) -> void:
 if g.effects!=null:g.effects.synchronize()
 # The combined panel integration exposes synchronize_inactive; retaining a
 # method fallback keeps the technical author usable on the earlier core.
 var panels: Variant=g.get('panels')
 if panels!=null:
  if panels.has_method('synchronize_inactive'):panels.synchronize_inactive()
  elif panels.has_method('synchronize'):panels.synchronize()

func _gap_at(g: RefCounted,motion: Vector3,time: float) -> float:
 var gap:=INF
 for i in g.points.size():
  var p: Vector3=g.points[i]+motion*time
  var hit: Dictionary=g.barrier_distance(p)
  gap=minf(gap,float(hit.distance)-g.radii[i])
 return gap

func step() -> void:
 if completed:return
 var g: RefCounted=vehicle.solver
 var dt: float=g.config.fixed_step_s
 if not armed:
  if g.simulated_time>3:
   push_error('Partial launcher did not reach the finite barrier');completed=true;return
  var began: int=Time.get_ticks_usec()
  var velocity: Vector3=vehicle.velocity()
  var at_start: float=_gap_at(g,velocity,0)
  var at_end: float=_gap_at(g,velocity,dt)
  if minf(at_start,at_end)>0:
   vehicle.step(dt);full_steps+=1;cpu_us+=Time.get_ticks_usec()-began
   return
  var low:=0.0;var high:=dt
  if at_start<=0:high=0
  else:
   for iteration in 12:
    var middle: float=(low+high)*.5
    if _gap_at(g,velocity,middle)<=0:high=middle
    else:low=middle
  for i in g.points.size():g.points[i]+=velocity*high
  preparation_speed_mps=velocity.length()
  var impact_velocity:=Vector3(speed_kmh/3.6,0,0)
  for i in g.velocities.size():g.velocities[i]+=impact_velocity-velocity
  for wheel in g.wheels.wheels:wheel.spin_speed=-impact_velocity.dot(grid.body_basis(g).x)/wheel.radius
  _synchronize_aux(g)
  signature=grid.signature(g,impact_velocity)
  if signature.is_empty():
   push_error('No incoming contact signature at partial registration');completed=true;return
  origin=g.station_center(2)
  initial_coverage=Coverage.describe(g,{'toi':0},signature)
  g.initial_energy=g.kinetic_energy();g.maximum_energy=g.initial_energy
  armed=true;frames.append(Clip.local_frame(g,origin));next_sample=1.0/120
  cpu_us+=Time.get_ticks_usec()-began
 super.step()
 if completed and not result.is_empty():
  result.metadata.id=Partial.case_id(angle_deg,speed_kmh,clipped_side,requested_overlap)
  result.metadata['contact_coverage']=initial_coverage
  result.metadata['requested_overlap']=requested_overlap
  result.metadata['partial_authoring_schema']=1
  result.metadata['scope']='Controlled finite one-edge barrier-box impact; no arbitrary wall, post or end-face extrapolation. Full shared physics/effects/panel snapshots are authored offline.'
  for source in ['scripts/partial_crash_recorder.gd','scripts/baked_contact_coverage.gd','scripts/partial_crash_library.gd','scripts/crash_bake_recorder.gd']:
   result.metadata.input_sha256[source]=FileAccess.get_sha256('res://'+source)
