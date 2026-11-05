# Moving roof-first landings

The shared driving car now detects a roof-first landing on flat ground and
selects a dedicated recording at actual contact. It works in the test yard and
colosseum, including natural landings that have no staged-test flag. A floor
event is independent of the designated wall and uses the car's full pitch,
yaw and roll. The original wall classifier remains separate.

## Try it

Run `python3 tools/demo.py arena` or `python3 tools/demo.py drive`. Leave
**Use baked crashes** enabled. Click **Roof landing**, **Roll left**,
**Roll right**, or **Hard roof**. These buttons put the ordinary shared car
above the floor with forward momentum; they do not play an animation directly.
The normal driving contact detector must trigger playback. The staged test runs
at 35% time so the contact is visible. **R** repairs and returns to normal speed.

You can also roll off the paired ramps and land on the flat arena floor.
Repair before each trial: this first slice accepts a pristine, closed car,
and does not add conditioned roof-after-wall damage histories.

## Recorded conditions

Six clips combine **60 km/h forward**, **4 or 7 m/s downward**, and roof roll
offsets **−15°, 0°, +15°** around upside down. The tilted cases have a real
20°/s roll rate during the simulated collision. Each recording uses 1920 Hz
physics, 301 samples at 120 Hz and 2.5 seconds after contact. Body, wheels,
panels, glass, seats and the optional demonstration airbag are recorded.

The new recorder and live driving use `panel_floor_wake.gd` to wake panel cages
before floor penetration. The helper is explicitly fingerprinted as part of
this recording recipe. The earlier wall recording recipes and their physical
source files are unchanged; old experimental 3D slam recordings are separate
reference data and are not used by this selector.

## Contact and selection

`roof_landing_sensor.gd` first rejects ordinary upright driving with a cheap
orientation check. Near the ground it tests body spheres, oriented tires and
panel cage points against `floor_sample`. A fractional gravity-aware time of
contact prevents a 120 Hz step from skipping the event.

The contact signature uses point velocities, including roll velocity, and maps
ground normals through the full chassis basis into the existing 5×3×3
car-local impact grid. Selection compares actual contact closing speed,
contact regions, roof orientation, forward speed and roll rate. Forward and
sideways speeds are measured in the ground plane; vertical motion is not
misclassified as sideways motion when the car is rolled.

This family allows approximately 39–81 km/h forward speed, modest lateral
motion, roll within about 25° of upside down and pitch within 8°. It selects
nearby 4/7 m/s contact-speed cases rather than scaling their deformation. Gentle
contacts, incompatible high-speed/sideways motion, slopes and previous damage
fall back to the existing rigid contacts. The UI reports the unsupported roof
condition. Ground must be locally flat across the car; this is not a general
terrain, wall, pole or multiple-impact roof library.

## Playback and verification

Roof playback preserves the world ground plane. Yaw places the clip in the
incoming heading, floor height places it vertically, and the existing short
handoff blend absorbs small roll-bin differences. It preserves incoming
position and velocity at entry instead of rotating the recorded floor with
the car. Completion returns the same damaged graph to lightweight rigid driving.

```sh
python3 tools/demo.py verify-roof-landings --no-import
python3 tools/bake_campaign.py --family roof_landing --workers 2 --resume
```

`tests/roof_landing/verify.gd` covers all six recordings at two headings,
unrecorded intermediate roll/speed cases, real scene buttons, airborne
non-triggering, upright wheel landings, moving away, gentle impacts, existing
damage, sloped rejection, elevated ground, mass and post-playback behavior.
It requires zero body, panel cage, glass membrane and airbag cloth solves.

The first high-quality batch took **109.2 seconds elapsed**, **216.4 CPU
seconds** across two workers and produced **23.9 MB** compressed. Each clip's
maximum kinetic energy stayed at its initial energy in these runs. Observed
final roof shortening was approximately **2.4–3.1 cm** for the 4 m/s cases and
**8.6–10.0 cm** for the 7 m/s cases; these are game-model outcomes, not calibrated
vehicle safety predictions. Raw timings and test reports are written under
`verification/roof_landing` and `verification/bake_campaign/roof_landing.json`.
