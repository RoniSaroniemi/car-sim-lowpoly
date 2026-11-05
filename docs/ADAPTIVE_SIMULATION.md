# Adaptive driving and deformation

The sandbox now defaults to [baked driving](BAKED_DRIVING.md), which skips the deformation forecast and full solver entirely. This page describes live mode, selected by turning baked crashes off.

The driving sandbox uses the shared vehicle graph and wheel code, with three simulation states:

- **DRIVE:** a rigid aggregate owns the existing 1,130 kg body/engine mass; the four separate 20 kg wheel nodes retain suspension and tire response. It runs at 120 Hz with three suspension sweeps and skips structural deformation links.
- **FULL:** the existing 480 Hz structural solve takes over before a predicted impact, or when a fresh contact, yielding, or external load requires it. No second full-mass body is added.
- **SLEEP:** a quiet stationary car skips simulation until controls or an environmental change wake it.

`collision_forecast.gd` sweeps a conservative bound over 0.18 seconds, with angular padding, relative obstacle velocity and acceleration margin. It checks the finite barrier and the same analytic terrain surface used for wheel contact. Pure yaw is not treated as vertical closing speed. Sideways travel alone does not imply an impact.

The aggregate is synchronized into structural node state before a full solve. A cleared prediction can return to DRIVE after 0.15 seconds clear time and residual deformation energy below 5 J. A quiet full solve can return after deformation energy falls below 2 J for 0.25 seconds. This energy excludes rigid translation/rotation and wheel bearing spin, while including relative structural/suspension motion. Fresh contacts and ongoing yielding keep full simulation active. Fixture loads can explicitly request a full-solve hold.

These are configurable game approximations in `vehicles/niva.json`. A rigid aggregate cannot reproduce the full solver's elastic response before wake-up; the benchmark compares both paths and reports the difference, rather than assuming equivalence.

## Driving and tests

W throttle, S brake, A/D driver-left/right, Space handbrake, Q reverse, R repair, C camera, T wheel-mount load test, H head-on approach, and J/K low/high jump starts. Hold W after a jump start. Both ramps use smooth analytic humps, with matching visual and contact surfaces. Takeoff and landing follow the wheel/body dynamics; no jump impulse is injected.

```sh
python3 tools/demo.py verify-adaptive
python3 tools/demo.py verify-ramps --no-import
python3 tools/demo.py verify-retention --no-import
python3 tools/demo.py drive --no-import
```

The adaptive report covers forecast wake-up, state continuity, near-miss recovery, energy cutoff, ordinary drift, quiet rest and paired timing/impact comparisons. The ramp suite checks real airborne intervals and landing. The retention suite checks rear mounts through frontal/offset impacts, severe localized front release and both ramp landings without mount failure. Results are in `verification/adaptive_report.md`, `verification/adaptive_validation.json`, `verification/ramp_validation.json` and `verification/wheel_retention_validation.json`.

Full-mode optimization research is separate in [PERFORMANCE_INVESTIGATION.md](PERFORMANCE_INVESTIGATION.md). Its candidate patch is not enabled in the shipping solver.
