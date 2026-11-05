# Roof/floor crash authoring

`scripts/roof_crash_recorder.gd` records flat inverted-roof and angled roof-corner landings through the shared full vehicle solver. It supplements the horizontal wall bank with a distinct **`roof_floor`** family and a full3D contact frame. It does not create another chassis or solver copy.

## Integration API

```gdscript
var recorder = preload('res://scripts/roof_crash_recorder.gd').new()
recorder.start('roof_flat', 35, 4) # case, normal contact km/h, quality multiplier
while not recorder.completed:
    recorder.step()
var data = recorder.result
```

`roof_corner` uses the existing fixture's15° pitch/20° roll and3 m/s tangential travel. The profile is `niva_multiaxis_v1`; body, wheels, glass and interior are advanced by the same shared runtime. Defaults are2.5 recorded seconds,120 samples/second, and1,920 physics steps/second. The authoring quality may be1/2/4×. The initialization descriptor is included so the pose/loading can be reproduced.

## Contact boundary and normalization

1. Prepare the selected fixture1 m clear of the flat floor, with downward launch velocity. Effects are synchronized after posing, so a change from upright rest coordinates to an inverted fixture cannot create a false inertia event.
2. Sweep **non-wheel body spheres only** against the floor before each full step. The time-of-contact root matches the solver's semi-implicit fractional displacement, `gap + vy*t - gravity*t² = 0`. Wheel contacts never arm this recorder.
3. Advance the tiny fractional preparation interval to the earliest body/floor boundary. Apply one uniform vertical velocity correction to initialize the requested35 km/h normal closing speed. Relative translational node velocity and tangential motion are preserved. This is an authoring initial-condition normalization, not an applied crash force.
4. Synchronize effect history at that velocity boundary, register station2 as the translation anchor, capture the first frame, then keep every following solve at the selected fixed timestep.
5. Sample body, wheel and effect state at120 Hz for301 frames. The existing `Clip.local_frame` includes effects automatically; no parallel glass or interior snapshot format is introduced.

The contact definition is the existing structural body probes, not render-mesh triangle collision. Signatures use mass-weighted rest-space45-bin zones, normal incident momentum/energy proxies and the initial non-wheel contact nodes. Contact history stores floor-contact substeps and nodal momentum-loss proxies; these are not calibrated ground reaction forces.

## Full3D registration contract

The following static helpers are exposed for the runtime floor matcher:

- `full_chassis_basis(g)`: lower-chassis longitudinal and transverse axes, with an orthonormal up axis. It preserves roll and pitch; it does not flatten the heading onto the ground plane.
- `minimum_body_floor_gap(g, floor_y=0)`.
- `body_floor_time_to_contact(g, horizon, floor_y=0)`.
- `floor_signature(g, velocity, tolerance=.002, floor_y=0)`.

Metadata is version3 with `family: roof_floor`, `fixture_descriptor`, `physics_hz`, `quality_multiplier`, `material_profile`/version, `origin`, and **`contact_rotation_xyzw`**. The signature contains car-local `normal`, world normal`[0,1,0]`, world velocity, closing speed, zones, incident proxies and `contact_source: non_wheel_body_floor_probes`.

An inverted flat roof has local normal approximately`[0,-1,0]`. The tested corner has all three components, approximately`[.258819,-.907674,.330366]`. A yaw-only registration cannot reproduce the corner case. The runtime must select the roof family and use the contact quaternion/full frame to register recorded positions, hub orientations and effect emission consistently. Root-owned player/UI code handles that integration.

Fingerprints include the graph, material alias, fixture/recorder/clip code, shared solver/dynamics/runtime, and both glass/interior controllers, their geometry/support scripts, profiles and model dependency. Preparation velocity and first body-floor gap are retained for audit.

## Author final clips after source freeze

```sh
godot --headless --path . --script res://scripts/bake_roof_clips.gd
```

On macOS use `/Applications/Godot.app/Contents/MacOS/Godot`. Defaults write:

- `bakes/roof/roof_flat_35.crashclip` and readable JSON metadata;
- `bakes/roof/roof_corner_35.crashclip` and readable JSON metadata;
- `bakes/roof/library.json` with the available roof records.

Optional arguments after`--`: `--speed=35`, `--quality=4`, `--case=roof_corner`. Updating one case preserves other roof entries in the per-folder catalog. The helper does not alter the central library reader, player or sandbox. Those must include this separate family explicitly.

Final records should be generated only after glass/interior and runtime code is frozen, followed by fingerprint and playback checks. This implementation patch deliberately includes **no final bank records**. Its test files are written only under ignored `verification/`.

## Verification evidence

```sh
godot --headless --path . --script res://scripts/verify_roof_authoring.gd
godot --headless --path . --script res://scripts/verify_roof_authoring.gd -- --high-quality
```

Both480 Hz and default1,920 Hz ephemeral runs passed35 checks across the flat/corner cases. Each produced301 frames, exact requested normal speed, full3D normals/quaternion, non-wheel initial contacts, glass/interior states on every frame, complete effect-profile fingerprints, disk/replay agreement and no additional full-solver steps while restoring frames. The high-quality first-contact gap was0 m in both cases; the480 Hz value was within4e-9 m of zero.

The tested high-quality recordings used about16.65 CPU seconds each locally and compressed to about1.7 MiB each with effect states. This is observational authoring cost, excluding disk write/setup; no runtime FPS claim is implied. Fresh results are in `verification/roof_authoring_validation.json`. The test asserts that both cases completed, so an aborted helper cannot be reported as a successful suite.
