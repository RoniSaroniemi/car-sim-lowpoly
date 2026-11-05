# Multi-car baked collision probe

This isolated proof demonstrates two moving cars and three cars contacting in the same physics tick. Actual world motion comes from a shared contact owner; prerecorded body deformation is sampled in each car's local frame. It does **not** replay two independent wall-root trajectories.

Originally authored on `603c3fd`, imported from probe commit `5244f14`, and reverified against the current main checkout. The opposed composite has been regenerated against current sources. No production runtime, existing main bake, main scene or vehicle profile changes are required by this example. This is a **planar contact/deformation adapter**, with condensed attached wheels and a flat-floor constraint. It is not yet the production driving sandbox's 3D tire/suspension solver. The example keeps opening panels condensed and uses the body skin for their shape; it does not run the production panel cages or support independently detached panels.

## Run and steer

```sh
# From the repository root, on any supported platform:
python3 tools/demo.py multicar
python3 tools/demo.py verify-multicar --no-import
```

Choose a case on the left. Quarter speed starts enabled. W accelerates, S brakes and A/D steer in **Drive into other cars**. This case starts at rest, with enough runway to reach deformation-triggering severity. R repairs/resets the selected case; P pauses; Space replays its recent samples. Drag to orbit and use the wheel to zoom. Save/Load replay persists up to six seconds in `verification/multicar_recording.bin`.

Replay is snapshot playback, including body shape, glass state and flying glass particles. Reset before starting another physical run; arbitrary continuation from an arbitrary replay sample is not provided.

| Case | Actual root motion | Deformation selection |
| --- | --- | --- |
| Head-on | Two 1,210 kg cars at 60 km/h each, opposite directions | Existing frontal 60 for each |
| Moving into parked | 1,210 kg car at 120 km/h into an equal-mass stationary car | Existing frontal 60 for each; struck car is pushed forward |
| Three simultaneous | Stationary middle car; two outer cars at 84.85 km/h inwards | One new opposed front/rear composite for the middle; frontal 60 for each outer car |
| Drive | User starts at rest and drives into parked cars | Same contact/selection owner |
| Partial corner | Offset 120 km/h collision | Physical response; explicit unsupported-shape fallback |
| Low speed | 2 m/s approach | Physical response; no deformation clip |

The three-car fixture intentionally chooses the outer speeds so that each middle-car contact receives approximately the supported 60 km/h wall-equivalent deformation energy. The middle car's **total** assigned severity is approximately 84.85 km/h; it does not receive two independently summed pristine clips.

## Evidence

All images are actual native Godot Compatibility rendering, inspected after capture. No generated or composited mockups.

- [Two cars: before](../probes/multicar/evidence/head_on_before.png), [contact/deformation](../probes/multicar/evidence/head_on_impact.png), [aftermath](../probes/multicar/evidence/head_on_after.png).
- [Moving into parked: before](../probes/multicar/evidence/parked_before.png), [contact](../probes/multicar/evidence/parked_impact.png), [aftermath](../probes/multicar/evidence/parked_after.png).
- [Three cars: before](../probes/multicar/evidence/triple_before.png), [contact/deformation](../probes/multicar/evidence/triple_impact.png), [aftermath](../probes/multicar/evidence/triple_after.png).
- [12-second native replay video](../probes/multicar/evidence/multicar_replay.mp4): two-car then simultaneous three-car case at quarter speed. The presentation is 30 FPS; the contact owner still advances at 120 Hz.
- [Focused validation](../probes/multicar/evidence/validation.json), [CPU benchmark](../probes/multicar/evidence/performance.json), [native render counters](../probes/multicar/evidence/native_budget.json), [capture-state ledger](../probes/multicar/evidence/native_states.json).

## Physical ownership and selection

`world.gd` owns one 120 Hz planar step for all cars. A conservative sphere test rejects far pairs, then swept OBB intervals over four planar axes find likely contact time. Finite OBB manifolds supply normal, point and overlap width. Connected pairs are grouped into islands and resolved together with 12 alternating sequential-impulse iterations. Each impulse is equal and opposite, including yaw inertia. There are no mesh-triangle contacts and proximity never starts a graph/cloth solve.

Every car owns exactly one physical aggregate of 1,210 kg, including attached wheels. The existing 38-node graph remains a saved visual/effects state; it contributes no second body, integration, mass or contact reaction. Its coordinates are published from the physical root and recorded local shape. Production Godot/Jolt does not independently simulate these custom cars.

`library.gd` removes the weighted center and full lower-chassis basis from each saved frame, then samples only local shape and local wheel orientation. `car.gd` applies the actual root transform. An 80 ms smooth handoff registers the current shape to the clip without jumping the root or replacing root velocity. Recorded wall reaction is never applied a second time.

For a single pair, the reduced mass is `mu = mA*mB/(mA+mB)`. A closing speed is relative normal motion; it is not each car's wall speed. Available collision energy scales with `0.5*mu*v_closing^2`. This probe measures actual kinetic energy removed by the contact island, weights incident pairs by `mu*v_closing^2`, then splits each pair's share equally between its cars as an **equal-compliance game approximation**. Per-car wall-equivalent speed is `sqrt(2*assigned_energy/car_mass)`.

Consequently, equal cars approaching at 60+60 km/h do not each receive a 120 km/h wall clip. Moving 120 km/h into an equal parked car also maps to approximately 60 km/h per car while preserving forward system momentum. Unequal aggregate masses are tested; their impulses and per-car equivalent speeds use each car's actual mass. Compliance, material work and the available bank still need calibration for different real vehicle types.

A single front/rear contact must cover at least 1.4 m across the car and lie within 18 degrees of its longitudinal axis. Its 5x3x3 impact-zone signature is checked by the existing `ImpactZoneGrid` matcher. Two contacts on one car must be opposed (`normal dot < -0.98`) and each within 15% of 60 km/h equivalent to select the one authored composite. Three or more contacts, incompatible normals/severity, a partial corner, unsupported damage history and clips containing detached wheels have explicit fallback reasons. Rigid contact still works; unsupported damage is not invented and previous damage is not erased.

A vehicle accepts at most one deformation recording in this proof. Later hits retain physical response and current damage. Existing production conditioned histories cannot be reused safely until they have equivalent root-free incoming-state descriptors. The code never adds two absolute pristine frame arrays.

### Composite authoring

`author_composite.gd` records a separate offline opposed-wall fixture at 960 Hz, sampled to 120 Hz. Two prescribed walls press the front and rear over a decelerating 0.6 m stroke each. The current shared body, wheel, glass and interior solvers run during **authoring only**. There are 301 frames over 2.5 seconds in `data/opposed_front_rear_60.crashclip`.

This fixture is an approximation to simultaneous crush, not a coupled moving-three-car ground-truth simulation. Prescribed walls add external work; their authoring energy is not asserted to equal the runtime island energy. Both passes also evaluate the floor contact. The shared structural/effects code and author script are fingerprinted, as are the surface inputs. Current source clips and the regenerated composite are checked against their actual input fingerprints; arbitrary mismatched physics inputs are rejected.

### State, debris and wheel ownership

Saved body/link damage, wheel attachment/alignment, glass membrane tears, seats, optional airbag and rest-space surface history travel with the selected sample. Existing effects event IDs prevent duplicate emission. Glass release uses its stored local residual motion plus the actual current attachment/root velocity. No glass membrane or interior cloth solver runs during playback. Cosmetic glass particles have existing bounded lifetime/floor contacts; other cars are not yet particle collision targets.

The snapshot recorder additionally stores each car's world-space glass particles and emitted-event cursor. Disk roundtrip checks compare these, effects, body nodes, wheel/broken states and physical roots exactly. Particle presence is asserted so that check is not vacuous.

All shown clips retain their attached wheels. A synthetic free-wheel channel tests that unsupported ownership is explicitly rejected before playback. Independent released-wheel/root ownership must be added before enabling a clip that releases wheels. Do not silently move a released wheel with a vehicle root or count its mass twice.

## Results and performance

Fresh verification reports are written to `verification/multicar/validation.json`;
`evidence/validation.json` is the checked integration snapshot.

The current integration rerun passes **86 checks**; fresh native captures are included. The original performance figures below remain historical measurements. It checks equal/unequal mass response, no energy growth, impulse linear/angular momentum, simultaneous determinism, single mass ownership, bounded overlap, actual acceleration-to-contact, no damage healing, unsupported cases, current source provenance and exact disk replay. Full structure, glass membrane and interior live/cloth step counters remain zero throughout all runtime cases.

For the two-car head-on, normal impulse is about 20,771.7 Ns and kinetic energy falls from 336.11 kJ to 0.30 kJ. Moving into the parked car retains about 40,333.3 Ns total forward momentum and both cars continue near 60 km/h. The simultaneous three-car case solves both contacts in one batch, with about 29,370 Ns per contact; momentum residual is below 0.001 Ns. No island's assigned cosmetic energy exceeds its actual removed kinetic energy. These are planar impulse-model checks, not claims of real crash calibration.

Historical probe-base benchmark (not remeasured after current integration): Apple M3, macOS, Godot 4.7.2 Compatibility; warmed caches, 480 physics steps per row. Other development work was concurrent. Values are microseconds for **physics/contact plus local deformation/effects sampling**, with snapshot recording and native rendering excluded:

| Cars / activity | Mean us | p95 us | p99 us |
| --- | ---: | ---: | ---: |
| 1 clear | 112 | 115 | 117 |
| 2 clear | 223 | 229 | 231 |
| 2 contact + baked playback | 845 | 1,054 | 1,068 |
| 3 clear | 347 | 357 | 387 |
| 3 contact + baked playback | 1,375 | 1,663 | 2,799 |
| 10 clear | 1,194 | 1,224 | 1,454 |
| 10, one colliding pair | 1,822 | 2,042 | 2,128 |

Every row has zero full structural steps. Only two/three affected cars sample a bake; distant cars remain cheap. Broadphase currently enumerates pairs (`N*(N-1)/2`) before rejecting them; use a spatial hash for larger fleets.

Native paused/pristine scene rendering is separate (this does not measure a debris-heavy aftermath): approximately **12.9 / 21.8 / 34.1 ms viewport CPU time for 1 / 2 / 3 cars**, with **167 / 285 / 400 visible draw calls** at 1280x800. Pose upload measured separately is about 37 / 79 / 147 us for all cars. Each current car skin has 57,624 triangles. The scene and per-car visual assembly dominate much sooner than the pair solver; shared meshes/materials, reduced draw calls and LOD/culling are necessary before a large fleet. Native GPU timestamps report zero on this Compatibility setup and are labeled unavailable, not fast GPU times. These are not whole-game FPS claims. Counters use official [Viewport render info](https://docs.godotengine.org/en/4.7/classes/class_viewport.html) and [RenderingServer measured render time](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html).

On the original probe base, `python3 tools/demo.py verify` completed successfully with no shared code changes, including structural/wheel/driving/adaptive/ramp/bake/glass/interior/conditioned/surface/roof suites. `python3 tools/demo.py check` also passes. The saved full-suite transcript is in `evidence/shared_verify.txt`.

## What production integration requires

1. **Split the clip/player contract.** Version an explicit local deformation track, optional author root track and stable shape frame. Keep live/custom physical root and contact impulse ownership separate. Add a finite crush/contact envelope: the current instantaneous root impulse followed by cosmetic crush can leave an unrealistic post-crush gap/rebound, visible in this proof. Do not call that fully coupled crush dynamics.
2. **One multi-vehicle world step.** The existing driving solver must expose force/wheel-ground integration to a shared 3D car-contact owner, including car-ground constraints. Keep one mass ledger. This proof's planar floor constraint and fixed yaw inertia do not cover ramps, jumping, pitching, suspension load or independent wheels.
3. **Per-car event signatures.** Store actual incoming relative contact motion, local normal/overlap/zones, masses, energy allocation and source-state IDs. Separate geometry compatibility from severity scaling. Far/proximity-only pairs must not wake the deformation solver. Swept rotational bounds and multiple impact times within one tick need production coverage; current sweep holds yaw constant for each interval.
4. **Bounded multi-hit library.** Keep supported composites/conditioned histories, current deformation/irreversible descriptors and explicit fallthrough. Author targeted front+side/corner and unequal-vehicle cases before enabling their visuals. Avoid a full combinatorial bank and do not hide unsupported signatures by replaying the last event.
5. **Released-part owners.** Assign world pose/velocity, mass transfer and collision lifetime to detached wheels and later panels. Attached deforming parts stay on the car. No second aggregate may retain the released mass. Rebase particle/part event velocities once, and keep existing event IDs/history.
6. **Versioned replay/provenance.** Carry root, shape, wheel, glass/interior and cumulative surface state plus transient event ownership. Validate model/profile/bake inputs and cosmetic compatibility. Replay must not heal damage, duplicate particles or silently activate cloth/full structural solvers.

Body splitting is intentionally outside this probe. The independent articulated-panel integration and arena work are not dependencies and were not edited.

## Reproduce checks and captures

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . --script res://probes/multicar/verify.gd
"$GODOT" --headless --path . --script res://probes/multicar/benchmark.gd
"$GODOT" --path . --script res://probes/multicar/native_budget.gd
"$GODOT" --path . res://probes/multicar/probe.tscn -- --capture-multicar
"$GODOT" --path . --script res://probes/multicar/record_video.gd --fixed-fps 30
ffmpeg -y -framerate 30 -i verification/multicar_video/%04d.png -frames:v 360 \
  -c:v libx264 -crf 21 -pix_fmt yuv420p -movflags +faststart \
  probes/multicar/evidence/multicar_replay.mp4
python3 tools/demo.py verify
python3 tools/demo.py check
```

Reauthor the isolated composite only when its physical inputs change:

```sh
"$GODOT" --headless --path . --script res://probes/multicar/author_composite.gd
```

The author writes only the probe's `data` directory and does not rebuild the production catalog. Intermediate video PNGs and replay recordings are generated under ignored `verification/`; reviewed final evidence stays beside this probe.
