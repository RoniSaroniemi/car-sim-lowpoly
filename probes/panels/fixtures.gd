extends RefCounted
const Graph=preload('res://probes/panels/panel_graph.gd')
const CASES=['controls','closed_medium','closed_severe','open_medium','open_severe','missed_open','weak_closed']
var graph: RefCounted
var name_:='controls'
var time:=0.0
var frames: Array=[]
var h:=1.0/480
var duration:=2.5
var running:=true
var complete:=false
var cpu_us:=0
var max_step_us:=0
var initial_energy:=0.0
var maximum_energy:=0.0
var contact_energy:=0.0
var control_energy:=0.0

func start(case_name: String) -> void:
 name_=case_name;time=0;complete=false;cpu_us=0;max_step_us=0
 graph=Graph.new();graph.setup();graph.reset(0,Vector3.ZERO);graph.panels.reset()
 graph.barrier_enabled=false;graph.config.enforce_symmetry=false
 if case_name in ['open_medium','open_severe','missed_open']:
  graph.panels.set_open('door_left',65)
  for step in 720:graph.step(h)
  # Settling to the commanded opening is real simulation, not a replay angle.
  graph.simulated_time=0;graph.panels.clock=0;graph.step_count=0;graph.panels.events.clear()
 if case_name!='controls':
  var open_case: bool=case_name.begins_with('open_') or case_name=='missed_open'
  var speed: float=20.0 if case_name.ends_with('severe') else 6.0 if case_name!='weak_closed' else 1.1
  graph.panels.obstacle={'center':Vector3(1.4,1.0,1.70) if open_case else Vector3(-.10,1.0,2.30),'size':Vector3(.14,.64,.46) if open_case else Vector3(.62,.65,.14),'velocity':Vector3(-speed,0,0) if open_case else Vector3(0,0,-speed),'travel_axis':0 if open_case else 2,'stop':-.45 if open_case else .62,'retracting':false}
  if case_name=='missed_open':graph.panels.obstacle.center.y=3.0
  if case_name=='weak_closed':graph.panels.obstacle.stop=.995
 initial_energy=energy();maximum_energy=initial_energy;frames=[graph.capture()]

func energy() -> float:
 var result: float=graph.kinetic_energy()
 for p in graph.panels.panels:
  if not p.active:continue
  for velocity in p.velocity:result+=.5*p.mass/10*velocity.length_squared()
 return result

func step() -> void:
 if complete:return
 var began: int=Time.get_ticks_usec()
 graph.step(h);time+=h
 maximum_energy=maxf(maximum_energy,energy())
 if graph.step_count%4==0:frames.append(graph.capture())
 var cost: int=Time.get_ticks_usec()-began;cpu_us+=cost;max_step_us=maxi(max_step_us,cost)
 if time>=duration-1e-8:complete=true

func metrics() -> Dictionary:
 var p: Dictionary=graph.panels.find('door_left')
 var failed_hinges: int=int(p.anchors[0].broken)+int(p.anchors[1].broken)
 var edge_change:=0.0
 for edge in p.edges:edge_change=maxf(edge_change,absf(edge.length-edge.original))
 var finite:=true
 for panel in graph.panels.panels:
  for point_ in panel.points:finite=finite and point_.is_finite()
  for v in panel.velocity:finite=finite and v.is_finite()
 return {'case':name_,'angle_deg':rad_to_deg(p.angle),'latched':p.latched,'latch_broken':p.anchors[2].broken,'failed_hinges':failed_hinges,'detached':p.detached,'anchor_peak_n':p.anchors.map(func(a):return a.get('maximum_n',0)),'panel_plastic_work_j':p.plastic_work,'max_plastic_edge_change_m':edge_change,'contacts':p.contacts,'maximum_mount_force_n':p.maximum_force,'release_time':p.release_time,'mass_kg':graph.panels.total_mass(),'body_mass_kg':graph.config.mass_kg,'initial_energy_j':initial_energy,'maximum_energy_j':maximum_energy,'finite':finite,'full_solver_steps':graph.step_count,'mean_step_us':float(cpu_us)/maxi(1,graph.step_count),'max_step_us':max_step_us,'panel_stats':graph.panels.statistics()}
