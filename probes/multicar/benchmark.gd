extends SceneTree
const World=preload('res://probes/multicar/world.gd')
const Library=preload('res://probes/multicar/library.gd')
func _initialize() -> void:call_deferred('_run')
func summary(costs: Array) -> Dictionary:
 var ordered: Array=costs.duplicate();ordered.sort();var total:=0.0
 for value in ordered:total+=value
 return {'mean_us':total/maxi(1,costs.size()),'p95_us':ordered[mini(ordered.size()-1,ceili(ordered.size()*.95)-1)],'p99_us':ordered[mini(ordered.size()-1,ceili(ordered.size()*.99)-1)]}
func _run() -> void:
 var warm:=World.new();warm.record_enabled=false;warm.start('head_on')
 for id in ['impact_000_60','impact_180_60','opposed_front_rear_60']:Library.get_clip(id,warm.cars[0].graph)
 var reports: Array=[]
 for count in [1,2,3,10]:
  for active in [false,true]:
   if count==1 and active:continue
   var world:=World.new();world.record_enabled=false
   if active:world.start('triple' if count==3 else 'head_on')
   while world.cars.size()<count:world.add_car(Vector3(world.cars.size()*15,0,30),0,Vector3(5,0,0))
   var costs: Array=[]
   for step in 480:
    var start: int=Time.get_ticks_usec();world.step();costs.append(Time.get_ticks_usec()-start)
   var report: Dictionary=summary(costs)
   report.merge({'car_count':count,'active_collision':active,'seconds':4,'recording_enabled':false,'pairs':world.pairs_checked,'broadphase_passes':world.broadphase_passes,'contacts':world.contacts_count,'bake_count':world.cars.reduce(func(total,car):return total+car.played,0),'full_steps':world.cars.reduce(func(total,car):return total+car.graph.step_count,0)})
   reports.append(report);print('MULTICAR_COST ',JSON.stringify(report))
 FileAccess.open('res://probes/multicar/evidence/performance.json',FileAccess.WRITE).store_string(JSON.stringify({'host':'Apple M3/macOS/Godot4.7.2 Compatibility','runs':reports,'scope':'Warm-cache CPU calls for physical roots/contact/deformation sampling/effects state. Excludes scene/model creation, native render upload/GPU/UI and optional replay snapshot recorder. Planar proof; no 3D tire/suspension solve. No FPS claim.'},'\t'))
 quit()
