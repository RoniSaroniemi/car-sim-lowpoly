# car-sim-lowpoly

A small, reproducible Godot driving and crash example: **38 physical nodes → 39 render bones → a textured car with 39,673 render triangles**. Structural links yield permanently; the skeleton carries the large deformation; a shader adds smaller folds, normal detail and surface wear.

![Textured 120 km/h offset crash with wheel interaction](docs/images/wheel_textured.png)

This isolated example includes the latest wheel revision: finite-width oriented wheels, independent hub tilt and rim spin, yielding/breakable suspension, limited tire compression and selective wheel-to-body load transfer. It includes the model, textures, editable Blender file, procedural model source and structural, wheel and driving verification suites.

## Start locally

Install the standard **Godot 4.7.2** build from [Godot's official release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable). Python 3.10+ is only needed for the convenience runner and graph generator. Blender 4.5 is optional for model editing/rebuilding. No .NET, add-ons, package manager, external Jolt extension or network service is needed to run the example.

```sh
git clone https://github.com/RoniSaroniemi/car-sim-lowpoly.git
cd car-sim-lowpoly
python3 tools/demo.py run
```

On Windows use `py -3 tools/demo.py run --godot "C:\path\to\Godot.exe"`. On macOS the runner finds `/Applications/Godot.app` automatically. On Linux it looks for `godot` or `godot4` in PATH. Any platform can pass `--godot /path/to/executable` explicitly.

Alternatively, import `project.godot` into Godot and press **F6/F5**, then click **Run structural impact**. Opening the project alone does not auto-start an impact. The runner imports assets and starts a 120 km/h slow-motion offset crash automatically.

## Drive the same car

```sh
python3 tools/demo.py drive
```

W throttle, S brake, A/D steer, Space handbrake, Q forward/reverse, R repair/reset,
C camera, and T wheel-mount test. The new flat practice area uses the same deformable car, wheels
and damage state as the crash bench. It is a first driving implementation;
the earlier sandbox's ramps and general Jolt-world collision are not ported.

Both scenes use one [shared vehicle runtime](docs/SHARED_VEHICLE_RUNTIME.md).
Tune `vehicles/niva.json` or improve the shared dynamics/wheel code once, then
run both scenes and the combined checks. There is no duplicated driving chassis.

## Inspect the result

| Control | Action |
|---|---|
| 1 / 2 / 3 / 4 | Structure / plain body / textured body / ghost body |
| Space / R | Run selected impact / reset |
| Drag / scroll | Orbit / zoom |
| Replay slider | Scrub the recorded three simulated seconds |
| Structure overlay | Show or hide the simulated load paths |
| Local folds and surface damage | Compare structural geometry with and without shader detail |
| Weaken one front rail | Lower one side's strength and release the symmetry boundary |
| B / Escape | Show barrier / close |

Choose 20, 50, 80 or 120 km/h and either Full-width frontal or Offset / left front wheel. The offset case releases the symmetry boundary automatically. Switch inspection views after impact to compare the same state, rather than rerunning a different crash. Slow motion changes playback rate, not the physics timestep.

## Understand and reproduce it

1. [Local setup and verification](docs/SETUP.md)
2. [How the solver, skeleton and shader fit together](docs/ARCHITECTURE.md)
3. [Adapting the method to another car](docs/ADAPTING_A_CAR.md)
4. [Editable model and procedural rebuild](model/README.md)
5. [Validation scope and limitations](docs/VALIDATION.md)
6. [Wheel physics, suspension and contact setup](docs/WHEEL_PHYSICS.md)
7. [Shared runtime, driving and future dynamics](docs/SHARED_VEHICLE_RUNTIME.md)
8. [Snapshot provenance and asset rights](docs/PROVENANCE.md)

```sh
python3 tools/demo.py check
python3 tools/demo.py verify
```

The second command runs six structural cases, seven wheel cases, native skin binding, replay/reset, support/detachment checks, rigid-mount load checks and shared-runtime driving checks. Fresh reports go to `verification/structural_validation.json` and `verification/wheel_validation.json`. Fresh driving results go to `verification/driving_validation.json`. Checked-in handover reports record the earlier published revision; `verification/baseline.json` preserves the older pre-wheel reference for comparison.

## What is included

| Path | Purpose |
|---|---|
| `vehicles/niva.json` | Shared model/structure paths and dynamics tuning |
| `scripts/vehicle_simulation.gd` | Common runtime used by both scenes |
| `scripts/vehicle_dynamics.gd` | Steering, wheel torque, brakes and drag |
| `scripts/driving_sandbox.gd` | Driving input, camera and practice area |
| `structure.json` | Editable mass nodes and material/link properties |
| `scripts/build_structure.py` | Reproducible structural graph generator |
| `scripts/structure_solver.gd` | Fixed-step elastic/plastic XPBD-style simulation |
| `scripts/wheel_physics.gd` | Hub orientation, bearing spin, rounded tire contacts and knuckle yielding |
| `scripts/verify_wheels.gd` | Wheel-specific crash cases, contact ablation and detachment tests |
| `scripts/structural_skin.gd` | Native Skeleton3D binding and structural visualisation |
| `scripts/damage_surface.gdshader` | Compression-driven folds and material damage |
| `scripts/structural_probe.gd` | Test bench, camera, controls, replay and validation |
| `assets/` | Prebuilt GLB LODs, texture maps and source operation metadata |
| `model/` | Packed Blender source, build scripts and configuration |
| `docs/images/` | Actual screenshots from the included snapshot |
| `tools/demo.py` | Portable launcher; installs nothing |

## Scope

The custom graph owns the car's motion and 1,210 kg mass. Godot renders it. Jolt is selected in project settings, but **Jolt does not solve this deformable car**. Contacts are analytic floor/finite-box tests plus selected wheel-to-structure contacts. This is a driving/crash learning example with approximate game parameters, not a calibrated crash-engineering model.

Each wheel retains one translational mass node and adds rotational inertia, six suspension hardpoints and a yielding angular knuckle constraint. Detached wheels remain in the same solver and retain their velocity/spin. Tire response is approximate: it is not a pressure/sidewall simulation. General-world collisions, general body self-contact, body-panel separation, glass debris, sheet tearing and porting the earlier sandbox course remain future work. Extreme folds can intersect. The complete example runs offline after dependencies are installed.

Code and documentation: [MIT](LICENSE). See [asset provenance](docs/PROVENANCE.md) for reference imagery and vehicle marks.
