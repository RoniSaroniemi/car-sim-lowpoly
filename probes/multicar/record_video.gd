extends SceneTree
var probe: Node3D
var ticks:=0
var frame:=0
var stage:=0
var skip:=8
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 root.size=Vector2i(1280,800)
 probe=load('res://probes/multicar/probe.tscn').instantiate();root.add_child(probe)
 probe.set_process_unhandled_input(false)
 probe.paused=true;probe.slow=true;probe.sim.record_enabled=false
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://verification/multicar_video'))
 RenderingServer.frame_post_draw.connect(_drawn)
func _drawn() -> void:
 if probe==null:return
 if skip>0:skip-=1;return
 root.get_texture().get_image().save_png('res://verification/multicar_video/%04d.png'%frame)
 frame+=1;ticks+=1
 if ticks>=180:
  stage+=1;ticks=0
  if stage>=2:
   FileAccess.open('res://probes/multicar/evidence/video.json',FileAccess.WRITE).store_string(JSON.stringify({'frames':frame,'fps':30,'presentation':'12 seconds at quarter-speed, real GPU-rendered head-on then simultaneous three-car opposed contact','full_structure_steps':0,'source':'probes/multicar/record_video.gd'},'\t'))
   quit();return
  probe._start('triple');probe.paused=true;probe.sim.record_enabled=false;skip=5
 probe.sim.step()
