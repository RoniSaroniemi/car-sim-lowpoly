# Colosseum driving arena

A procedural sand arena using the existing Niva driving runtime and damage skin, built from commit `603c3fd`. This is an isolated environment scene: car dynamics, power, grip, steering and shared physics files are unchanged.

## Run

From the main repository root:

```sh
python3 tools/demo.py arena
# Or directly on this Mac:
/Applications/Godot.app/Contents/MacOS/Godot --path . res://arena/colosseum.tscn
```

Use **Open colosseum arena** in the test yard and **Open test yard** in the arena to switch scenes. Switching starts a fresh car.

The window is titled **Niva / Colosseum sand arena**. W accelerates, S brakes, A/D steer, Space is the handbrake, Q toggles reverse and R repairs/resets. C cycles chase, orbit and overview cameras; drag to orbit. Escape exits. The obstacle buttons stage a repaired car on each approach; 1–5 select the same approaches. The three paired-ramp buttons select either lane or the shared seam. F3 exposes optional performance counters.

There are smooth sand, concrete and timber jumps, a curved halfpipe fixture, and adjacent **42° / 24°** ramps. The pair has a common rounded toe, 3.8 m crest height and a continuous 1.24 m blended median, so wheels can straddle different profiles without an artificial collision curb. The stated angles are the straight portions; toe and crest transitions are rounded. Use moderate throttle on the approach. The straddling case deliberately produces strong roll; it does not alter the car to keep it upright.

## Structure and contacts

- `terrain.gd` owns obstacle descriptors, height/normal queries and the matching visible ramp meshes. The paired ramp samples the same triangles that are rendered. Its nominal mesh spacing is 0.2 m longitudinally and 0.05 m across the join; original ramps use approximately 0.35 m spacing.
- `stadium.gd` builds cached meshes, eight seat-culling sectors, repeated piers/arches, material instances and lighting. Twelve seat tiers surround the 152 m diameter drivable area. There are 4,677 repeated instances and 45 unique meshes, rather than one node per chair.
- `vehicle.gd` extends the shared driving vehicle only to add the finite-height circular retaining-wall contact. Its inexpensive radial broadphase skips body-wall tests away from the edge. There is no per-seat physics work.
- `colosseum.gd` owns staging, camera and concise controls. It uses the current shared damage skin and vehicle profile. Future changes to shared car dynamics carry through without a second implementation.

The terrain is a single-valued heightfield: ramp undersides and overhangs are not drivable. The small timber ribs/supports are visual details over the common contact surface. Seats and upper arches are decorative behind the retaining wall. Sand is a rigid contact surface with procedural material detail, without granular soil or rut simulation. The retaining wall has a finite height; a sufficiently high airborne car can clear it, and an out-of-bounds reset recovers the car.

**The curved ring uses rigid contact response, without selecting a crash animation.** The existing bank records planar full-width wall impacts, so this scene explicitly declines to apply those incompatible bakes to a curved wall, pillar or narrow corner. It also does not wake the heavy deformation solver merely because scenery is nearby. New arena-specific damage contacts/bakes are a separate integration task. This scene contains neither the separate panel-articulation probe nor deferred body separation work.

## Materials and lighting

All arena geometry and materials are authored procedurally here; no downloaded or generated bitmap assets are required. Shared world-scale shaders provide sand grain and broad variation, stone/concrete pores and joints, and timber grain/plank seams. Surface-gradient bump perturbs the actual shading normal. Vertex masks place dirt and cavity darkening at bases, seat/riser seams, sheltered backs and wood joints; these are material/occlusion cues, not painted directional light. Fine detail is attenuated at distance.

One shadowed directional sun supplies direct light. The procedural sky provides ambient fill and reflections to the dynamic car. Filtered shadow maps retain a readable sun direction and moving car shadow. No parked-car shadow is painted into the floor.

**No LightmapGI bake was performed.** Compatibility can render baked lightmaps, but baking requires the editor/RenderingDevice workflow, static bake geometry and suitable unique UV2. This runtime-generated, instanced scene currently uses sky ambient plus authored cavity shading. It does not claim ray-baked ambient occlusion or indirect illumination. See the official [renderer comparison](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) and [LightmapGI limitations and dynamic probes](https://docs.godotengine.org/en/stable/classes/class_lightmapgi.html). The renderer remains Compatibility.

## Verification and native evidence

```sh
# Geometry/contact contracts and actual driving:
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://arena/verify.gd
# Recreate actual native-window captures:
/Applications/Godot.app/Contents/MacOS/Godot --path . res://arena/colosseum.tscn -- --capture-arena
# Native viewport budget (opens a temporary window):
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://arena/benchmark.gd
# Existing complete shared suites:
python3 tools/demo.py verify --no-import
```

`evidence/validation.json` retains the delivery snapshot of **35 passing checks**. A fresh `python3 tools/demo.py verify-arena --no-import` run writes `verification/arena_validation.json` without overwriting that snapshot. All four original obstacle approaches produced actual takeoff and subsequent landing, finite car states and retained wheels. Both individual paired lanes and the straddled approach remained finite with zero heavy solves. The straddling stress case reached approximately 95° roll; individual lanes remained near 1.2° or less in the recorded runs. No wheel detached in those three cases. The ring stopped the car from all four cardinal approaches without applying an incompatible bake. Maximum visible/contact vertex height error was 0.000000187 m; maximum normal discrepancy was 0.000115 from mesh normal packing.

The existing shared regression command also passed: structural/wheel cases, mounts, driving, adaptive handoff, terrain, wheel load handling, crash library, baked driving, glass, interior, contact sensitivity, conditioned sequential transitions, damage materials and roof cases. `evidence/shared_regression.json` retains the pass summary.

The saved PNGs are actual native Godot renders, visually inspected for alignment, material scale, car illumination and shadows: overview, chase, car lighting, timber/stone/sand details, airborne sand jump, paired ramps and the car straddling their join. `evidence/captures.json` records wheel positions, sampled floor heights and solver counts at each capture. `sand_jump.png` is captured only when all four tire support points clear the floor; it is not a posed static car.

## Measured budget

Apple M3, Godot 4.7.2 Compatibility, 1440×900; values are retained in `evidence/native_budget.json` and `validation.json`:

| Measurement | Result |
|---|---:|
| Repeated instances / arena triangle instances | 4,677 / 206,050 |
| Unique meshes | 45 |
| Serialized mesh-array payload | 5,448,908 bytes |
| Instance transform payload | 224,496 bytes |
| Procedural generation CPU time | 723 ms |
| Native overview draws / reported primitives | 114 / 263,674 |
| Native chase draws / reported primitives | 263 / 174,674 |
| Car-only control draws / primitives | 117 / 57,624 |
| Moving arena physics, mean / p95 | 1.036 / 1.101 ms per 120 Hz step |
| Same-route practice terrain, mean / p95 | 1.067 / 1.113 ms per step |
| Mixed arena floor query, mean | 1.91 µs |
| Heavy solver / forecast steps on normal obstacle drives | 0 / 0 |

The close physics timings show comparable load, not proof that the arena is faster. Mesh/transform payload estimates exclude engine and GPU allocation overhead. Viewport counters include rendering/shadow behavior. Native CPU render submission averaged about 9.9–10.3 ms including possible waiting; GPU timestamps were unavailable, so these measurements do not establish a GPU frame time or FPS guarantee. Shader cost, shadows and resolution still affect the actual rendering budget.
