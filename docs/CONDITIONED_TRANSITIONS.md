# Conditioned transitions in the main simulation

The runtime helper supports a bounded **60 km/h frontal → 60 km/h +20° → 120 km/h −20°** family. It selects a clip by incoming irreversible state and impact, rather than stacking absolute pristine-car clips. General deformation-delta composition remains rejected by the earlier measured errors.

The production sandbox now loads the regenerated three-stage bank, selects successors at actual contact, preserves already released wheels and accumulated body/glass/interior damage, then returns to lightweight driving. Run `python3 tools/demo.py drive-sequence` or click **Three baked impacts**.

## Owned API

`conditioned_crash_transitions.gd` extends RefCounted and never steps a solver:

```gdscript
var state = Conditioned.describe(graph) # or describe(graph, snapshot)
Conditioned.stamp(clip, initial_snapshot, graph, chain_id, step_index)
var compatibility = Conditioned.compatible(graph, clip)
var selection = Conditioned.choose(graph, impact_signature, conditioned_clips)
var next_fixture = Conditioned.next_supported(graph, conditioned_clips)
var old_free_wheels = Conditioned.detached_wheel_indices(graph) # indices 0..3
var old_free_nodes = Conditioned.detached_nodes(graph) # nodes 34..37
Conditioned.irreversible_floor(graph, previous_snapshot)
```

`compatible` and `choose` also accept an optional explicit current snapshot for deterministic tests. `choose` returns the existing accepted/index/id/score schema, actual and recorded speed, state diagnostics, conditioned chain/step and candidate rejection reasons. Conditioned speed coverage is limited to ±15% of an authored transition; the only available successor is never stretched to a completely different severity. Unsupported state/impact combinations return `accepted=false` for the caller's cheap rigid fallback.

The descriptor compares:

- Actual material properties, profile version, mass, rest topology and wheel structural profiles via a fingerprint.
- Canonical structural shape relative to rear lower rails, with 25 mm maximum body-node residual. This datum is specific to the frontal family, not a claim of arbitrary topology/roof-history support.
- Attached wheel positions with 150 mm tolerance, allowing ordinary suspension/steering registration; detached world positions are excluded.
- Normalized plastic lengths within 0.00002 and peak node/link damage within 0.000002; exact broken-link and wheel attachment/joint flags.
- Permanent wheel alignment/lateral rest state. Spin phase and ordinary steering orientation are handled by player registration, not mistaken for irreversible damage.
- Glass/interior profile/stage/tear/mask/release/plastic/deployment state. Clocks, live motion caches, particle positions and cloth/elastic poses are excluded from the irreversible key. Float scalars are quantized at 10⁻⁶ to avoid meaningless serialization noise. Attachment-local cloth pose residual is a possible later diagnostic; it is not a substitute for matching damage.

The descriptor includes a diagnostic `state_key`; compatibility measures numeric residuals and irreversible flags rather than requiring every raw float to hash identically. These tolerances are explicit first-integration limits to test, not calibrated bounds for equivalent crashes.

## Implemented central wiring

1. Load the conditioned catalog once from `bakes/conditioned/`. Keep it separate from the standard root 27-clip bank.
2. Before choosing another pristine clip for a damaged car, call `choose(graph, signature, conditioned_library)`. Replace the unconditional one-bake/clean-only rejection with this supported-transition path. If no conditioned state matches, keep rigid response; do not heal the car with a pristine fallback.
3. The contact sensor and wall-coverage checks must skip previously detached nodes. A wheel rolling away from the car must not define the next car-impact footprint or reject it for being outside the wall span.
4. Pass the chosen transition through the same live-graph player. Its initial effects already contain previous damage. `begin_playback` should initialize release history without re-emitting old events.
5. Snapshot already-detached indices before each `Clip.apply`, retain their original world position/velocity/rotation/spin afterward, and advance only those existing mass nodes through coarse world contacts. Do not reposition them with the car or restore a future clip's recorded old-wheel trajectory. Newly detached wheels may follow their current clip until its ownership handoff.
6. Apply the irreversible floor after samples if needed for float-noise safety: max node/link damage and plastic work, union broken links, and preserve released/joint-broken states. It does not clamp every plastic length to a monotonic direction; reverse plastic loading is physically possible. It does not manufacture new wheel failures from clean clips.
7. On completion, retain the existing rigid-damaged aggregate handoff. Root position/momentum is owned once by the selected trajectory; never add multiple clips' root motions or impulses. Repair resets the chain state normally.

## Offline authoring and deterministic fixture

`conditioned_crash_authoring.gd` uses the shared `VehicleSimulation` and `Clip.local_frame`. The first stage is an exact copy of the rebuilt standard 60 km/h frontal clip, so normal bank playback reaches the precise state from which stage 2 is authored. It is not independently re-recorded from a different suspension pose.

For the two follow-ups, the existing live graph keeps its damaged geometry, plastic lengths, broken supports and effects. The fixture reorients/relaunches attached car nodes only; released wheels retain their world state. It calls `effects.resume_live()` and `effects.synchronize()` after the imposed pose/velocity boundary, then records 4,800 shared 1,920 Hz steps into 301 states at 120 Hz (or follows the prefix’s explicitly selected authoring quality). This is offline authoring, not runtime solver work.

The reusable staging call is:

```gdscript
Author.prepare(vehicle.solver, {"speed": 60.0, "angle": 20.0})
# Default wall_x is the current graph.barrier_min.x.
# Root then captures the compact shape/sets DRIVE, without reset/repair.
```

The UI can stage the next supported hit after playback finishes, preserving slider state. This fixture proves the chain and is not continuous driving between three independent walls. Natural subsequent collisions use the same state/impact selector; unsupported histories stay explicit rigid fallback.

Generate only after root freezes promoted materials and both effects controllers:

```sh
godot --headless --path . --script res://scripts/bake_conditioned_transitions.gd -- \
  --prefix=res://bakes/impact_000_60.crashclip \
  --output=res://bakes/conditioned --chain=front_60_60_120
```

The author rejects legacy no-effects/version2 prefixes, mismatched source fingerprints and an unpromoted material profile. Root must bake the standard version3 bank with `niva_multiaxis_v1` first. The prefix's input fingerprints are carried forward; follow-ups also identify the conditioned authoring code. No body/material mass is added by this module.

`save_library` writes compressed clips and a small explicit catalog in the requested directory. The catalog stores paths, speed/angle, chain/step and predecessor/successor keys; the complete descriptors live inside each clip's metadata.

## Verification

```sh
godot --headless --path . --script res://scripts/verify_conditioned_transitions.gd
```

The focused helper suite checks rigid-pose invariance, shape/plastic/material/failure/effects rejection, clock-insensitive effects identity, state+impact selection, explicit unsupported fallback, detached-wheel exclusion and fixture preservation, irreversible merging and catalog disk round-trip. It does not falsely label old version2/probe records as a final production bank. Root's final integration suite must additionally play all three generated stages with real glass/interior state and check monotonic body/effects damage, no reattachment/teleport, exact sample replay and zero full solver during every playback.

Main integration is verified by `python3 tools/demo.py verify-sequence --no-import`: 27 sensor, 28 transition helper, 42 actual-bank and 19 driving-sequence checks. The successor remains compatible immediately after playback and after one second of ordinary coarse settling. Arbitrary crash histories still require additional conditioned recordings.
