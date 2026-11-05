# Current status — 2026-11-05

The repository contains a runnable vehicle/crash experiment, its source assets,
offline recordings, focused tests and native visual evidence. It is a development
example with approximate game parameters, not a calibrated crash model.

## Main driving setup

- Test yard and colosseum use the same vehicle runtime, mass, wheels and damage
  state. The arena includes sand/concrete/timber jumps, a halfpipe, adjacent
  42°/24° ramps, a test wall and finite circular retaining wall.
- Throttle, brakes, steering, suspension, tire grip and engine power are live.
  Roof stiffness now defaults to **3×**, adjustable **0.5×–8×**; **1×** restores
  the earlier deliberately fragile roof. Repair/reset keeps the chosen tuning.
- Doors, bonnet and hatch can open, deform, lose closure/hinge supports and use
  lightweight reduced physics when loose. Healthy closed panels are condensed.
- Wheels can bend, compress and detach. Glass and interior effects can be
  simulated offline/live and recorded for playback. The optional airbag is a
  demonstration retrofit, not an original-equipment claim for this car.
- Godot renders the custom graph/compact-body simulation. Jolt is selected in
  project settings, but does not solve this deformable car. Vehicle mass is
  owned once; there is no second full-mass chassis.

## Baking and repeated impacts

There are **132 main recordings**: horizontal 37, finite-wall partial/corner 48,
conditioned sequence 3, roof landing 6, older roof fixtures 2, multiaxis 36.
Offline physics generally runs at **1,920 Hz**; tracks still contain **301 samples
at 120 Hz** over 2.5 seconds. **Baked storage/loading/playback is not optimized for
shipping.** The main bank is **622.18 MiB compressed**. See [optimization status,
current costs and next experiments](BAKE_OPTIMIZATION_STATUS.md).

The normal baked sandbox keeps lightweight root/wheel/contact physics running
while skipping full structural, panel-cage, glass-membrane and airbag-cloth solves.
World impact detection uses the actual arena ring and ramp surfaces. Roof
contacts use full 3D car orientation, angular motion and non-wheel probes, so an
earlier tire touch cannot hide a roof impact. Rejections do not consume triggers;
successful contacts rearm after physical separation.

The authored 60 → 60 at +20° → 120 at −20° sequence uses conditioned recordings.
Other supported arena/terrain/roof histories use approximate incremental local
shape changes on the current damaged car, preserving previous crush/failures.
A roof layer can start during another incremental playback. Arbitrary overlapping
legacy absolute trajectories are not supported. The roof slider scales dedicated
baked roof shape changes; live mode changes actual roof stiffness/yield. Existing
recorded secondary effects are not resimulated by that slider.

The 36-direction experimental multiaxis bank/viewer is distinct from general
sandbox matching. Some historical upper-angle cases fail energy-quality checks;
a successful source/replay audit is not physical calibration. Whole-body splitting
and arbitrary metal tearing remain deferred reference work.

## Multi-car examples

```sh
python3 tools/demo.py multicar
python3 tools/demo.py verify-multicar --no-import
```

The separately runnable [multi-car probe](MULTICAR_BAKED_PROBE.md) shows two moving
cars, a moving car hitting a parked one, simultaneous three-car contacts and a
small drive-into-cars case. Shared contact impulses own physical roots; clips
supply local deformation. The opposed front/rear composite was regenerated on
the current sources. Native images/video and validation are included.

This is a **planar proof**, not multi-car integration into the colosseum. It
condenses attached wheels/panels, has no 3D suspension/jumps, permits one supported
deformation event per car, and rejects unsupported partial/detachment/history
cases. Do not assume production roof/panel behavior from that isolated adapter.

## Known interior problem: seats penetrate crushed bodywork

Driver/passenger seats can visibly pass through a heavily collapsed roof or
other body mesh. They already have an elastic/plastic backrest hinge and baked
seat poses, but **seat-to-deforming-body contact, seat-frame/rail crushing and
cushion collapse are not implemented**. Existing pose replay cannot solve a
new roof/seat intersection by itself.

The next interior implementation should use simple seat/backrest/cushion and
interior-body proxies, frame-following mount points and yielding/collapsible
seat supports. Run those contacts during live/offline crash authoring, record
the resulting persistent seat deformation and failure state, then replay it
without adding heavy gameplay solves or counting seat mass twice. Include
roof-first, angled rollover, frontal and repeated-impact tests. Re-bake affected
recordings after changing the actual interior model; do not patch fingerprints
on older data. This is an explicit open task, not a claimed completed feature.

## Reproduce and evidence

```sh
python3 tools/demo.py arena
python3 tools/demo.py verify
python3 tools/demo.py check
python3 model/source/test_cabin_fit.py
```

Current release receipts are in [release evidence](evidence/release_2026_11_05/).
[Roof tuning](ROOF_LANDING_SLICE.md), [world damage stacking](WORLD_DAMAGE_STACKING.md),
[panel ownership](VEHICLE_PANELS.md), [glass](VEHICLE_GLASS.md) and
[interior limits](VEHICLE_INTERIOR.md) describe the individual contracts.
Historical benchmark numbers retain their original scope and source baseline.
