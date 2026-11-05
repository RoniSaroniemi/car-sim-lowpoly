extends 'res://scripts/structure_solver.gd'
const Panels=preload('res://probes/panels/panel_system.gd')
var panels: RefCounted
var release_step_us: Array=[]
func setup(definition_path: String='res://structure.json') -> void:
 super.setup(definition_path)
 config.enforce_symmetry=false;barrier_enabled=false
 panels=Panels.new();panels.setup(self)
func step(dt: float) -> void:
 var began: int=Time.get_ticks_usec();var old_releases: int=panels.release_continuity.size()
 panels.prepare_step(dt)
 super.step(dt)
 panels.finish_step()
 if not panels.obstacle.is_empty():
  panels.obstacle.center+=panels.obstacle.velocity*dt
  if not panels.obstacle.get('retracting',false):
   var axis: int=panels.obstacle.get('travel_axis',2)
   var stop: float=panels.obstacle.get('stop',.62)
   if (panels.obstacle.velocity[axis]<0 and panels.obstacle.center[axis]<stop) or (panels.obstacle.velocity[axis]>0 and panels.obstacle.center[axis]>stop):
    panels.obstacle.velocity=-panels.obstacle.velocity;panels.obstacle.retracting=true
 if panels.release_continuity.size()>old_releases:release_step_us.append(Time.get_ticks_usec()-began)
func _contacts() -> void:
 if panels!=null:panels.solve()
 super._contacts()
func capture() -> Dictionary:
 var state: Dictionary=super.capture()
 if panels!=null:state['panels']=panels.capture();state['mass_nodes']=masses.duplicate();state['obstacle']=panels.obstacle.duplicate(true)
 return state
func restore(state: Dictionary,restore_effects: bool=true) -> void:
 super.restore(state,restore_effects)
 if state.has('panels'):
  masses=state.mass_nodes.duplicate()
  for i in masses.size():inverse_masses[i]=1/masses[i]
  config.mass_kg=0.0
  for mass in masses:config.mass_kg+=mass
  panels.restore(state.panels);panels.obstacle=state.obstacle.duplicate(true)
