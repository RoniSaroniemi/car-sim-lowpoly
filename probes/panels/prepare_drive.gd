extends SceneTree
const Graph=preload('res://probes/panels/panel_graph.gd')
const RoadProfile=preload('res://probes/panels/road_panel_profile.gd')
func _initialize() -> void:
 var valid:=true
 for item in [['right_free',6.0],['right_sag',12.0]]:
  var g:=Graph.new();g.setup();g.reset(0,Vector3.ZERO);g.panels.reset();RoadProfile.apply(g.panels)
  g.config.fixed_step_s=1.0/960
  for link in g.links:link.damping_fraction=1-exp(-link.damping_ns_per_m*link.weight_sum/960)
  g.panels.obstacle={'center':Vector3(-.1,1.1,-2.3),'size':Vector3(.95,1.4,.14),'velocity':Vector3(0,0,item[1]),'travel_axis':2,'stop':.05,'retracting':false,'hold_at_stop':true}
  var found:=false
  for step in 960:
   g.step(1.0/960)
   var p: Dictionary=g.panels.find('door_right')
   var hinges: int=int(p.anchors[0].broken)+int(p.anchors[1].broken)
   if p.anchors[2].broken and p.closing_supports.all(func(s):return s.broken) and hinges==(0 if item[0]=='right_free' else 1):found=true;break
  g.panels.obstacle={}
  for step in 192:g.step(1.0/960)
  var p: Dictionary=g.panels.find('door_right')
  var hinges: int=int(p.anchors[0].broken)+int(p.anchors[1].broken)
  var accepted: bool=found and not p.detached and hinges==(0 if item[0]=='right_free' else 1)
  valid=valid and accepted
  FileAccess.open('res://probes/panels/data/'+item[0]+'.panelstate',FileAccess.WRITE).store_var(g.capture(),false)
  print('MEASURED_ROAD_RIGHT ',item[0],' accepted=',accepted,' latch=',p.anchors[2].broken,' hinges=',p.anchors.map(func(a):return a.broken),' seats=',p.closing_supports.map(func(s):return s.broken),' speed=',item[1],' plastic_j=',p.plastic_work,' angular=',p.angular_mount,' evidence=',p.impact_evidence)
 quit(0 if valid else 1)
