extends SceneTree
const World=preload('res://probes/multicar/world.gd')
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 for name_ in ['head_on','parked','triple','corner','low']:
  var sim:=World.new();sim.record_enabled=false;sim.start(name_)
  for step in 420:sim.step()
  print('MULTICAR_RESULT ',name_,' ',JSON.stringify(sim.stats()))
  for car in sim.cars:print('CAR ',car.id,' clip=',car.clip_id,' reason=',car.last_selection.get('reason',''),' detached=',car.graph.wheels.capture().map(func(w):return w.detached))
 quit()
