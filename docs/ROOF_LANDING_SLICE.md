# Moving roof-first landings

The shared driving car detects roof-first support and impacts on ground and
ramps. This is the deliberately fragile game profile requested for the sandbox;
it is not a calibrated roof-safety model. A real roof may support several times
vehicle weight; see the [IIHS roof-strength method](https://www.iihs.org/ratings/about-our-tests/roof-strength).

## Try it

Run `python3 tools/demo.py arena` or `python3 tools/demo.py drive`. Leave
**Use baked crashes** enabled. **Light roof** stages a gentle landing;
**Roll left/right** stage 40° roof-side landings; **Hard roof** stages the stronger
case. These buttons place the shared car and let the ordinary contact detector
start playback. The staged view runs at 35% speed; **R** repairs and returns to
normal driving. Rolling off a ramp uses the same detector, with no test flag.
Roof hits after earlier damage now use the [incremental world-damage path](WORLD_DAMAGE_STACKING.md), preserving the earlier crush. Repair with R to compare identical starting cars.

## Roof stiffness control

Both driving scenes expose **Roof stiffness**, from **0.5× to 8×**, default **3×**.
The previous deliberately fragile setup is **1×**. Higher values resist crushing;
repair with R before comparing the same impact. The value survives repair and
staging, and each scene starts with its default when opened.

For baked roof contacts, stiffness scales the cached local deformation by its
reciprocal, including a roof layer during another incremental impact. The setting
is captured at contact: changing the slider during playback affects later roof
hits and cannot repair existing damage or abruptly rescale the active clip.
The selector's contact sensitivity is unchanged. No new clip preparation, full
structural solver or cloth solver runs because the slider changes. Ordinary
frontal/conditioned recordings retain their authored response.

For live collisions, the shared runtime scales the roof/pillar members' stiffness
and yield strength from their material definition, with corresponding damping.
It leaves the lower rails unchanged and recomputes parameters only when the
setting, simulation precision or fixture materials change. Scaling starts from
the definition each time, so repeated changes do not multiply cumulatively.

This control is gameplay tuning. Baked geometry scaling is an approximation,
not a newly simulated material response; recorded glass/interior/wheel failure
states retain their source severity. Existing source recordings and fingerprints
remain unchanged. `tests/roof_landing/stiffness.gd` compares equal impacts at
1×/2×/3×/4×, runs real live roof collisions, and checks slider wiring, persistence,
bounds, active-playback behavior and zero baked solver work.

Equal 60 km/h forward, 4 m/s downward baked comparisons measured cabin-height
loss of **0.815 m at 1×**, **0.460 m at 2×**, **0.311 m at the 3× default**, and **0.235 m at 4×**. Separate real
live 4 m/s roof-drop runs over 0.75 seconds measured **0.225 m at 1×** versus
**0.165 m at 4×**. These are distinct playback and live measurements, not a
claim that the approximate slider reproduces the live solver exactly.

[Roof stiffness measurements](evidence/roof_stiffness/validation.json) · [Native control preview](images/roof_stiffness_control.png)

## Recorded conditions

Six clips combine **60 km/h forward**, **4 or 7 m/s downward**, and roof roll
offsets **−15°, 0°, +15°** around upside down. The tilted cases have a real
20°/s roll rate during the simulated collision. Each recording uses 1920 Hz
physics, 301 samples at 120 Hz and 2.5 seconds after contact. Body, wheels,
panels, glass, seats and the optional demonstration airbag are recorded.

The new recorder uses `soft_roof_profile.gd` and `panel_floor_wake.gd`.
Roof/pillar/diagonal members have reduced stiffness/yield, including the remaining
roof-connected bend and front ties. Floor activation precedes cage penetration.
Live driving applies this optional roof recipe when live solving begins. The
six roof-landing recordings were regenerated with exact recipe fingerprints;
the historical wall recipes remain unchanged.

`roof_landing_response.gd` derives a cached, deliberately stronger playback
track from those recordings. It amplifies cabin roof compression, adds a minimum
progressive buckle after support starts, caps the remaining cabin clearance,
and propagates roof displacement through panel bindings. The raw recordings are
immutable. Its metadata labels the result as **art-directed playback**; source
energy metrics describe the original physics, not the amplified geometry.
Prepared tracks are cached at setup, never baked or solved when a hit happens.

## Contact and selection

`roof_landing_sensor.gd` cheaply rejects upright driving, then queries actual
body, tire and panel probes near the floor. `ground_impact_geometry.gd` sweeps
those probes with gravity **and angular velocity**, finding fractional contact
against the shared terrain's height and normal. The full chassis basis maps
the actual contact normal into the car-local 5×3×3 regions. Floor impacts are
independent of the designated planar wall and work on sloped ramp surfaces.

A roof-facing contact, including approximately 120° roll, can initiate a crush
under nearly static support. Wheel-first landings do not trigger roof damage.
There is no requirement to travel along world X or to meet the old wall speed
threshold. Motion up to 75 m/s and angular speed up to 16 rad/s is accepted;
nearest recorded roof orientation and severity are approximations outside the
six authoring cases. Higher speeds keep rigid contacts. Later damage histories use the approximate incremental path. This is not a general pole or ceiling collision implementation.

## Playback and verification

Playback adds cached local shape changes to the current damaged geometry. The
existing lightweight body and wheels continue moving under gravity, angular
momentum, suspension and actual world contacts. It does not assign the recorded
60 km/h root velocity to an incoming stationary car. Small panel/body contact
remainders are projected along actual terrain normals; tire compliance remains
active, with a hard-rim limit. Completion returns the same damaged graph to
rigid driving. Previously crushed members and irreversible failures are retained.

The chase camera holds its heading reference while airborne, so pitching through
vertical no longer makes the camera swing to the opposite side. This changes
only the view. Free-flight tests found no physical automatic uprighting: at
0/45/120/180° initial roll, zero or 1 rad/s spin retained its orientation/spin
within the checked tolerances and the center of mass followed ballistic motion.

```sh
python3 tools/demo.py verify-roof-landings --no-import
python3 tools/bake_campaign.py --family roof_landing --workers 2 --resume
```

`tests/roof_landing/verify.gd` covers all six recordings at two headings,
unrecorded intermediate roll/speed cases, real scene buttons, airborne
non-triggering, upright wheel landings, moving away, gentle impacts, existing
damage, sloped ground contacts, elevated ground, mass and post-playback behavior.
It requires zero body, panel cage, glass membrane and airbag cloth solves.

The earlier six-clip batch timing was 109.2 s elapsed / 216.4 CPU s. The new
soft-roof batch is measured independently in
`verification/bake_campaign/roof_landing.json`; do not compare the old timing
as if it described the new source. At the earlier 1× setting, 20 m/s forward and static
support tests measured amplified cabin-height loss of approximately **0.34–0.80 m**.
The native PNGs show the actual severe roof response. All runtime replay tests
require zero structural, cage, membrane and cloth solves.

Additional checks:

```sh
Godot --headless --path . --script tests/roof_landing/response.gd
Godot --headless --path . --script tests/roof_landing/terrain.gd
Godot --headless --path . --script tests/roof_landing/static_live.gd
Godot --headless --path . --script tests/airborne/verify.gd
```

`static_live.gd` separately tests the real softened solver starting at rest,
without playback amplification. That measured roughly 9–13 cm of initial
buckling over one second; the dramatically larger sandbox response deliberately
uses the art-directed baked track. The terrain suite includes rest at upside
down/120° roll, 20 m/s tangential motion, two plane slopes and the actual
42° arena ramp. Source recordings, amplified playback and live-only outcomes
are reported separately rather than presented as the same simulation.

Natural-driving regression: `tests/roof_landing/drive_rollover.gd` drives the
actual paired-ramp seam at 35/50/70 km/h with two lateral offsets. Paths reaching
roof contact trigger a recorded roof event with zero full solves. Lower-roll
paths can select generic body damage when the body hits the ramp; tire-only
contacts remain suspension events. The evidence contains the measured roll,
contact normal, selected clip and continuous-handoff errors for every path.
The original car-local grid is used as a similarity score for this deliberately
permissive roof family, not as a strict direction gate; no world-X alignment is
required. Position/velocity corrections are bounded and floor-plane registered.
