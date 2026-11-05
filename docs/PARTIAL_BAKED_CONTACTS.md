# Finite-wall footprint coverage

The earlier forecast-assisted manifold fix only repaired the 25mm first-contact signature sensitivity. It did not add finite-wall edge recordings. The previous driving adapter still rejected a car extending beyond the visible planar wall, and the arena parity adapter inherited that policy. There are no inactive regions in the visible wall collider.

`baked_contact_coverage.gd` defines `metadata.contact_coverage` schema1. Legacy clips without it are compatible only with full-width, full-height planar hits. A wider classification band cannot manufacture missing coverage.

The schema records `source=barrier_box`, body-local impact normal, edge side, normalized kept interval/overlap, normalized height interval/full-height flag, attached-vehicle tangent span, local contact centroid and tangent, finite box dimensions and vehicle material/mass/topology identity. Freed wheels are excluded. The tangent is body +Z projected onto the authored wall’s ±X plane (not the averaged corner-contact normal); low tangent is body-left for the supported frontal0±30° family. Left/right describes which part of the vehicle lies beyond the wall edge, not a fixed world-Z label.

Coordinates are relative and translation-independent. A wall may be shifted without altering the footprint. A roughly1m solid box with one relevant edge is the reviewed family; a wall of half/twice the authored thickness is the outer allowed range. A narrow post clipping both sides, pure short-end impact or low barrier needs its own recording family.

The base authoring list is36 cases: 60/120km/h ×0/±30° body heading ×left/right clipped edge ×25/50/75% requested overlap. The actual driven matrix requires12 targeted refinements, giving48 total: ±10° opposite-edge75% (4 clips), ±10° near-edge25% (4), and ±20° opposite-edge50% (4), all at both speeds. The final eight contain measured spherical-probe corner normals; they cannot be replaced by a planar partial recording. Full-width clips remain separate. Runtime selects severity and local normal together with the clipped side and kept interval. Nearest overlap differs by at most0.15 (kept-interval endpoint error at most0.16); this is discrete nearest-footprint approximation, not interpolation of crash physics. In particular a25% edge strike cannot use a full-wall crush.

The standalone partial recorder inherits the standard recorder's graph capture, effects/panel snapshots, physical timestep and final provenance. Technical proof clips generated against an earlier core are verification-only. Final shipped partial clips must be generated after the combined structural/material/panel/effects source freeze, together with the standard/conditioned/roof banks; source hashes must never be rewritten to make older clips appear current.

Public loading helper: `partial_crash_library.gd`. It keeps the family under `bakes/partial` so old full-wall catalogs and conditioned-state semantics remain intact. Loaded clips may carry the owner's `_input_compatibility` cache outside metadata/frames; the selector excludes explicitly incompatible entries without doing file I/O at contact time.

Schema validation:

```sh
godot --headless --path . --script res://scripts/verify_contact_coverage_schema.gd
```

The schema test uses an actual DrivingVehicle and contact packet, and verifies translation invariance, clipped-side identity, no partial legacy fallback, mass/profile identity and explicit height/end-face fallback.


Authoring and registration

`partial_crash_recorder.gd` subclasses the shared recorder, leaving its full snapshots, final metadata and physical provenance intact. It places a finite1×3×16m box at X=0, starts the vehicle3m before it, shifts the attached footprint to the requested lateral overlap, and runs offline preparation. It registers the first real sphere/box distance zero using bisection, then records the shared full simulation. The requested fraction is a launcher target; metadata stores the actual measured fraction. Auxiliary effects and inactive panels synchronize after placement and again at registration so launcher teleports do not become false damage. A3s no-contact preparation limit fails cleanly.

At runtime, an expanded-box sweep is only a broad phase. Conservative advancement confirms the unpadded structural sphere/box contact before playback. This corrects premature contact at rounded box corners. Forecast arming and50/100mm classification bands remain separate; they cannot start replay. Candidate-specific normal/coverage is recomputed for each band. Corner-to-planar substitution and wall-plane alignment errors over18.01° are rejected, as are opposite clipped sides. Severity bins use closing speed against the authored ±X plane, while impact-zone normals and impulse normalization use the clip’s actual contact normal. No full structural solve or legacy forecast runs.

A dirty vehicle still requires the existing conditioned-state transition. Coverage adds an extra condition; it never authorizes pristine replay over existing damage. The current partial family is pristine only. True end faces, short/narrow obstacles, overlap outside the recorded tolerance and different material/mass/topology remain rigid fallback. The circular arena perimeter is not a barrier-box source. This is a bounded nearest recorded family, not arbitrary obstacle matching or deformation blending.

Build the authoritative bank only on the combined frozen panel/material/effects source:

```sh
godot --headless --path . --script res://scripts/bake_partial_crashes.gd -- --quality=4 --directory=res://bakes/partial
```

`--only=partial_020_60_right_50,...` supports bounded rebuilding. The catalog is local to `bakes/partial/library.json`. Technical proof used quality1 and `verification/partial_bakes`; those clips are intentionally excluded from the repository and must not be promoted as production physical recordings. Standard/conditioned/roof authoring sources were not changed by this work.

Reproduce the actual adapter tests after baking:

```sh
godot --headless --path . --script res://scripts/verify_contact_coverage_schema.gd
godot --headless --path . --script res://scripts/verify_partial_baked_driving.gd -- --directory=res://bakes/partial
godot --headless --path . --script res://scripts/verify_partial_baked_controls.gd -- --directory=res://bakes/partial
godot --headless --path . --script res://scripts/verify_baked_contact_sensor.gd
godot --headless --path . --script res://scripts/verify_driving_bakes.gd
```

Evidence from the isolated technical proof (Godot4.7.2, AppleM3; not a post-panel production bank):

- Actual DrivingVehicle and ArenaVehicle:196/196 triggered across60/120km/h,0/±10/±20/±30°, full-width and left/right25/50/75% overlap. Every case kept its graph, with0 full structural steps and0 legacy forecast calls. The old strict finite-width gate rejected the partial cases; stricter true-sphere contact plus the40-case planar/refinement bank still missed16/196. Eight explicit corner clips resolved those measured misses.
- Four actual replay→rigid aftermath cases retained0.388–0.404m maximum permanent member rest change. Contact confirmation gap was within0.4µm of the box surface, with no early playback; mass and graph remained unchanged and points stayed finite. Native20°50% corner replay reported0m entry position jump and3.1e-8m/s entry velocity jump.
- Moving-away forecast cancellation, wall-edge near miss, short wall and tiny5% footprint all passed without unsupported playback. Existing27 sensor checks and full-width driving bake regression passed.
- Clear-road eligibility query5.5µs with0 actual sweeps/forecast checks/rankings. Per-case mean near sensor time: median87µs,95th percentile105µs,max229µs. The forecast component: median51µs,95th57µs,max79µs per forecast. These are local measured means, not worst-frame guarantees; contact selection also ranks the48 loaded clips only at actual contact.

The [196-case table](evidence/partial_baked/driving_matrix.csv) and [control results](evidence/partial_baked/controls.json) retain the measurements. Native captures show [before impact](evidence/partial_baked/partial_corner_before.png), [registered corner replay](evidence/partial_baked/partial_corner_impact.png) and [damaged rigid aftermath](evidence/partial_baked/partial_corner_aftermath.png). The yellow5×3×3 grid is a diagnostic rest-space overlay; the visible car is the real driven/rendered vehicle. Recreate captures with `godot --path . --script res://tools/probes/partial_coverage/capture.gd -- --directory=res://bakes/partial`.
