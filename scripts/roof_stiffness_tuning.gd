extends RefCounted
## Runtime roof tuning; the frozen offline recipes and source clips stay intact.
const DEFAULT=3.0
const MINIMUM=.5
const MAXIMUM=8.0
const KINDS=['roof_ring','cabin_pillar','cabin_diagonal','roof','cabin_roof_brace','cabin_roof_planar','pillar','roof_crossmember']
static func bounded(value: float) -> float:
 return clampf(value,MINIMUM,MAXIMUM) if is_finite(value) else DEFAULT
static func playback_scale(value: float) -> float:return 1.0/bounded(value)
static func apply_live(g: RefCounted,value: float) -> void:
 value=bounded(value)
 if not g.has_meta('roof_tuning_indices'):
  var indices: Array=[]
  for i in g.links.size():
   var edge: Variant=g.links[i]
   # Mirrors the frozen soft-roof recipe without editing its bake provenance.
   var tie: bool=edge.kind in ['bend','upper_front','front_brace'] and maxf(g.rest[edge.a].y,g.rest[edge.b].y)>1.20
   if edge.kind in KINDS or tie:indices.append(i)
  g.set_meta('roof_tuning_indices',indices)
 var indices: Array=g.get_meta('roof_tuning_indices')
 if indices.is_empty():return
 var step_s: float=g.config.fixed_step_s
 var key: Array=[value,step_s]
 var first: int=indices[0]
 # Fixture material changes can replace parameters without changing the graph.
 # A representative roof member detects that replacement, including reset to
 # the same material profile. No per-substep parameter rebuild is needed.
 var expected: float=float(g.config.links[first].stiffness_n_per_m)*.08*value
 if g.get_meta('roof_tuning_key',[])==key and is_equal_approx(g.links[first].stiffness_n_per_m,expected):return
 for i in indices:
  var edge: Variant=g.links[i];var raw: Dictionary=g.config.links[i]
  edge.stiffness_n_per_m=float(raw.stiffness_n_per_m)*.08*value
  edge.yield_n=float(raw.yield_n)*.02*value
  edge.compliance=1.0/edge.stiffness_n_per_m
  edge.max_compression=maxf(float(raw.max_compression),.82)
  edge.damping_ns_per_m=float(raw.damping_ns_per_m)*.6*sqrt(value)
  edge.damping_fraction=1-exp(-edge.damping_ns_per_m*edge.weight_sum*step_s)
 g.set_meta('roof_tuning_key',key)
