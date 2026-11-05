# Cheap forecast-assisted baked contact sensor

`scripts/baked_contact_sensor.gd` supplies a lightweight contact packet to the driving owner. It does not own physics, choose clips, mutate the graph, or invoke the legacy deformation forecast/full solver. The original failure analysis is in [BAKED_TRIGGER_INVESTIGATION.md](BAKED_TRIGGER_INVESTIGATION.md).

## Behaviour

A cached-aggregate broad phase rejects distant obstacles. Near a possible collision, a 66 ms per-node sweep is scheduled at 30 Hz. Current node velocity includes the body's angular contribution; an additional bounded acceleration/curvature margin makes arming conservative. That margin is never used to start playback.

A prediction arms a short-lived classification window. Motion direction, heading, obstacle-bound changes, moving away, timeout and clear hysteresis invalidate stale arming. The sensor still requires an **unpadded nodal contact within the next physics step** before returning an event. Forecasting alone returns an empty packet.

At imminent contact the sensor builds one predicted-pose manifold. The primary signature preserves the existing 25 mm band. While armed, it also supplies 50 and 100 mm signatures, allowing nearby structural probes to contribute to the classifier when a light upper node touches slightly before the heavy lower node. This fixes the measured 6–10° nose-down sensitivity failure without lowering the overlap threshold globally.

The live graph is never advanced or edited to make the prediction. Predicted points and contact records are local arrays. Bank ranking stays in the owner and happens at contact, not on clear roads.

## Owner integration

The owner creates one sensor per vehicle and resets it with repair/reset:

```gdscript
var contact_sensor = preload('res://scripts/baked_contact_sensor.gd').new()
# In reset(): contact_sensor.reset()
```

The intended `_contact_event(h)` sequence is:

1. Call `contact_sensor.nearby(solver, motion)` before expensive eligibility checks. If clear, cancel an old arm and return.
2. Keep the owner's existing pristine-car, grounded/upright, terrain, speed and consumed-bake guards. On rejection, `cancel(reason)` or `note_rejection(reason)` supplies diagnostics.
3. Call `packet = contact_sensor.event(solver, motion, h)`. An empty packet means no confirmed next-step event, even if `statistics().armed` is true.
4. Keep full-wall coverage gates using `packet.bounds_min`, `packet.bounds_max` and the primary signature's world normal. Do not turn wall edges, short faces or low walls into valid full-wall impacts.
5. Rank `packet.signature` first. Only after that fails may the owner rank `packet.fallback_signatures` in increasing band order. Each entry contains `band_m` and `signature`. Retain normal/coverage compatibility for every candidate.
6. Pass `packet.toi`, the chosen signature and the owner's selection to the existing registered player. Record `classification_band_m` and `packet.forecast_lead_s` in the selected event for inspection.

The production test adapter in `verify_baked_contact_sensor.gd` is a small executable integration example. The owner may call `note_rejection('partial_wall_width')`, `note_rejection('partial_wall_height')`, `note_rejection('bank_match')` etc.; the helper does not reinterpret those policies.

Public API:

| Call | Result |
|---|---|
| `reset()` | Clear lifecycle and counters |
| `nearby(g, motion)` | Cheap broad-phase boolean |
| `event(g, motion, dt)` | Empty dictionary or confirmed contact packet |
| `cancel(reason)` | Invalidate arming |
| `note_rejection(reason)` | Retain owner-specific diagnostic |
| `statistics()` | Arming/status, rejection/cancellation and cost/count metrics |

The packet contains `toi`, `signature`, `fallback_signatures`, `bounds_min/max`, `armed`, `forecast_lead_s` and `first_probe_node`. Signatures retain the existing zone/normal/incident-proxy fields and additionally expose the classification band and a mass-weighted world contact centroid. These quantities remain game-model proxies, not calibrated wall forces.

## Evidence and cost

```sh
python3 tools/demo.py import
# Direct test, even before adding it to a runner:
godot --headless --path . --script res://scripts/verify_baked_contact_sensor.gd
# Reproduce original misses against a frozen pre-sensor adapter:
godot --headless --path . --script res://tools/probes/baked_trigger_investigation/run.gd
# Optional scoped microbenchmark:
godot --headless --path . --script res://tools/probes/baked_trigger_investigation/benchmark_sensor.gd
```

The helper test passed **27 checks**: four recovered pitched cases, the ordinary narrow-band match, preserved corner/height rejection, actual arming without early playback, wall removal/change, steering-away cancellation, clear-road zero sweeps/rankings and unchanged graph state. All driving cases retain zero legacy forecast/full-solver steps. Fresh report: `verification/baked_contact_sensor_validation.json`.

The local Apple M3 production-helper benchmark measured about **44–45 µs per scheduled near-obstacle forecast**, below the 0.1 ms target. The entire helper call was about 95 µs when a forecast was forced on every near-obstacle call (normal scheduling is 30 Hz), and 175 µs when constructing the contact manifold. Clear-road helper work averaged about 1.2 µs; including the benchmark caller's body-velocity calculation gave 5.6 µs. There are zero library rankings inside the helper. These are repeated headless function timings, not whole-game frame rates or portable CI time thresholds.

Partial-corner and partial-height bakes remain a separate bank extension. The wider manifold must not bypass those coverage limits or repair a vehicle damaged before arming. A successful forecast cannot create a recording for a missing contact footprint.
