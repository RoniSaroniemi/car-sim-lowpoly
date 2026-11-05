# Temporal quality for full live simulation and offline bakes

The shared quality API selects1×/2×/4× temporal resolution:480,960 or1,920 full-solver steps per simulated second. It preserves the per-step eight constraint sweeps. Link damping fractions must be recomputed using the selected physical timestep, rather than reusing a480 Hz cached fraction at every finer step. The aggregate/compact wheel path already computes its own damping from its actual120 Hz timestep; no separate drive cache is required.

The material fixture preserves `fixed_step_s` and `simulation_quality_multiplier` while selecting or restoring promoted/baseline materials, and recomputes the full-step damping cache accordingly. Thus selecting a high precision and then starting a roof test does not silently return to480 Hz.

## Controlled study

The local study compared the promoted `niva_multiaxis_v1` profile at all three rates with the same mass, topology, material parameters, initial conditions and eight sweeps. Its isolated worktree used the selected timestep plus correctly recomputed damping cache before the shared API was merged. The verification script uses the real shared API when available; its fallback requires the explicit `--allow-quality-fallback` study flag. Source reports distinguish those paths.

| Fixture / measure |480 Hz |960 Hz |1,920 Hz |
|---|---:|---:|---:|
|120 km/h frontal, front shortening after1.2 s |641.44 mm |687.80 mm |693.32 mm |
| Angled roof drop, peak intrinsic cabin-height loss over0.8 s |192.77 mm |196.38 mm |197.51 mm |
|175 km/h offset against15 mm thick barrier, unresolved center-sweep crossings over0.8 s |9 |2 |0 |
| Frontal plastic work |227.81 kJ |241.71 kJ |248.43 kJ |
| Narrow-offset plastic work |171.90 kJ |293.21 kJ |310.95 kJ |

The narrow fixture deliberately exposes discrete contact error: its leading body probes initially sit40 mm ahead of the barrier, moving48.6 m/s. At480 Hz a step can move a center through the thin obstacle before endpoint contact responds. More temporal samples substantially reduce that error in this case. Final penetration alone would miss it: the samples can end entirely behind the obstacle. The crossing count therefore checks swept center segments against the finite obstacle bounds as a separate diagnostic.

The frontal shortening increment falls from46.36 mm between480/960 to5.52 mm between960/1,920. Roof-height increments fall from3.61 to1.14 mm. This is useful local refinement evidence, not proof that every material/failure trajectory is converged. The thin-obstacle damage result changes substantially with contact sampling. A general continuous collision method would remain valuable for smaller/faster objects.

All9 study runs remained finite, retained1,210 kg/38 nodes/187 links, matched the requested step count and damping formula, and met the bounded-energy/floor-clearance guards. The largest sampled mechanical-energy increase was2.57% in the960 Hz narrow fixture, below the study's10% plus1 kJ limit. Other scenarios stayed at or below the initial maximum. These bounds do not establish crash-engineering accuracy.

Timed `vehicle.step` calls, excluding setup, metrics and rendering, cost approximately1.62/3.21/6.37 CPU seconds for the1.2-second frontal scenario, and1.07/2.07/4.12 CPU seconds for the0.8-second roof scenario. Those local observational costs roughly scale with substep count; they are not stable FPS measurements. Offline1,920 Hz recording increases authoring work, while playback can retain the same120 Hz sample rate and avoid those solves entirely.

## Run the shared-API verification

```sh
godot --headless --path . --script res://scripts/verify_authoring_quality.gd
```

On macOS use `/Applications/Godot.app/Contents/MacOS/Godot`. The script checks frontal, angled-roof and thin-offset fixtures at1×/2×/4×, plus material apply/restore preserving a chosen quality. Fresh results go to `verification/authoring_quality_validation.json`. [The saved isolated study](authoring_quality_study.json) records the first66 checks; the current test adds explicit shared-API/fixture-selection guards.

For reproduction before the shared API exists, only the controlled isolated study permits:

```sh
godot --headless --path . --script res://scripts/verify_authoring_quality.gd -- --allow-quality-fallback
```

That report marks `used_shared_quality_api:false`; it must not be presented as validation of an API that was absent. Final integrated verification should run without the fallback flag.
