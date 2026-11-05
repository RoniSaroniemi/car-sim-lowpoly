# Out-of-plane crash authoring

This bank adds **18 directions at 60 and120 km/h (36 clips)** to the separate horizontal campaign. It uses the production1210 kg vehicle, its closed and latched25 kg doors,18 kg bonnet,22 kg tailgate, live panel cages/mounts, windows, interior and surface damage. No physical source, shared material, suspension threshold or horizontal selector is changed.

## Coordinate contract

`MultiaxisCrashCases.directions()` provides8azimuths at+45° elevation,8 at−45°, puretop and pureunderside. Azimuth0 points toward the front(+X),90 toward the left(−Z),180 rear,270 right. Elevation+Y points toward roof. `incoming_car_direction` is the direction the car moves toward its contact location; `reaction_car_normal` is its opposite. The fixture quaternion maps that incoming vector toworldDOWN. The explicit quaternion and full3D signature are authoritative; `heading_deg` is descriptive azimuth only and must not be used to select/register these clips as horizontal impacts.

Each fixture rotates the complete vehicle and slams it onto the actual flat floor. The initial physical clearance is1 m. Earliest contact includes body spheres, **oriented rounded tire support**, and all10 physical cage floor proxies per panel at their actual40 mm radius. Underbody cases therefore retain honest wheel-first contact; they do not suppress tires to pretend a rail hit. A top impact may touch the raised tailgate edge before a roof body node. Every first-contact source and gap is recorded explicitly.

The partial first step uses the solver's semi-implicit gravity convention. At the exact boundary the requested normal closing velocity is normalized with a uniform vertical velocity change, preserving relative/tangential velocities. Panel and effects mounts are synchronized after initial teleport and again before arming. Preparation fails after3 simulated seconds rather than running indefinitely.

## Run

From the project root, substitute your Godot4.7 executable:

```sh
Godot --headless --path . --script scripts/bake_multiaxis_clips.gd -- --list
Godot --headless --path . --script scripts/bake_multiaxis_clips.gd -- --only=top_60,upper_az045_60,underside_60 --quality=4 --no-index
Godot --headless --path . --script scripts/bake_multiaxis_clips.gd -- --speed=60,120 --quality=4 --skip-valid
Godot --headless --path . --script scripts/bake_multiaxis_clips.gd -- --index-only
```

Defaults are1920 Hz full simulation,120 Hz samples,2.5 seconds and301frames, including contactframe0. `--only` accepts comma-separated direction keys or complete IDs; `--speed` accepts comma-separated speeds; `--output` redirects the bank. Parallel workers must use `--no-index`. A supervisor can regenerate the bank-local catalog afterwards. `--skip-valid` reuses only301-frame clips with matching precision and physical fingerprints.

`MultiaxisCrashRecorder.start(direction_key,speed_kmh,quality_multiplier)` constructs one shared production VehicleSimulation. Call `step()` until`completed`; check`error` before reading`result`. No duplicate solver or fake vertex animation exists. All frames contain body, wheel, mass reservations, four panels and glass/interior/surface effects. Source/profiles are fingerprinted. Timing fields are measured monotonic wall time: setup, full simulation call scope, total authoring step scope and total. They are not process CPU; measure CPU separately with`/usr/bin/time`.

## Inspect and verify

```sh
Godot --headless --path . --script scripts/verify_multiaxis_authoring.gd -- --clips=res://bakes/multiaxis/top_60.crashclip,res://bakes/multiaxis/upper_az045_60.crashclip,res://bakes/multiaxis/underside_60.crashclip
Godot --path . multiaxis_crash_viewer.tscn
Godot --path . multiaxis_crash_viewer.tscn -- --clip=res://bakes/multiaxis/top_60.crashclip --time=.4 --capture=/tmp/top60.png
```

The viewer explicitly chooses from existing bank clips, with replay, pause, scrub, orbit and structure overlay. It does not install vertical clips into the driving sandbox's yaw matcher. The existing Player is registered using`contact_rotation_xyzw` and lower-chassis longitudinal/transverse basis, preserving pitch and roll. The verification harness applies an arbitrary3D transform, runs in-place Player replay, checks final body/cage position, latches/detachments, glass stages/masks/released pieces,1210 kg mass and **zero body, cage, glass membrane and airbag cloth solves**. Detached debris may use their intended cheap playback motion; this is separate from full vehicle simulation.

Outcomes record actual loads. Doors and glass are not forced to fail, and intact glazing is valid. These materials are game-oriented and uncalibrated; the clips are not physical safety predictions.

## Pilot evidence

On frozen production source9ab5f46, `top_60` at1920 Hz produced301frames and4.2 MiB. Concurrent campaign timing:94.49s measured authoring wall,95.27s process wall,78.77s userCPU+0.50s systemCPU. First contact was the real tailgate upper cage edge (3proxies),6.6nanometres minimum recorded gap. Full3D replay passed11,929checks with0failures; body/cage/membrane/cloth solve counters all remained0, and mass was1210.0000038147kg (float32mass rounding). More pilot timings will be appended after those records complete. Concurrent timings are not isolated throughput benchmarks.
