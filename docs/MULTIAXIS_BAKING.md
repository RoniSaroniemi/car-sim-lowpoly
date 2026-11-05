# Out-of-plane crash authoring

This bank adds **18 directions at 60 and 120 km/h (36 clips)** alongside the horizontal campaign. It uses the production 1210 kg vehicle: closed and latched 25 kg doors, 18 kg bonnet, 22 kg tailgate, live panel cages and mounts, glass, interior and surface damage. It changes no shared physical source, material, suspension threshold or horizontal selector.

## Coordinate contract

`MultiaxisCrashCases.directions()` provides eight azimuths at +45° elevation, eight at −45°, pure top and pure underside. Azimuth 0 points toward the front (+X), 90 toward the left (−Z), 180 rear and 270 right. Positive elevation points toward the roof (+Y). `incoming_car_direction` is the direction the car moves toward its contact location; `reaction_car_normal` is its opposite. The fixture quaternion maps that incoming vector to world DOWN.

The quaternion and full 3D signature are authoritative. `heading_deg` is descriptive azimuth only; do not use it to select or register these clips as horizontal impacts.

Each fixture rotates the complete vehicle and slams it onto the actual flat floor, starting with 1 m physical clearance. Earliest contact includes body spheres, **oriented rounded tire support**, and all ten physical cage floor proxies per panel at their actual 40 mm radius. Underbody cases retain honest wheel-first contact. A top impact can touch the raised tailgate edge before a roof body node. The metadata records every first-contact source and gap.

The partial first step uses the solver's semi-implicit gravity convention. At the exact boundary a uniform vertical velocity change normalizes requested normal closing speed while preserving relative and tangential velocities. Panel and effects mounts synchronize after teleport and again before arming. Preparation fails after three simulated seconds instead of running indefinitely.

## Bake

Run from the project root, substituting your Godot 4.7 executable:

```sh
Godot --headless --path . --script scripts/bake_multiaxis_clips.gd -- --list
Godot --headless --path . --script scripts/bake_multiaxis_clips.gd -- --only=top_60,upper_az045_60,underside_60 --quality=4 --no-index
Godot --headless --path . --script scripts/bake_multiaxis_clips.gd -- --speed=60,120 --quality=4 --skip-valid
Godot --headless --path . --script scripts/bake_multiaxis_clips.gd -- --index-only
```

Defaults are 1920 Hz full simulation, 120 Hz samples, 2.5 seconds and 301 frames including contact frame zero. `--only` accepts comma-separated direction keys or complete IDs. `--speed` accepts comma-separated speeds. `--output` redirects the bank. Parallel workers must use `--no-index`; regenerate the bank-local catalog afterwards. `--skip-valid` reuses only 301-frame clips with matching precision and physical fingerprints.

`MultiaxisCrashRecorder.start(direction_key, speed_kmh, quality_multiplier)` creates one shared production `VehicleSimulation`. Call `step()` until `completed`, then check `error` before reading `result`. There is no duplicate solver or fake vertex animation. Each frame contains body, wheels, mass reservations, four panels and glass/interior/surface effects. All relevant source files and profiles are fingerprinted.

Timing fields measure monotonic **wall time**: setup, full simulation call scope, authoring step scope and total. Measure process CPU separately with `/usr/bin/time`.

## Inspect and verify

```sh
Godot --headless --path . --script scripts/verify_multiaxis_authoring.gd -- --clips=res://bakes/multiaxis/top_60.crashclip,res://bakes/multiaxis/upper_az045_60.crashclip,res://bakes/multiaxis/underside_60.crashclip
Godot --path . multiaxis_crash_viewer.tscn
Godot --path . multiaxis_crash_viewer.tscn -- --clip=res://bakes/multiaxis/top_60.crashclip --time=.4 --capture=/tmp/top60.png
```

The viewer explicitly selects existing bank clips and supports replay, pause, scrub, orbit and structure overlay. It does not install vertical clips into the driving sandbox's yaw matcher. The existing `Player` registers `contact_rotation_xyzw` against the full lower-chassis longitudinal/transverse basis, preserving pitch and roll.

The verification harness applies an arbitrary 3D transform, runs in-place `Player` replay and checks final body/cage positions, latches and detachments, glass stages/masks/released pieces, mass conservation and **zero body, cage, glass membrane and airbag cloth solves**. Detached debris can use its intended cheap playback motion.

Outcomes record actual loads. Panels and glass are not forced to fail; intact glazing is valid. These game materials are uncalibrated and are not vehicle safety predictions.

## Pilot evidence

Frozen physical source: `9ab5f46`. Top 60 km/h at 1920 Hz produced 301 frames and 4.2 MiB. During the concurrent campaign it took 94.49 s authoring wall time, 95.27 s process wall time, 78.77 s user CPU and 0.50 s system CPU. Its first contact was the real tailgate upper cage edge (three proxies), with minimum recorded gap 6.6 nanometres.

Top-impact transformed replay passed 11,929 checks with zero failures. Body, cage, membrane and cloth solve counters all stayed zero; mass was 1210.0000038147 kg (float32 mass rounding). The authored outcome included 59.65 kJ of body plastic work, actual deformation in all four panels, intact latches and hinges, windscreen cracking/deformation and five shattered tempered panes. Nothing was forced to detach.

Additional pilot evidence is stored under `verification/multiaxis/`. Concurrent timings describe these runs, not an isolated throughput benchmark.

All three pilots passed **35,606 checks with zero failures**. The upper-front-left diagonal first contacted body node 26 in zone 39; the underside first contacted four oriented tires while the body was still 0.54498 m above the floor. All three retained 1210 kg and showed no kinetic-energy amplification above initial energy.

| Pilot at 60 km/h | Authoring wall | Body plastic work | First contact |
| --- | ---: | ---: | --- |
| Top | 94.49 s | 59.65 kJ | Tailgate upper cage edge |
| Upper azimuth 45°, elevation 45° | 129.50 s | 72.36 kJ | Front body node 26 |
| Underside | 128.77 s | 47.63 kJ | Four oriented tires |

The upper-diagonal and underside clips ran sequentially in one process: 259.43 s wall, 161.03 s user CPU, 0.97 s system CPU. Raw timing logs, hashes, physical summaries and the zero-solver roundtrip result are in `verification/multiaxis/pilot_receipt.json` and adjacent logs. Native GPU captures show the actual textured replay at the named timestamps.
