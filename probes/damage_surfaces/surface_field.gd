extends RefCounted
## Recorded graph signals only. Cosmetic; no solver, no per-frame mesh rebuild.
var graph_ref: WeakRef
var damage:=PackedFloat32Array()
var contact:=PackedFloat32Array()
var compression:=PackedFloat32Array()
var compression_override:=PackedFloat32Array()
var build_us:=0
var updates:=0
func setup(graph: RefCounted) -> void:
 graph_ref=weakref(graph)
 damage.resize(38);contact.resize(38);compression.resize(38)
func update() -> void:
 var began: int=Time.get_ticks_usec()
 var graph: RefCounted=graph_ref.get_ref()
 damage=graph.node_damage.duplicate();contact=graph.node_contact.duplicate()
 compression.resize(38);compression.fill(0)
 for edge in graph.links:
  if edge.a>=28 or edge.b>=28:continue
  var strain: float=maxf(0,1.0-edge.length/maxf(.001,edge.original))
  compression[edge.a]=maxf(compression[edge.a],strain)
  compression[edge.b]=maxf(compression[edge.b],strain)
 if compression_override.size()==38:compression=compression_override.duplicate()
 build_us+=Time.get_ticks_usec()-began;updates+=1
static func history(graph: RefCounted,clip: Dictionary) -> Array:
 var output: Array=[];var peak:=PackedFloat32Array();peak.resize(38);peak.fill(0)
 for frame in clip.frames:
  for i in graph.links.size():
   var edge=graph.links[i]
   if edge.a>=28 or edge.b>=28:continue
   var strain: float=maxf(0,1.0-float(frame.lengths[i])/maxf(.001,edge.original))
   peak[edge.a]=maxf(peak[edge.a],strain);peak[edge.b]=maxf(peak[edge.b],strain)
  output.append(peak.duplicate())
 return output
func at(rest_point: Vector3) -> Vector3:
 var graph: RefCounted=graph_ref.get_ref()
 var station:=0
 for i in 6:
  if rest_point.x>=float(graph.config.station_x[i]):station=i
 var t: float=clampf((rest_point.x-float(graph.config.station_x[station]))/(float(graph.config.station_x[station+1])-float(graph.config.station_x[station])),0,1)
 var value:=Vector3.ZERO
 for next in 2:
  var s: int=station+next
  var ty: float=clampf((rest_point.y-.58)/(float(graph.config.station_top_y[s])-.58),0,1)
  var tz: float=clampf((rest_point.z+float(graph.config.station_half_width[s]))/(2*float(graph.config.station_half_width[s])),0,1)
  for corner in 4:
   var w: float=(t if next else 1-t)*(ty if corner>=2 else 1-ty)*(tz if corner%2 else 1-tz)
   var index: int=s*4+corner
   value+=Vector3(damage[index],contact[index],compression[index])*w
 return value
