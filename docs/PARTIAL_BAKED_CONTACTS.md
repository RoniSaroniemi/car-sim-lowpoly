# Finite-wall footprint coverage

The earlier forecast-assisted manifold fix only repaired the 25mm first-contact signature sensitivity. It did not add finite-wall edge recordings. The previous driving adapter still rejected a car extending beyond the visible planar wall, and the arena parity adapter inherited that policy. There are no inactive regions in the visible wall collider.

`baked_contact_coverage.gd` defines `metadata.contact_coverage` schema1. Legacy clips without it are compatible only with full-width, full-height planar hits. A wider classification band cannot manufacture missing coverage.

The schema records `source=barrier_box`, body-local impact normal, edge side, normalized kept interval/overlap, normalized height interval/full-height flag, attached-vehicle tangent span, local contact centroid and tangent, finite box dimensions and vehicle material/mass/topology identity. Freed wheels are excluded. The tangent is body +Z projected onto the horizontal impact plane; low tangent is body-left for the supported frontal0±30° family. Left/right describes which part of the vehicle lies beyond the wall edge, not a fixed world-Z label.

Coordinates are relative and translation-independent. A wall may be shifted without altering the footprint. A roughly1m solid box with one relevant edge is the reviewed family; a wall of half/twice the authored thickness is the outer allowed range. A narrow post clipping both sides, pure short-end impact or low barrier needs its own recording family.

The bounded authoring list is36 cases: 60/120km/h ×0/±30° body heading ×left/right clipped edge ×25/50/75% requested overlap. Full-width clips remain separate. Runtime selects severity and local normal together with the clipped side and kept interval. Nearest overlap differs by at most0.15 (kept-interval endpoint error at most0.16); this is discrete nearest-footprint approximation, not interpolation of crash physics. In particular a25% edge strike cannot use a full-wall crush.

The standalone partial recorder will inherit the standard recorder's graph capture, effects/panel snapshots, physical timestep and final provenance. Technical proof clips generated against an earlier core are verification-only. Final shipped partial clips must be generated after the combined structural/material/panel/effects source freeze, together with the standard/conditioned/roof banks; source hashes must never be rewritten to make older clips appear current.

Public loading helper: `partial_crash_library.gd`. It keeps the family under `bakes/partial` so old full-wall catalogs and conditioned-state semantics remain intact. Loaded clips may carry the owner's `_input_compatibility` cache outside metadata/frames; the selector excludes explicitly incompatible entries without doing file I/O at contact time.

Schema validation:

```sh
godot --headless --path . --script res://scripts/verify_contact_coverage_schema.gd
```

The schema test uses an actual DrivingVehicle and contact packet, and verifies translation invariance, clipped-side identity, no partial legacy fallback, mass/profile identity and explicit height/end-face fallback.
