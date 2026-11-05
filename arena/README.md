# Colosseum driving arena

A procedural sand arena using the existing Niva driving runtime and damage skin, built from commit `603c3fd`, then integrated with the shared sandbox controls on `2ad1656`. The shared vehicle owns car dynamics; an optional analytic static-contact provider adds the arena boundary to live and lightweight contacts.

## Run

From the main repository root:

```sh
python3 tools/demo.py arena
# Or directly on this Mac:
/Applications/Godot.app/Contents/MacOS/Godot --path . res://arena/colosseum.tscn
```

Use **Open colosseum arena** in the test yard and **Open test yard** in the arena to switch scenes. Switching starts a fresh car.

The window is titled **Niva / Colosseum sand arena**. W accelerates, S brakes, A/D steer, Space is the handbrake, Q toggles reverse and R repairs/resets. C cycles chase, orbit and overview cameras; drag outside the controls to orbit horizontally and tilt vertically; use the mouse wheel to zoom (2.8–24 m). Orbit is continuous through 360°, pitch is limited to 5–80°, and C/repair resets the orbit distance and tilt predictably. Escape exits. B switches baked/live collision handling. H/Y stage 60/120 km/h wall approaches; U/I stage the ±20° cases. The engine-power and tyre-friction sliders change shared driving parameters and persist through repair/staging. The 480/960/1,920 Hz selector changes live precision. Roof/side fixtures, the wheel-mount test, textured/structure views and the three-impact conditioned sequence are available in the same scrolling controls. The obstacle buttons stage a repaired car on each approach; 1–5 select the same approaches. The three paired-ramp buttons select either lane or the shared seam. F3 exposes optional performance counters.

There are smooth sand, concrete and timber jumps, a curved halfpipe fixture, and adjacent **42° / 24°** ramps. The pair has a common rounded toe, 3.8 m crest height and a continuous 1.24 m blended median, so wheels can straddle different profiles without an artificial collision curb. The stated angles are the straight portions; toe and crest transitions are rounded. Use moderate throttle on the approach. The straddling case deliberately produces strong roll; it does not alter the car to keep it upright.

## Structure and contacts

- `terrain.gd` owns obstacle descriptors, height/normal queries and the matching visible ramp meshes. The paired ramp samples the same triangles that are rendered. Its nominal mesh spacing is 0.2 m longitudinally and 0.05 m across the join; original ramps use approximately 0.35 m spacing.
- `stadium.gd` builds cached meshes, eight seat-culling sectors, repeated piers/arches, material instances and lighting. Twelve seat tiers surround the 152 m diameter drivable area. There are 4,677 repeated instances and 45 unique meshes, rather than one node per chair.
- `vehicle.gd` extends the shared driving vehicle and registers `world_contacts.gd`, which describes the finite annular retaining wall and the straight benchmark wall. The shared `Structure.static_contact` query chooses the nearest enabled box/provider hit, preserving signed point distance, normal and source. Wheel contacts still use oriented tire support. The optional live forecast uses the same provider and skips work away from the predicted edge. There is no per-seat physics work.
- `colosseum.gd` owns staging, camera and concise controls. It uses the current shared damage skin and vehicle profile. Future changes to shared car dynamics carry through without a second implementation.

The terrain is a single-valued heightfield: ramp undersides and overhangs are not drivable. The small timber ribs/supports are visual details over the common contact surface. Seats and upper arches are decorative behind the retaining wall. Sand is a rigid contact surface with procedural material detail, without granular soil or rut simulation. The retaining wall has a finite height; a sufficiently high airborne car can clear it, and an out-of-bounds reset recovers the car.

**The visible straight crash wall at x=40–41, z=−8…8 uses the existing compatible baked selector.** Its geometry and analytic collision derive from the same bounds. It supports the 60/120 km/h, ±20° and conditioned 60→60→120 sequence fixtures. In baked mode the curved ring and body contacts on every ramp can select incremental local damage, with physical root motion retained. The detector uses the actual finite ring and the shared ramp heights/normals; wheel-only suspension landings do not trigger body crushing. Later roof hits accumulate on the damaged car. See [world damage stacking](../docs/WORLD_DAMAGE_STACKING.md) for the approximate response and contact separation rules. In live mode its analytic contacts and forecast can wake actual structural deformation. Decorative seats/pillars remain outside the drivable retaining wall. Scenery does not wake heavy physics merely by existing nearby. The arena exposes `panel_controls: VBoxContainer`, named `PanelControls`, for the production shared panel widget; it uses the public shared damage skin so production panel integration carries through. Deferred structural body separation is not included.

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
# Additional functional controls / live-baked arena parity:
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://arena/verify_parity.gd
# Native crash + functional HUD evidence:
/Applications/Godot.app/Contents/MacOS/Godot --path . res://arena/colosseum.tscn -- --capture-arena-crash
# Compare null-provider default physics with the unmodified prior commit:
python3 arena/prepare_contact_baseline.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://arena/verify_contact_compatibility.gd
# Existing complete shared suites:
python3 tools/demo.py verify --no-import
```

`evidence/validation.json` retains the delivery snapshot of **35 passing checks**. A fresh `python3 tools/demo.py verify-arena --no-import` run writes `verification/arena_validation.json` without overwriting that snapshot. All four original obstacle approaches produced actual takeoff and subsequent landing, finite car states and retained wheels. Both individual paired lanes and the straddled approach remained finite with zero heavy solves. The straddling stress case reached approximately 95° roll; individual lanes remained near 1.2° or less in the recorded runs. No wheel detached in those three cases. The ring stopped the car from all four cardinal approaches without applying an incompatible bake. Maximum visible/contact vertex height error was 0.000000187 m; maximum normal discrepancy was 0.000115 from mesh normal packing.

The existing shared regression command also passed: structural/wheel cases, mounts, driving, adaptive handoff, terrain, wheel load handling, crash library, baked driving, glass, interior, contact sensitivity, conditioned sequential transitions, damage materials and roof cases. `evidence/shared_regression.json` retains that pre-contact-hook pass summary. The parity integration adds a physical-source query interface; current verification and exact-provenance results are documented separately below.

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


## Functional parity integration evidence

`evidence/parity_validation.json` records 32 passing checks. All four wall starts selected one completed bake with zero full solves and zero heavy forecasts. The conditioned sequence completed three impacts without a full solve. The live 60 km/h wall case accumulated approximately 60 kJ plastic work; the live circular-wall impact accumulated approximately 52 kJ while retaining the car inside the arena. The baked circular-wall case retained the car with no deformation solve and no wrong planar bake.

Actual HUD slider signals were exercised, followed by centre reset, timber staging, paired-ramp staging and wall staging. Power, friction, live mode and 1,920 Hz quality persisted. At 55 versus 660 kW, the same two-second acceleration finished at 3.11 versus 12.87 m/s. Friction 0.2 versus 1.2 left 12.83 versus 0.34 m/s after the same two-second brake interval. These are test-fixture outcomes, not calibrated vehicle claims. Roof and mount buttons activate their existing shared fixtures. Panel mechanics are owned by the parallel production integration; this environment does not duplicate them.

`arena_crash_controls.png` is an inspected native render showing actual `front_left_20_120` playback, the matching wall and functional controls. Its capture state is retained in `parity_capture.json`. Original approved environment images remain as the visual baseline. Runtime validation files are written under ignored `verification/`.

The standard 35 environment checks still pass with the provider. On a clear route, the updated arena measured 1.019 ms mean / 1.060 ms p95 per 120 Hz step, compared with 1.036 / 1.063 ms for the practice terrain in the same process; both had zero full solves. Treat these close timings as comparable CPU cost. The added wall contributes 12 counted mesh triangles plus small markers and one label; earlier native viewport budget values describe the approved environment before the parity HUD/wall addition.


The optional-contact interface was compared against unmodified `2ad1656` modules: null-provider live frontal cases and compact driving matched their recorded body states exactly. The earlier provenance failures in this branch were resolved by regenerating the standard, partial, conditioned and roof banks on the frozen shared panel source. Historical environment evidence remains under `evidence/`; current checks write `verification/` reports.

The shared panel widget is now wired to this car. The new **Roof landing**, **Roll left/right** and **Hard roof** buttons stage an ordinary moving car and let the ground-contact detector select a recorded impact. The older roof/side buttons are labelled **Live** and select live simulation. See [the roof-landing slice](../docs/ROOF_LANDING_SLICE.md) for supported speeds, roll, flat-floor matching, measurements and the distinct experimental 3D reference bank.


## Camera regression

`orbit_camera.gd` replaces the previous wall-side X reflection. A finite padded box slab test and a bounded signed-distance trace against the actual finite ring shorten only the intended target-to-camera ray when it is occluded; they never reflect its direction or limit yaw. The radius-limited car contacts and crash selection are unchanged. This small camera adapter does not add general scenery/terrain camera collision.

Run the native event-driven camera check with:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://arena/verify_camera.gd
```

`evidence/camera_validation.json` records 16 passing checks: actual viewport mouse routing through a full turn, four cardinal views relative to the car, wheel zoom limits, pitch limits, C/repair defaults, HUD slider isolation and actual finite box/ring occlusion preserving the intended ray. `evidence/camera_orbit.png` is a visually inspected atlas of actual rendered frames: front/right/rear/left, then near/far zoom. The existing capture-only camera presets remain available.
