# Baked trigger misses: investigation and bounded prototype

Investigated the current **working-tree** `driving_vehicle.gd`, not the earlier committed standalone bake probe. The initial investigation did not modify the driving runtime. The portable harness now lives in `tools/probes/baked_trigger_investigation/`, using a frozen pre-sensor driving adapter. Generated evidence goes under ignored `verification/trigger_investigation/`. The supported production helper and its owner integration are described in [BAKED_CONTACT_SENSOR.md](BAKED_CONTACT_SENSOR.md). All 38 reproduction cases used **zero legacy deformation-forecast calls and zero full-solver steps**.

There are two separate problems: a genuine first-contact classifier sensitivity issue, and intentionally unsupported wall-edge/height geometry. A lightweight forecast can help the first; more full-width sensitivity alone cannot correctly supply the second.

## Measured causes

| Reproduction | Result | Cause |
|---|---|---|
| Centered 0°, 20° and 30°, car moving along its heading, 120 km/h | Correct bake | No general 30° blind sector |
| Centered 30°, 60 km/h with throttle; longer 35 m approach; several steering inputs | Correct bake | Ordinary steering/throttle alone did not reproduce the miss |
| Centered 40°, moving along car heading | No bake, rigid contact | Tangential/normal velocity ratio 0.839 exceeds 0.65; the cutoff corresponds to about 33° of trajectory incidence |
| 40° body heading, but launched wall-normal | Correct bake | Body heading and trajectory incidence are different inputs |
| 30°, 120 km/h, trajectory aimed at wall Z=5 m | Correct bake | Whole projected car fits the wall |
| Same, aimed at Z=6 m | No bake | Projected car Z span is 5.52–8.78 m; only 76% lies inside the wall ending at Z=8 m |
| 30° aimed at Z=7.2 m | No bake | About 43% overlap; first normal may come from the short end face, not the large wall face |
| Wall only 0.8, 1.2 or 1.6 m high | No bake despite physical contact | Whole-car height gate rejects a recording that assumed a tall wall |
| Centered 0° or 30°, **6° nose-down pitch** | **Missed bake** | Earliest contact contains only light upper-front zones; weighted overlap falls just below the matching threshold |

The finite box is the wall's whole collider; it has no separate inactive hit zones. `_contact_event()` intentionally requires the complete projected car to fit between `barrier_min.z + 0.1` and `barrier_max.z − 0.1`, requires a world normal within the ±X faces, and rejects roof points above the wall top. Those checks reject edge/corner/short-face and partial-height cases before playback. Subsequent rigid contact can damage suspension links; the clean-car gate then rejects later attempts until R repairs the car. One bake per repaired car is another explicit gate.

The first-contact signal is mass-weighted, **not a minimum number of activated voxels**. The 30° recording's first zones have weights 0.84 (zone 38) and 0.16 (zone 41). With a small nose-down pose, the upper zone 41 touches first and is normalized to weight 1. Its weighted Jaccard overlap becomes `0.16 / (2 − 0.16) = 0.087`, below the 0.1 gate. The 0° upper pair has the same combined weight and the same failure. This happens before the upright guard fails: 6° and 10° pitch are allowed poses. The rejected contact can then change vertical speed or damage mounts, preventing a later retry.

At 6° nose-down, a 50 mm classification contact band includes the nearby lower nodes and recovers the expected recording. At 10°, the same fixtures need a 100 mm band. The current band is 25 mm. A pure time forecast with the same narrow classifier does not cure this by itself.

## Combined-pass prototype and evidence

The isolated `sensitized_vehicle.gd` prototype extends the instrumented harness, not production code. It:

1. Uses a cheap distance rejection and per-node linear swept AABB checks over 66 ms. Current node velocities already include the aggregate's angular contribution.
2. Arms a short-lived candidate without playing an animation.
3. Still requires the original next-step contact event to become imminent.
4. Only when the original result is `bank_match`—with the existing clean/upright/full-wall geometry gates satisfied—tries 50 mm, then 100 mm signatures.
5. Starts the same registered player when the broader contact manifold matches. It does not permit unsupported partial-width/height clips.

The four previously missed fixtures (0°/30° × 6°/10° nose-down) all recovered, with no pose pop, zero heavy forecast calls and zero full-solver steps. **16 prototype checks passed**, including preserving the partial-corner rejection, actually arming a prediction without playing early, and cancelling after the wall is removed. This proves the narrower sensitivity mechanism in these fixtures; it is not a complete shipping predictor.

Instrumented 33/66/100 ms forecasts found the supported centered 30° collision about 31/64/98 ms ahead. They also correctly identified the geometry-rejected edge cases early; extra lead time did not manufacture a suitable partial-contact recording.

A separate 10,000-call headless timing probe measured:

| Pose | Cheap 100 ms forecast | Existing one-frame detector |
|---|---:|---:|
| 65 m from the wall | 0.51 µs/call | 5.18 µs/call |
| 5 m from the wall, future contact only | 40.55 µs/call | 5.20 µs/call, no event yet |
| 2.05 m from the wall, imminent contact | 41.20 µs/call | 234.72 µs/call, including bank selection |

The cheap forecast returns only a time-to-contact; it performs **zero library rankings**. These timings exclude rendering and physics and are local microbenchmarks, not FPS gains. The instrumented sensitivity prototype additionally runs diagnostics and is deliberately not a performance implementation.

## Suggested shipping path

Keep strict baked mode: do not reinstate `collision_forecast.gd` or structural wakes. Add a small `clear → armed → contact` path:

- Reuse cached aggregate center/velocity and a conservative bounding radius for an inexpensive clear-road rejection.
- Near a possible obstacle, run a 66–100 ms per-node sweep at about 30 Hz; use an angular bound for turn/rotation acceleration that the linear node velocities cannot capture.
- On a valid forecast, cache the pre-contact motion, pristine-at-arm state and footprint. At actual contact, classify a 50 mm manifold, widening up to 100 mm only while armed, or accumulate a short 10–20 ms contact-zone manifold. Keep the actual contact confirmation separate so sensitivity cannot cause early playback.
- Rank clips once on arming/contact and invalidate when angle, footprint or obstacle changes materially. Do not rank the library on clear roads or every render frame.
- Cancel after a short clear hysteresis, when moving away, or when geometry changes. Test steering/braking near misses and prediction cancellation before enabling it by default.
- Allow damage generated by that same confirmed, recently armed impact to be distinguished from damage that already existed before arming. Never use this to overwrite an old damaged car with a pristine bake.
- Keep the geometry coverage gates until suitable clips exist. A short status such as “Rigid response: no matching edge-impact recording” would distinguish a deliberate fallback from a missed sensor.

Do not blindly lower the overlap threshold to accept every one-zone event. That would hide true unsupported contact patterns and still would not supply proper partial-wall deformation.

## Partial-corner and height bank extension

Record overlap/obstacle context in addition to the initial zone mask. The full-face and 76%-overlap 30° cases above initially touched the **same zones 38/41** and gave the same angular fit, despite needing potentially different later physics. First-contact voxels alone cannot distinguish them.

A useful descriptor is a projected impact footprint: body-local contact centroid, width overlap and clipped side, vertical overlap/obstacle height, obstacle corner/end-face normal distribution, plus the existing speed and local direction. Record the contacted obstacle bounds relative to the car and the actual contact history. Runtime matching can then reject or choose the right overlap case explicitly.

Start with 12 new frontal clips: 60/120 km/h × left/right wall edge × 25/50/75% overlap. Compare the current ~76% case against a full-wall reference first; the current whole-car-fit gate may be conservative where only the unaffected tail lies outside the wall. Relax that gate only if sampled node/wheel differences stay within an agreed tolerance. Then extend ±30° overlap cases if the evidence warrants them. Short/low walls need separate vertical-overlap clips, beginning with 0.8 and 1.2 m barriers. The offline full solver already accepts finite barrier bounds, so these can be recorded without changing the cheap runtime.

Suggested acceptance: supported centered/pitched contacts trigger before rigid response corrupts the incoming signature; partial cases choose a matching footprint rather than a full-wall fallback; near misses never play; reset rearms; every strict-baked run stays at zero full solves; clear-road library ranking remains zero; and the added near-obstacle predictor fits a measured sub-0.1 ms budget per scheduled check on this machine.

## Local reproduction

From the repository root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/probes/baked_trigger_investigation/run.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/probes/baked_trigger_investigation/verify_sensitized.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/probes/baked_trigger_investigation/forecast_cost.gd
```

Evidence: `results.json` (38 cases and per-gate signatures), `sensitized_validation.json`, `forecast_cost.json`, and `summary.json` under `verification/trigger_investigation/`. `source_fingerprints.json` records the working-tree runtime inputs used. The harness and frozen baseline are portable repository sources; raw reports remain generated investigation artifacts. This document records the original investigation rather than claiming full corner/height coverage.
