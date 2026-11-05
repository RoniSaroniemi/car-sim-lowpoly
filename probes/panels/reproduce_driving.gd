extends SceneTree
const Drive=preload('res://probes/panels/drive_runtime.gd')
func summary(d: RefCounted) -> Array:
 var out: Array=[]
 for p in d.graph.panels.panels:
  out.append({'id':p.id,'hinge_n':p.hinge_strength_n,'latch_n':p.latch_strength_n,'hinges':p.anchors.map(func(a):return {'broken':a.broken,'peak_n':a.get('maximum_n',0),'exposure_s':a.exposure}),'seats':p.get('closing_supports',[]).map(func(s):return {'node':s.node,'broken':s.broken,'peak_n':s.maximum_n}),'plastic_j':p.plastic_work,'detached':p.detached,'latched':p.latched,'mode':p.get('reduced_mode',''),'contacts':p.contacts,'normal':p.last_normal,'local':p.get('impact_evidence',{})})
 return out
func _initialize() -> void:
 var d:=Drive.new();d.start('closed');var snapshots: Array=[{'time':0,'parts':summary(d)}];var event_count:=0;var entered:=false;var contact_speed:=-1.0
 print('DRIVE_REPRO_INITIAL ',JSON.stringify(snapshots[0]))
 for i in 700:
  var before: float=d.speed;d.controls(1,0,0);d.step()
  if d.graph.impact_started and contact_speed<0:contact_speed=before
  if d.full_remaining>0 and not entered:entered=true;snapshots.append({'time':d.time,'kind':'full_wake','parts':summary(d)})
  if d.graph.panels.events.size()!=event_count:
   snapshots.append({'time':d.time,'kind':'failure','parts':summary(d),'events':d.graph.panels.events.duplicate(true)})
   event_count=d.graph.panels.events.size()
  if entered and d.full_remaining<=0 and d.time>4:break
 var result: Dictionary={'case':'W throttle fromrest, actual drive barrier','contact_kmh':contact_speed,'final':summary(d),'history':snapshots,'events':d.graph.panels.events,'stats':d.stats()}
 FileAccess.open('res://probes/panels/evidence/driving_failure_reproduction.json',FileAccess.WRITE).store_string(JSON.stringify(result,'  '))
 print('DRIVE_REPRO_RESULT ',JSON.stringify(result.final),' contact_kmh=',contact_speed,' events=',JSON.stringify(d.graph.panels.events));quit()
