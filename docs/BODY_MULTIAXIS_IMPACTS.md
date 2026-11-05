# Live roof, side and angled body deformation probe

The full structural solver already supports three-dimensional motion and plastic distance constraints. It does not disable deformation on a particular axis. Two separate limits explain the reported stiff roof:

1. The sandbox's **baked mode intentionally keeps the body rigid outside playback**. An arbitrary roof landing cannot create a newly solved body collapse there. This probe explicitly switches to full live simulation.
2. In the published live graph, the cabin uses the same stiff `ring` material for lower crossmembers, roof crossmembers, vertical pillars and wall diagonals: 2.4 MN/m stiffness, 110 kN yield and only 12% plastic compression. Roof/body masses can roll or rebound while the closed cage barely changes shape. Mixed-height cabin braces and A-pillar links reinforce that cage.

No factory material data or certified crash validation is claimed. This is a bounded game-material comparison.

## Measured baseline and experimental response

All cases use the same 38 nodes, 187 links, 1,210 kg mass, wheel assemblies, engine/frame definitions and 480 Hz / eight-sweep full solver. Symmetry is disabled. Roof cases start with the closest surface 1 m above the floor and 8 m/s downward velocity; the corner case adds 15° pitch, 20° roll and 3 m/s horizontal travel. The side case launches the rotated car into the static wall at 80 km/h.

Cabin height is an average of six **intrinsic floor-to-roof/pillar lengths**, and width is an average of five intrinsic transverse lengths. A rigid rotation cannot create their reported compression.

| Case | Original peak height loss | Experimental peak height loss | Original peak width loss | Experimental peak width loss |
|---|---:|---:|---:|---:|
| Flat inverted roof | 16.2 mm | 178.9 mm | 0.4 mm | approximately 0 mm |
| Angled roof corner | 15.4 mm | 200.9 mm | 0.6 mm | 6.3 mm |
| Side wall | approximately 0 mm | approximately 0 mm | 30.2 mm | 70.2 mm |

The maximum local upper-ring span loss in the side case grows from 14.0 to 100.6 mm. After removing gravity/contact loads and relaxing the structure for 0.5 seconds, experimental flat/corner cabin height losses remain 166.8 / 195.4 mm; the side case retains 50.8 mm of average width loss. These are permanent material changes, not just whole-car reorientation or elastic sag.

All **42 checks passed** across six baseline/experimental runs: finite positions/velocities, floor clearance, mechanical-energy bound, live solve usage, fixed mass/topology, restored original properties, improved roof/side response and retained deformation after unloading. Maximum sampled mechanical energy stayed within 0.007% of the initial value; the check allows an 8% plus 1 kJ tolerance. Static floor/box collision and the graph remain approximate; panel self-contact and tearing are absent.

![Published live materials under angled roof landing](images/body_multiaxis/baseline_roof_corner.png)
![Experimental live materials under the same angled roof landing](images/body_multiaxis/experimental_roof_corner.png)
![Experimental side-wall impact](images/body_multiaxis/experimental_side_wall.png)

## Preserve the existing baked library

The experiment is **not a silent replacement for `structure.json`**. The default graph is byte-identical to the published definition, and none of the 26 clips is rewritten. Generate the separate material definition with:

```sh
python3 scripts/build_structure.py --multiaxis-live
```

It writes `structures/niva_multiaxis_live.json`. Running the generator without that flag continues to write the original `structure.json`.

The experimental material variant keeps lower crossmembers, sills, front rails, engine, mounts, wheel properties and topology unchanged. It softens only roof rings, cabin pillars/diagonals, roof longitudinal members, mixed-height/upper cabin braces and the auxiliary A-pillar roof members. It also increases their compression travel so yielding can actually change cabin shape. For example, cabin vertical links use 300 kN/m, 8 kN yield and 70% allowed plastic compression; mixed-height roof braces use 120 kN/m and 3 kN yield. These are intentionally visible test parameters requiring review, not a proposed factory calibration.

Promoting those strengths into the default graph would require a full regression comparison and re-baking/revalidating the library. This isolated variant avoids that change while allowing immediate live sandbox testing.

## Reusable sandbox fixture API

`scripts/body_impact_fixture.gd` operates on the existing vehicle and graph:

```gdscript
const BodyFixture = preload('res://scripts/body_impact_fixture.gd')
BodyFixture.start(vehicle, 'roof_corner', 1.0, true)
# Other cases: 'roof_flat', 'side_wall'; final bool false compares original materials.
```

The fixture disables baked mode and adaptive representation changes, applies the experimental link properties in-place, resets/poses the existing nodes and hub orientations, and supplies the declared initial velocity. It does not move render vertices or add another rigid body. Existing tyre/power parameters remain unchanged. The side case uses the current barrier position; roof cases temporarily disable that barrier.

Before an ordinary reset or wall-start fixture, call:

```gdscript
BodyFixture.restore(vehicle)
vehicle.reset(...)
```

`restore` returns cached original link configuration/properties, `adaptive_enabled` and `barrier_enabled`. It does not repair the current shape itself; the following ordinary vehicle reset does that. The main scene should uncheck its baked-mode control when starting the live fixture and keep that UI state in sync. Material changes last only until restore/reset.

Suggested sandbox buttons: **Live flat roof drop**, **Live angled roof drop**, **Live side impact**. The root agent owns that scene wiring; this branch deliberately does not alter its input/UI implementation.

## Standalone inspection and reproduction

```sh
godot --path . res://body_impact_probe.tscn
godot --headless --path . --script res://scripts/verify_body_impacts.gd
godot --path . --script res://scripts/capture_body_impacts.gd -- --capture-body
```

On macOS use `/Applications/Godot.app/Contents/MacOS/Godot`. The probe exposes an original/experimental material toggle on identical fixtures. 1/2/3 select flat roof/corner/side, Space pauses, R repeats, V switches plain/textured skin, and drag/wheel orbit and zoom. Playback is slow presentation of the actual full solve, not a baked animation.

For a matched baseline capture:

```sh
godot --path . --script res://scripts/capture_body_impacts.gd -- --capture-body --baseline-materials --capture-case=roof_corner
```

Fresh numerical output goes to `verification/body_impacts_validation.json`; a saved local result is [body_multiaxis_validation.json](body_multiaxis_validation.json). GPU screenshots are generated under `verification/` and retained above for review. Material parameters, impact loading and coarse skin should be steered visually before making the variant a default or generating new roof/side bakes.
