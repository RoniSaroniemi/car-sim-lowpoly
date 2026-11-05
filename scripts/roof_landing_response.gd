extends RefCounted
## Art-directed derived playback. Recorded physics and provenance stay immutable.
const GAIN=4.0
static var preparations:=0
const Attachment=preload('res://scripts/car_attachment.gd')
static func _basis(points: PackedVector3Array) -> Basis:
 var x: Vector3=(points[12]+points[13]-points[4]-points[5]).normalized()
 var z: Vector3=points[5]-points[4];z=(z-x*z.dot(x)).normalized()
 return Basis(x,z.cross(x).normalized(),z).orthonormalized()
static func _anchor(points: PackedVector3Array) -> Vector3:return (points[4]+points[5]+points[12]+points[13])*.25
static func _minimum(g: RefCounted,f: Dictionary) -> float:
 var minimum:=INF
 for i in f.points.size():
  if g.wheels.by_node.has(i):continue
  minimum=minf(minimum,f.points[i].y-g.radii[i])
 for p in f.panels.panels:
  if p.detached:continue
  for point in p.points:minimum=minf(minimum,point.y-.04)
 return minimum
static func prepare(g: RefCounted,raw: Dictionary) -> Dictionary:
 if raw.get('_roof_response_gain',0)==GAIN:return raw
 if raw.has('_roof_response'):return raw._roof_response
 preparations+=1
 var frames: Array=[];var rest_anchor:=_anchor(g.rest)
 for source in raw.frames:
  var f: Dictionary=source.duplicate()
  f.points=source.points.duplicate();f.velocities=source.velocities.duplicate();f.damage=source.damage.duplicate();f.lengths=source.lengths.duplicate()
  f.panels=source.panels.duplicate(true)
  var basis:=_basis(source.points);var center:=_anchor(source.points)
  var deltas:=PackedVector3Array();deltas.resize(g.rest.size())
  for i in g.rest.size():
   if g.wheels.by_node.has(i) or g.rest[i].y<1.15:continue
   var local: Vector3=basis.transposed()*(source.points[i]-center)
   var compression: float=minf(0,local.y-(g.rest[i]-rest_anchor).y)
   var elapsed: float=float(frames.size())/float(raw.metadata.sample_hz)
   # Deliberately fragile game roof: once loaded, bake playback carries a
   # minimum progressive buckle, including low-speed or static roof support.
   var buckle: float=.55*(1-exp(-elapsed*5.0))
   compression=minf(compression,-buckle/maxf(1,GAIN))
   deltas[i]=basis.y*maxf(-minf(.85,maxf(0,local.y-.20)),compression*(GAIN-1))
   f.points[i]+=deltas[i];f.damage[i]=clampf(source.damage[i]*GAIN,0,1)
  for p in f.panels.panels:
   p.points=p.points.duplicate();p.velocity=p.velocity.duplicate()
   if p.detached:continue
   var prototype: Dictionary=g.panels.find(p.id)
   for k in p.points.size():
    var binding: Dictionary=prototype.bindings[k];var delta:=Vector3.ZERO
    for j in binding.ids.size():delta+=deltas[binding.ids[j]]*binding.weights[j]
    p.points[k]+=delta
  var shift:=Vector3.UP*(_minimum(g,source)-_minimum(g,f))
  for i in f.points.size():f.points[i]+=shift
  for p in f.panels.panels:
   if p.detached:continue
   for k in p.points.size():p.points[k]+=shift
   if p.has('reduced_data'):p.reduced_data.center+=shift
  for i in g.links.size():
   var edge: Variant=g.links[i]
   if deltas[edge.a].length_squared()+deltas[edge.b].length_squared()<.0000001:continue
   var difference: float=f.points[edge.a].distance_to(f.points[edge.b])-source.points[edge.a].distance_to(source.points[edge.b])
   f.lengths[i]=maxf(.02,source.lengths[i]+difference)
  for p in f.panels.panels:
   if p.detached:continue
   var prototype: Dictionary=g.panels.find(p.id)
   var original: Dictionary=source.panels.panels.filter(func(item):return item.id==p.id)[0]
   for i in p.edges.size():
    var edge: Dictionary=prototype.edges[i]
    var difference: float=p.points[edge.a].distance_to(p.points[edge.b])-original.points[edge.a].distance_to(original.points[edge.b])
    p.edges[i].length=maxf(.02,p.edges[i].length+difference)
  f.effects=source.effects.duplicate();f.effects.surface=source.effects.surface.duplicate(true)
  for field in ['damage','compression']:
   f.effects.surface[field]=source.effects.surface[field].duplicate()
   for i in g.rest.size():
    if g.rest[i].y>=1.15:f.effects.surface[field][i]=clampf(f.effects.surface[field][i]*GAIN,0,1)
  frames.append(f)
 # Add the derivative of the cosmetic displacement to the recorded velocities.
 for n in frames.size():
  var a:=maxi(0,n-1);var b:=mini(frames.size()-1,n+1)
  var dt: float=float(b-a)/float(raw.metadata.sample_hz)
  for i in g.rest.size():frames[n].velocities[i]+=((frames[b].points[i]-raw.frames[b].points[i])-(frames[a].points[i]-raw.frames[a].points[i]))/dt
  for p in frames[n].panels.panels:
   var pa: Dictionary=frames[a].panels.panels.filter(func(item):return item.id==p.id)[0]
   var pb: Dictionary=frames[b].panels.panels.filter(func(item):return item.id==p.id)[0]
   var oa: Dictionary=raw.frames[a].panels.panels.filter(func(item):return item.id==p.id)[0]
   var ob: Dictionary=raw.frames[b].panels.panels.filter(func(item):return item.id==p.id)[0]
   for i in p.velocity.size():p.velocity[i]+=((pb.points[i]-ob.points[i])-(pa.points[i]-oa.points[i]))/dt
 var result: Dictionary=raw.duplicate();result.erase('_surface_track');result.frames=frames;result['_roof_response_gain']=GAIN
 result.metadata=raw.metadata.duplicate()
 result.metadata['playback_response']={'mode':'art_directed','roof_crumple_gain':GAIN,'source_clip_id':raw.metadata.id,'source_physics_metrics_only':true,'response_script_sha256':FileAccess.get_sha256('res://scripts/roof_landing_response.gd')}
 raw['_roof_response']=result
 return result
static func view(data: Dictionary,time: float,horizontal_delta: Vector3) -> Dictionary:
 if horizontal_delta.length_squared()<.000001:return data
 var result: Dictionary=data.duplicate();result.frames=data.frames.duplicate()
 var sample: float=clampf(time*float(data.metadata.sample_hz),0,data.frames.size()-1)
 for index in [floori(sample),ceili(sample)]:
  var source: Dictionary=data.frames[index];var f: Dictionary=source.duplicate()
  var x: float=(source.points[8].x+source.points[9].x+source.points[10].x+source.points[11].x)*.25
  var x0: float=(data.frames[0].points[8].x+data.frames[0].points[9].x+data.frames[0].points[10].x+data.frames[0].points[11].x)*.25
  var vx: float=(source.velocities[8].x+source.velocities[9].x+source.velocities[10].x+source.velocities[11].x)*.25
  var reference_vx: float=(data.frames[0].velocities[8].x+data.frames[0].velocities[9].x+data.frames[0].velocities[10].x+data.frames[0].velocities[11].x)*.25
  var shift: Vector3=horizontal_delta*((x-x0)/maxf(.1,reference_vx));var boost: Vector3=horizontal_delta*(vx/maxf(.1,reference_vx))
  f.points=source.points.duplicate();f.velocities=source.velocities.duplicate()
  for i in f.points.size():f.points[i]+=shift;f.velocities[i]+=boost
  f.panels=source.panels.duplicate(true)
  for p in f.panels.panels:
   p.points=p.points.duplicate();p.velocity=p.velocity.duplicate()
   for i in p.points.size():p.points[i]+=shift;p.velocity[i]+=boost
   if p.has('reduced_data'):p.reduced_data.center+=shift;p.reduced_data.linear+=boost
  result.frames[index]=f
 return result
