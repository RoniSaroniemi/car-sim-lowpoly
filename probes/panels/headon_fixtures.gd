extends 'res://probes/panels/fixtures.gd'
const RoadProfile=preload('res://probes/panels/road_panel_profile.gd')
var requested_kmh:=60.0
var measured_contact_kmh:=-1.0
var contact_time:=-1.0
var pre_contact_velocity:=Vector3.ZERO
var outcomes: Dictionary={}
var costs: Array=[]
func start(case_name: String) -> void:
 super.start('controls')
 name_=case_name;requested_kmh=120 if case_name=='headon_120' else 60
 graph.reset(requested_kmh,Vector3(-5,0,0));graph.panels.reset()
 graph.barrier_enabled=true;graph.barrier_min=Vector3(0,0,-2.25);graph.barrier_max=Vector3(.5,3.5,2.25)
 graph.structural_panel_wake=true
 # A common stronger road-car mount profile; same values at both launch speeds.
 RoadProfile.apply(graph.panels)
 graph.panels.obstacle={'center':Vector3(.25,1.75,0),'size':Vector3(.5,3.5,4.5),'velocity':Vector3.ZERO,'travel_axis':0,'stop':-100,'retracting':true}
 # Author at960Hz. Rate-based stiffness/damping/failure windows stay seconds.
 h=1.0/960;graph.config.fixed_step_s=h
 for link in graph.links:link.damping_fraction=1-exp(-link.damping_ns_per_m*link.weight_sum*h)
 duration=2.5;initial_energy=energy();maximum_energy=initial_energy;frames=[graph.capture()]
func step() -> void:
 if complete:return
 var began: int=Time.get_ticks_usec()
 pre_contact_velocity=Vector3.ZERO
 for i in graph.points.size():pre_contact_velocity+=graph.velocities[i]*graph.masses[i]/float(graph.config.mass_kg)
 super.step()
 costs.append(Time.get_ticks_usec()-began)
 # Base records every4 steps; head-on keeps120Hz snapshots instead.
 if graph.step_count%8==4:frames.pop_back()
 if contact_time<0 and graph.impact_started:
  contact_time=time;measured_contact_kmh=pre_contact_velocity.x*3.6
func metrics() -> Dictionary:
 var result: Dictionary=super.metrics()
 result['requested_speed_kmh']=requested_kmh;result['measured_contact_kmh']=measured_contact_kmh;result['contact_time_s']=contact_time;result['author_hz']=1/h
 result['body']=graph.metrics();result['structural_panel_wakes']=graph.structural_wake_count
 var sorted: Array=costs.duplicate();sorted.sort()
 result['p95_step_us']=sorted[mini(sorted.size()-1,floori(sorted.size()*.95))] if not sorted.is_empty() else 0
 result['p99_step_us']=sorted[mini(sorted.size()-1,floori(sorted.size()*.99))] if not sorted.is_empty() else 0
 result['all_panels']=[]
 for p in graph.panels.panels:
  var change:=0.0
  for edge in p.edges:change=maxf(change,absf(edge.length-edge.original))
  result.all_panels.append({'id':p.id,'active':p.active,'latch_broken':p.anchors[2].broken,'latched':p.latched,'failed_hinges':int(p.anchors[0].broken)+int(p.anchors[1].broken),'detached':p.detached,'plastic_work_j':p.plastic_work,'max_plastic_edge_change_m':change,'mount_peak_n':p.maximum_force,'closing':graph.panels.closing_topology(p),'seats':p.get('closing_supports',[])})
 return result
