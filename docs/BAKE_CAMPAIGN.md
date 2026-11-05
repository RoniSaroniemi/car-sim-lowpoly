# Offline crash bake campaign

The recordings use the shared car, panel, wheel, glass and interior runtime.
Doors, bonnet and tailgate start closed and latched. Their actual plastic
deformation and mount failures are recorded; failure is not forced by a speed
label. Glass cracks, membrane motion and released fragments are saved alongside
seat and optional demonstration-airbag states.

## Coverage

| Family | Cases | Purpose |
| --- | ---: | --- |
| Horizontal | 37 | Retain the established 30° bank; add all 45° compass directions and frontal ±20° at both 60/120 km/h |
| Partial/corner | 48 | Bounded left/right finite-wall overlaps at both speeds, including measured oblique coverage gaps |
| Multiaxis | 36 | 18 directions at 60/120 km/h: top, underside, and eight azimuths at each of +45° and −45° elevation |
| Roof fixtures | 2 | Retain the existing flat/corner 35 km/h inspection cases |
| Conditioned sequence | 3 | 60 frontal → 60 at +20° → 120 at −20°, preserving previous damage |
| Total | 126 | Includes the conditioned sequence's copy of the frontal prefix |

The multiaxis family uses controlled whole-car floor impacts. Contact includes
the structural body, actual oriented tires and panel contact proxies; underside
landings may be wheel-first. These are separate recordings, not arbitrary
extrapolations of horizontal clips. Contact directions are expressed in the car
frame, and replay registration retains full 3D orientation.

## Repeatable timing

Freeze the physical source and profiles before recording. Each clip stores
source SHA256 fingerprints. A mismatch requires a new recording; changing saved
hashes to make an old recording appear current is not supported.

Use the timed campaign runner from the repository root:

```sh
python3 tools/bake_campaign.py --family horizontal --workers 4 --resume
python3 tools/bake_campaign.py --family partial --workers 4 --resume
python3 tools/bake_campaign.py --family multiaxis --workers 4 --resume
python3 tools/bake_campaign.py --family roof --workers 1 --resume
# Requires the newly generated impact_000_60 prefix:
python3 tools/bake_campaign.py --family conditioned --workers 1
```

The case inventory comes from the Godot authoring definitions rather than a
second manually maintained list. Parallel jobs suppress catalog updates; rebuild
the catalogs after workers finish. Use one worker for the legacy roof fixtures,
whose CLI writes a shared catalog. The multiaxis helper also has its own authoring
CLI and separate catalog; the same timed runner supports it.

Quality 4 runs physics at **1,920 Hz**, records **2.5 seconds** after contact and
saves **301 samples at 120 Hz**. The initial isolated frontal-60 pilot measured
**41.36 s elapsed, 41.10 s user CPU, 0.11 s system CPU**, producing **4,978,930
compressed bytes** on this Apple M3 machine. This is a pilot measurement, not a
whole-library timing estimate.

`verification/bake_campaign/<family>.json` retains each job's process wall,
user/system CPU, recorder elapsed time, frames, bytes and result. Godot's
historically named `record_cpu_ms` is elapsed time spent in recorder calls; it
is not an operating-system CPU measurement. `/usr/bin/time` supplies the latter.
Family wall times overlap when families run together; add CPU times, not their
elapsed durations. Resuming preserves the first start time and earlier completed
job timing logs, and skips only exact-source, complete files.

## Acceptance and runtime limits

Audit the saved files, then test the actual driving selector. Required evidence
includes exact physical fingerprints, complete panel/effects snapshots, finite
state, the 1,210 kg ownership ledger and disk replay with zero structural,
panel-cage, membrane or airbag solves. Record what broke rather than requiring
every high-speed case to break every window or detach a door.

The horizontal and finite-wall families have a driving contact selector. A new
3D recording is not automatically a supported sandbox contact: roof/underside
recordings require matching pose, geometry and footprint registration. An
unsupported hit must keep its documented rigid/live fallback rather than play
an unrelated clip. Similarly, the three-hit conditioned sequence covers its
recorded damage history; it does not authorize stacking arbitrary absolute
deformation tracks or healing earlier damage.

General car-body splitting remains a deferred reference probe and is not part
of this campaign.
