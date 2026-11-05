extends SceneTree
const Fixture=preload('res://probes/panels/fixtures.gd')
func _initialize() -> void:
 for mode_ in ['right_free','right_sag']:
  var f:=Fixture.new();f.start('controls')
  for part in f.graph.panels.panels:f.graph.panels.configure_closing_seats(part)
  f.graph.panels.find('door_right').hinge_strength_n=16000
  if mode_=='right_sag':f.graph.panels.find('door_right')['lower_strength_fraction']=.15
  f.graph.panels.obstacle={'center':Vector3(-.1,1,-2.3),'size':Vector3(.62,.65,.14),'velocity':Vector3(0,0,9),'travel_axis':2,'stop':-.62,'retracting':false}
  for i in 480:
   f.step()
   var right: Dictionary=f.graph.panels.find('door_right')
   if f.time>.30 and right.anchors[2].broken and right.closing_supports.all(func(s):return s.broken) and (mode_=='right_free' or right.anchors[0].broken):break
  f.graph.panels.obstacle={}
  var p: Dictionary=f.graph.panels.find('door_right')
  FileAccess.open('res://probes/panels/data/'+mode_+'.panelstate',FileAccess.WRITE).store_var(f.graph.capture(),true)
  print('MEASURED_RIGHT ',mode_,' latch=',p.anchors[2].broken,' hinges=',[p.anchors[0].broken,p.anchors[1].broken],' plastic_j=',p.plastic_work,' angle=',p.angle,' seats=',p.closing_supports.map(func(s):return s.broken))
 quit()
