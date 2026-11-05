extends RefCounted
## Explicit game tuning for weak roof/pillar buckling, without changing rails.
static func apply(g: RefCounted) -> void:
 if g.has_meta('soft_roof_v1'):return
 var kinds: Array=['roof_ring','cabin_pillar','cabin_diagonal','roof','cabin_roof_brace','cabin_roof_planar','pillar','roof_crossmember']
 for link in g.links:
  var roof_tie: bool=link.kind in ['bend','upper_front','front_brace'] and maxf(g.rest[link.a].y,g.rest[link.b].y)>1.20
  if link.kind not in kinds and not roof_tie:continue
  link.stiffness_n_per_m*=.08;link.yield_n*=.02
  link.max_compression=maxf(link.max_compression,.82)
  link.compliance=1.0/link.stiffness_n_per_m
  link.damping_ns_per_m*=.6
  link.damping_fraction=1-exp(-link.damping_ns_per_m*link.weight_sum*float(g.config.fixed_step_s))
 g.set_meta('soft_roof_v1',true)
