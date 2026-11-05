extends SceneTree
var view: Node3D
var specs: Array=[['road_throttle_from_rest','road_front_driving_final'],['road_120_p30','road_oblique_120_final'],['road_open_road_120_m20','road_open_strike_final'],['hinge_0','one_hinge_stiff'],['hinge_1800','one_hinge_plastic_bend'],['road_side_24','road_side_release']]
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 view=load('res://probes/panels/drive_probe.tscn').instantiate();root.add_child(view)
 view.paused=true;view.replay=true
 for spec in specs:
  view._start('closed');view.paused=true;view.replay=true;view.orbit=PI if spec[0]=='road_side_24' else 0.0
  var path: String='res://probes/panels/data/'+spec[0]+('.panelstate' if str(spec[0]).begins_with('hinge_') else '.panelclip')
  var data: Dictionary=FileAccess.open(path,FileAccess.READ).get_var(false) if str(spec[0]).begins_with('hinge_') else FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_ZSTD).get_var(false)
  var state: Dictionary=data.frames[-1] if data.has('frames') else data
  if state.has('graph'):view.runtime.restore(state)
  else:
   view.runtime.graph.restore(state);view.runtime.compact.mass=0
   for i in view.runtime.compact.indices:view.runtime.compact.mass+=view.runtime.graph.masses[i]
   view.runtime.compact.capture_shape();view.runtime.graph.compact_active=true
  view.runtime.speed=view.runtime.dynamics.body_velocity().length()*3.6
  for child in view.get_children():
   if child is MeshInstance3D and child.mesh is BoxMesh and absf(child.mesh.size.x-.5)<.001:
    if str(spec[0]).begins_with('road_open'):
     child.mesh.size=Vector3(.5,3.5,1.65);child.position=Vector3(45.25,1.75,-1.975)
    elif spec[0]=='road_side_24':
     child.mesh.size=state.obstacle.size;child.position=state.obstacle.center
    else:child.mesh.size=Vector3(.5,3.5,24);child.position=Vector3(45.25,1.75,0)
  for i in 8:await process_frame
  RenderingServer.force_draw(false)
  var output: String='res://probes/panels/evidence/'+spec[1]+'.png'
  root.get_texture().get_image().save_png(output);print('ROAD_NATIVE_CAPTURE ',output)
 quit()
