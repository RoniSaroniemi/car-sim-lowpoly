# Drive with baked crashes and live tuning

```sh
python3 tools/demo.py drive
```

The sandbox starts with **Use baked wall crashes** enabled. Drive normally with W/S and A/D. At an imminent compatible wall contact, the same car graph changes from lightweight driving to a recorded crash, then returns to lightweight physics with its damaged body shape, suspension and detached-wheel state retained.

| Control | Action |
|---|---|
| W / S / A / D | Throttle / brake / steer |
| Space / Q | Handbrake / select forward or reverse |
| R | Repair, reset and rearm the next bake |
| H / Y | Stage a 60 / 120 km/h approach; driving controls remain usable |
| U / I | Stage the +20° / −20° 120 km/h approaches |
| B or the checkbox | Switch baked crashes on/off |
| J / K | Stage either jump ramp |
| C / drag | Change camera / orbit |

Tyre grip adjusts the actual wheel friction coefficient from 0.10 to 1.50. Engine power adjusts from 55 to 660 kW and scales the profile's peak torque in proportion, so the change is useful at low speed too. Both sliders act immediately and survive R/repair. They are session tuning; the vehicle profile and baked files are not rewritten. Sliders affect live driving, suspension and contacts; a playing crash keeps its authored trajectory. The existing 160 km/h profile speed taper remains unchanged.

## Baked mode ownership and performance

`driving_vehicle.gd` extends the shared `vehicle_simulation.gd` and owns the switch. The scene remains input, level, camera and UI. There is one 1,210 kg vehicle graph; no second physics chassis is spawned.

With baked mode **on**, the deformation forecast and full structural solver are never called. The body/engine mass stays in the existing rigid aggregate during driving, including ramps and the period after a crash. Wheels retain the existing 120 Hz suspension, rotation, friction and breakable mounts. Simple generalized contact impulses keep the rigid/deformed body above the analytic terrain and outside the test barrier. These contact projections do not evaluate the 187 structural deformation constraints.

A cheap distance check rejects remote obstacles. Only when a contact is within the next 120 Hz step does a swept probe event rank recordings. The bank is loaded once and shared, not read from disk during a crash. The nearest 60/120 km/h speed bin is selected first; the existing zone/local-normal classifier then chooses an angle within that bin. Impacts from 35 to 175 km/h are eligible. There is no interpolation between severity bins; an 80 km/h hit can use the 60 km/h recording.

The existing player binds to the **same live graph** through a weak reference. A 0.10-second Hermite registration preserves contact pose and initial node velocity while blending onto the recorded trajectory. Wheel spin phase is continuous. No full structural or suspension solve runs during playback. Simulation time stays monotonic.

At completion, retained link lengths, damage, broken supports, wheel alignment/spin and detached states become the lightweight simulation's current state. Constraint accumulators are cleared; the damaged body is captured as a rigid shape, and detached wheels keep moving with coarse collision physics. No full-solver wake happens after the clip.

Only one bake is played per repaired car: the library describes pristine vehicles, so another bake would erase or overwrite damage from the first crash. Later contacts, low-speed bumps, already damaged cars, airborne/tilted poses, wall corners/short faces and incompatible events use rigid contact response in baked mode. They do not silently activate live deformation. Turn baked mode **off** to use the existing forecast-driven full solver instead. The wheel-mount test selects live mode explicitly. A toggle during playback affects the mode used after the current clip completes.

This is still the benchmark's analytic terrain and finite barrier, not arbitrary Godot-world collision. Registered intermediate-angle clips can approximate contact rather than exactly satisfy the wall. Replaying an authored crash does not produce a newly calibrated physical outcome for every speed, grip setting or glancing trajectory.

## Verification

```sh
python3 tools/demo.py verify-driving-bakes
# Optional timed comparison, excluding scene setup and rendering:
godot --headless --path . --script res://scripts/benchmark_driving_bakes.gd
```

The driving suite covers actual acceleration from rest into a bake; frontal, angled, side and rear selection; pose/velocity/clock continuity; the same graph throughout; zero forecast/full-solver calls before, during and after playback; retained damage and repair; disabled/live mode; low-speed/missed/damaged cases; both ramp flights/landings; and effective, persistent live tuning. Fresh reports are `verification/driving_bakes_validation.json` and `verification/driving_bakes_performance.json`.

On the local Apple M3 run, a four-second 120 km/h case averaged 11.58 ms per 120 Hz call in live mode versus 0.42 ms with baking. Baked mode made zero forecast calls and zero full-solver steps; its p99 was 1.01 ms. These are timed physics/selection/playback calls, excluding rendering, scene setup and bank loading; they do not establish a whole-game FPS gain.
