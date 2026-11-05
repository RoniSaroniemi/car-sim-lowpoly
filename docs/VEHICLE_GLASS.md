# Vehicle glass controller

The production adapter operates on all six existing `Glass_*` meshes in the Niva GLB. The default profile uses a laminated windscreen and tempered side/rear panes. This is a configurable demonstration assignment, not certification of the actual vehicle's glazing. Thresholds and crack patterns are art-directed; this is not calibrated glass fracture or a safety simulation.

## Live behavior

`scripts/vehicle_glass.gd` implements the vehicle-effects interface in `VEHICLE_EFFECTS_IMPLEMENTATION.md`. It holds a weak graph reference and never changes graph mass, positions or velocities. `hit_window(id, severity, piercing, uv)` provides a direct local hit. IDs are `windscreen`, `rear`, `door_left`, `door_right`, `quarter_left`, `quarter_right`.

The windscreen creates an actual 117-node stiff PBD membrane only after cracking. Its 404 stretch/shear bonds and 190 bending restraints run at 120 Hz with six constraint sweeps. The intact pane follows its body opening without a membrane solve. Cracked laminated glass bends more readily than it stretches. Cutting/puncture can tear local bonds; disconnected interior patches can become cosmetic fragments. The mount boundary and a band around the actual curved pane outline stay permanently attached. A blunt frontal collision should crack and bow a retained sheet, not eject the windscreen. Diffuse tensile tearing is enabled only after extreme opening stretch (70%); ordinary compression alone does not cut the interlayer.

A live opening-strain trigger cracks glass; a high-speed normal velocity pulse also initiates laminated inertia response. Default settings are in `vehicles/niva_glass.json`. The tempered path has its own higher opening threshold, chips for modest direct hits, and granulates after a strong hit. It retains a jagged rim in this demo. Such remnants are an authored frame/retention choice, not a universal property of tempered glazing.

Crack lines are procedural radial/ring artwork. Fragment topology is a coarse prefracture mask, not solved stress-crack propagation. The sheet solver supplies deformation and tear/connectivity state. The coarse existing car mesh limits visible fold detail.

## Recording, playback, relaunch

`capture()` returns version-2 state: profile ID, attachment-local node positions, velocities relative to per-node mount motion, broken bonds, released nodes, cell masks, hit parameters and stable release IDs. Cosmetic particle trajectories are excluded. Save this inside the central effects snapshot; do not run a second recorder.

`begin_playback(initial_state)` initializes the event cursor without replaying old releases and preserves already airborne debris during a conditioned transition. `restore_interpolated(a,b,alpha)` interpolates node poses and applies irreversible masks/tears/events from the discrete lower sample. It never advances PBD. Forward events emit once; backward seeks clear cosmetic transients and reconstruct the event cursor. `reset()` repairs panes and clears debris. `resume_live()` reconstructs a retained membrane with its recorded tears and relative motion; `synchronize()` preserves local cloth motion across a car teleport, yaw or uniform-velocity relaunch.

Release events store motion **relative to the pane mount**, then add the current weighted mount-point velocity when emitted. This permits a clip authored at one vehicle velocity to replay at another. Tempered granules inherit the pre-contact point motion plus a small symmetric local kick; their default normal impulse is not always outward. Laminate patches inherit the actual released membrane motion. A particle born inside an analytic obstacle can exit without being teleported to a face and spuriously reflected backwards.

Debris is one CPU array with a global 192-particle cap and a MultiMesh draw. It collides with the current analytic graph floor and enabled barrier using swept expanded-box collision, and expires after roughly 2–3 seconds. There is no vehicle-body AABB to prevent flight through the cabin. General scene objects and full self-collision are not implemented. Debris is one-way cosmetic and does not return impulses to the car.

## Geometry and rendering

`python3 tools/extract_glass_geometry.py` deterministically regenerates six pane frames, actual source triangles, normalized UVs, outlines and SHA fingerprints. The GLB exports no suitable glass UVs. The adapter adds dedicated pane-local UVs to the already bound native meshes and retains their existing skin weights.

The renderer is specifically verified under Godot's GL Compatibility renderer. GLES3 performs skeleton transform feedback before the custom vertex shader, so membrane deltas are uploaded in graph/model space; inverse bone rotation here creates a detaching-pane artifact. A contour-weight texture forces the shader displacement to zero at the native pane edge. Changing rendering backends needs a fresh verification of shader/skinning order. Relevant Godot sources: [GLES3 skeleton transform](https://github.com/godotengine/godot/blob/4.5/drivers/gles3/shaders/skeleton.glsl), [GLES3 scene vertex shader](https://github.com/godotengine/godot/blob/4.5/drivers/gles3/shaders/scene.glsl).

## Reproduce verification and previews

From the project root, using the installed Godot binary:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/verify_vehicle_glass.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://scripts/benchmark_vehicle_glass.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://scripts/run_vehicle_glass_probe.gd -- --capture-glass-car
```

Omit `-- --capture-glass-car` for the interactive actual-car viewer. Its controls hit the windscreen, release side glass, replay the recording and repair. The standalone side-by-side material probe remains in `probes/glass/` with its own project.

The production suite has 49 guarded checks across eight sections. The count and section guards prevent an aborted helper from silently reporting success. It covers six-pane geometry, actual live tearing, exact recorded pose/topology roundtrip, zero replay PBD, retained blunt/frontal windscreen, fixed mounts, repair/seek/conditioned-transition lifecycle, resumed tears and release IDs, ±30 m/s velocity inheritance and rebasing, 33→0 m/s braking inertia, cabin transit, particle expiry and 180 m/s thin-wall CCD.

Committed evidence is under `probes/glass/evidence/production/`. The 120 km/h structural frontal authoring fixture retains all windscreen cells, cracks to stage 2 and has zero measured membrane mount error. The GPU yaw/roof fixture rotates the actual car 1.2 radians and lowers/shifts roof nodes; its windscreen remains cracked/mounted, with zero broken bonds and zero measured boundary error. The view is an actual render, not a mock image. A 17 m/s Galilean fixture differs by only 0.057 mm in attachment-local pose; live/baked release velocity roundtrip error is zero.

CPU timing artifacts explicitly exclude rendering, loading and the main car solver. The full live membrane remains an offline-authoring-quality path; baked playback is intended for the driving performance target. Profiles/source fingerprints change when physics or configuration changes; old banks must be rebuilt. The parent runtime owns bank compatibility and vehicle-effects composition.
