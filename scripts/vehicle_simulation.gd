extends RefCounted
## The scenes supply input/time; this is the single live vehicle implementation.
const Structure=preload('res://scripts/structure_solver.gd')
const Dynamics=preload('res://scripts/vehicle_dynamics.gd')
var solver: RefCounted
var dynamics: RefCounted
var profile: Dictionary
var driving:=false
var accumulator:=0.0

func setup(profile_path: String='res://vehicles/niva.json',enable_driving: bool=false) -> void:
 profile=JSON.parse_string(FileAccess.get_file_as_string(profile_path))
 solver=Structure.new()
 solver.setup(profile.structure)
 driving=enable_driving
 dynamics=Dynamics.new()
 dynamics.setup(solver,profile.dynamics)
 if driving:solver.config.enforce_symmetry=false

func reset(speed_kmh: float=0,start: Vector3=Vector3(-9,0,0),weaken: bool=false) -> void:
 accumulator=0
 dynamics.reset()
 solver.reset(speed_kmh,start,weaken)

func set_controls(throttle: float,brake: float,steering: float,handbrake: float=0) -> void:
 dynamics.set_controls(throttle,brake,steering,handbrake)

func step(dt: float) -> void:
 if driving:dynamics.step(dt)
 solver.step(dt)

func advance(elapsed: float,time_scale: float=1.0) -> void:
 accumulator+=elapsed*time_scale
 var fixed_step: float=solver.config.fixed_step_s
 while accumulator>=fixed_step:
  step(fixed_step)
  accumulator-=fixed_step

func velocity() -> Vector3:
 return dynamics.body_velocity()

func forward() -> Vector3:
 return dynamics.body_forward()
