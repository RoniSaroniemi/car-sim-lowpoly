extends SceneTree
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var author=load('res://scripts/partial_crash_recorder.gd').new();author.quality_multiplier=1
 author.start_partial(30,60,'left',.25)
 for i in 1500:
  author.step()
  if i%120==0:print('AUTHOR_TRACE ',i,' t=',author.vehicle.solver.simulated_time,' origin=',author.vehicle.solver.station_center(2),' gap=',author._gap_at(author.vehicle.solver,author.vehicle.velocity(),0),' vx=',author.vehicle.velocity(),' armed=',author.armed)
  if author.armed:print('AUTHOR_CONTACT ',author.signature,' coverage=',author.initial_coverage);break
  if author.completed:break
 quit()
