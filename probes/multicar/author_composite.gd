extends SceneTree
const Structure=preload('res://scripts/structure_solver.gd')
const Effects=preload('res://scripts/vehicle_effects.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
class OpposedGraph extends 'res://scripts/structure_solver.gd':
 var rear_min:=Vector3.ZERO
 var rear_max:=Vector3.ZERO
 func _contacts() -> void:
  super._contacts()
  var a: Vector3=barrier_min;var b: Vector3=barrier_max
  barrier_min=rear_min;barrier_max=rear_max
  super._contacts();wheels.contacts(float(config.fixed_step_s))
  barrier_min=a;barrier_max=b
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var graph:=OpposedGraph.new();graph.setup();graph.config.enforce_symmetry=false
 graph.config.fixed_step_s=1.0/960
 for link in graph.links:link.damping_fraction=1-exp(-link.damping_ns_per_m*link.weight_sum/960)
 graph.effects=Effects.new();graph.effects.setup(graph)
 graph.reset(0,Vector3.ZERO);graph.barrier_enabled=true
 var front: float=-INF;var rear:=INF
 for i in graph.points.size():front=maxf(front,graph.points[i].x+graph.radii[i]);rear=minf(rear,graph.points[i].x-graph.radii[i])
 var frames: Array=[Clip.local_frame(graph,Vector3.ZERO)]
 var start: int=Time.get_ticks_usec();var max_energy:=0.0
 for step in 2400:
  var t: float=(step+1)/960.0
  # Controlled opposed moving-wall fixture; decelerates to a finite .6m stroke.
  var moving: float=minf(t,.072)
  var stroke: float=(60.0/3.6)*(moving-.5*moving*moving/.072)
  graph.barrier_min=Vector3(front-stroke,0,-2.25);graph.barrier_max=graph.barrier_min+Vector3(.5,3.5,4.5)
  graph.rear_max=Vector3(rear+stroke,3.5,2.25);graph.rear_min=graph.rear_max-Vector3(.5,3.5,4.5)
  graph.step(1.0/960);graph.effects.step_live(1.0/960)
  max_energy=maxf(max_energy,graph.kinetic_energy())
  if (step+1)%8==0:frames.append(Clip.local_frame(graph,Vector3.ZERO))
 var metadata: Dictionary={'id':'opposed_front_rear_60','version':3,'family':'opposed_front_rear','heading_deg':0.0,'speed_kmh':60.0,'duration_s':2.5,'sample_hz':120,'physics_hz':960,'origin':[0,0,0],'signature':{'normal':[-1,0,0],'zones':[],'closing_speed_mps':60.0/3.6},'contact_families':['front','rear'],'panels_runtime_enabled':false,'per_face_launch_kmh':60,'stroke_m':.6,'scope':'Offline prescribed two moving walls, equal opposed compression, .6m decelerating stroke each. This is a new composite fixture, not sum of two pristine clips or full moving-car authoring. Root motion removed by probe playback. External walls inject energy.','input_sha256':{}}
 var sources: Dictionary=Clip.read('res://bakes/impact_000_60.crashclip').metadata.input_sha256.duplicate()
 sources['probes/multicar/author_composite.gd']=''
 for path in sources:metadata.input_sha256[path]=FileAccess.get_sha256('res://'+path)
 var data: Dictionary={'metadata':metadata,'frames':frames}
 Clip.save(data,'res://probes/multicar/data/opposed_front_rear_60.crashclip',false)
 var detached: Array=graph.wheels.capture().map(func(w):return w.detached)
 print('MULTICAR_COMPOSITE_BAKED frames=',frames.size(),' ms=',(Time.get_ticks_usec()-start)/1000.0,' max_energy_kj=',max_energy/1000,' work_kj=',graph.plastic_work/1000,' detached=',detached)
 quit()
