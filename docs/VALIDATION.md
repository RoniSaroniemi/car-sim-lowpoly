# What verification proves

Run `python3 tools/demo.py verify` from the repository root. The runner imports assets in the selected Godot, runs all four suites headlessly and writes `verification/structural_validation.json` , `verification/wheel_validation.json` and `verification/driving_validation.json`. A failed required check causes a nonzero exit code.

## Structural scene suite

The six runs are 20, 50, 80 and 120 km/h with the declared full-width symmetry boundary, followed by unweakened/weak-rail 80 km/h runs with symmetry released. The latter pair compares material strength under identical boundary conditions.

Required checks cover finite positions/velocities; analytic barrier/floor clearance; bounded kinetic-energy growth; 1,210 kg mass accounted once; permanent rest-length change; increased severe-impact cabin shortening; actual native bone anchors; normalised skin weights; rendered wheel rotation matching hub/spin transforms; material-strength sensitivity; replay and reset.

Shortening metrics use Euclidean distances between structural section centres, so yaw alone is not counted as front shortening. Roof span is measured relative to section geometry rather than global height alone. Wheel clearance allows the configured tire-compression envelope; it does not claim zero visible tire interpenetration.

## Wheel suite

The seven cases are 20/50/80/120 km/h full-width, 80/120 km/h offset, and the same 120 km/h offset case with wheel/body contact disabled. The enabled/disabled comparison checks both final node positions and permanent link rest lengths. This verifies a physical deformation difference rather than a changed render transform alone.

Focused checks also cover standing-car support and upright hubs; unbroken suspension under gravity; equal/opposite translational response during a direct internal contact; force/time-based support removal without a position/velocity kick; continued contact of a deliberately detached wheel; replay of wheel/link detachment; and reset. The default severe offset impact must load nearby body structure and break some supports, while the low-speed case must not eject wheels.

The detached-wheel branch is exercised by deliberately overloading supports in a targeted test. A passing report does not mean the default impact necessarily ejects a complete wheel. See [wheel implementation and limits](WHEEL_PHYSICS.md).

For only this suite, run `python3 tools/demo.py verify-wheels`.

## Reports and package integrity

- `verification/handover_validation.json`: current six-case structural report from the isolated published handover.
- `verification/handover_wheel_validation.json`: current seven-case wheel report and targeted checks.
- `verification/baseline.json`: historical 175-link pre-wheel reference. The current topology has 187 links; this old report is preserved only for comparison.
- Generated `structural_validation.json` / `wheel_validation.json`: fresh output from your current checkout, ignored by Git.

Compare behaviour and pass/fail rather than requiring byte-identical floating-point/timing output across machines. The supplied reports record the tested version and scope. The GitHub workflow runs all four suites on Linux. The optional Blender 4.5.9 model rebuild and seven cabin-fit tests were also checked when the initial handover was created; the model inputs are unchanged by the wheel update.

`python3 tools/demo.py check` verifies deterministic graph regeneration, topology and mass, wheel assembly/hardpoint configuration, GLB naming, model presence and file hashes. It does not run simulation.

## Visual review

Use the plain mesh with local folds disabled to judge the structural skin alone, then enable the detail shader. Inspect textured and ghost views from front, side and top; scrub before impact, during load transfer and at the held end state. `docs/images/wheel_*.png` contains actual renders of the current offset setup. The older `*_120.png` files show the pre-wheel full-width reference.

Extreme panel folds can intersect because the example has selected wheel/body contacts but no general structural/panel self-contact. Passing these checks does not certify realistic folds, a closed physical energy budget, safe occupant space or real Niva crash performance. Shape review remains necessary.

## Timing scope

`mean_step_us` and `max_step_us` measure the named GDScript structural step, including wheel work. Skin-build and visual-upload fields measure their named operations. None is a complete frame-time/GPU/multiple-car benchmark. The crash scene solves during an active impact; the driving scene solves continuously. Profile target hardware and port the hot solver as needed for production.

## Shared driving runtime

The driving suite checks wheel-torque acceleration, braking, steering signs,
reverse, profile-sensitive tuning, intact suspension/structure in ordinary
driving, persistent crash damage, detached-wheel control release, reset and
matching physics under 30 Hz/120 Hz frame chunking. It drives the same graph
through `VehicleSimulation`; it is not a separate mock vehicle. See
[Shared runtime](SHARED_VEHICLE_RUNTIME.md) for the scene boundaries and limits.

## Wheel mount load suite

The combined runner also writes `verification/wheel_mount_validation.json`.
Its 11 checks cover rigid lateral support below yield, permanent twist after
unloading, full wheel release at load/damage limits, continuity of motion,
absence of a detached lateral tether, replay/reset, and all three stages of
the exact visible T-key test fixture. Ordinary driving checks include full-lock
steering without yielding or breaking the mounts.
