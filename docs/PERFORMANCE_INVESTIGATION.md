# Full crash-solver performance investigation

Measured on 2026-11-04 with standard Godot 4.7.2 (`ed1daf0bf`), Apple M3 / arm64.
This investigates the **full crash solver at 480 Hz and eight sweeps**. Compact
road mode, sleeping, forecasts, rendering, skinning, clip baking and voxel
matching are excluded. The live solver and its defaults were not changed.

The isolated candidate is **1.37× faster overall**: about **27% less solver CPU**.
It preserves every sampled physical result exactly in the tested cases. The
investigation does **not** establish an accuracy-preserving 2× speedup.

## Controlled results

Baseline and candidate run in the same headless process. Their execution order
reverses every substep. Two complete batches were measured, with 1,440 substeps
per solver/case (three simulated seconds). The table shows medians across the
two batches; timings come from the solver's own step counter and exclude trace
serialization. Phase instrumentation runs separately.

| Case | Baseline µs/step | Candidate µs/step | Speedup |
|---|---:|---:|---:|
| 20 km/h full width | 2,924.5 | 2,133.9 | 1.370× |
| 50 km/h full width | 2,899.1 | 2,110.6 | 1.374× |
| 80 km/h full width | 2,893.4 | 2,118.7 | 1.366× |
| 120 km/h full width | 2,879.6 | 2,102.5 | 1.370× |
| 80 km/h offset | 2,953.2 | 2,175.8 | 1.357× |
| 120 km/h offset | 2,894.3 | 2,137.1 | 1.354× |
| 120 km/h offset, wheel/body contact disabled | 2,772.9 | 2,020.8 | 1.372× |
| 80 km/h full width, weakened rail / symmetry released | 3,026.4 | 2,078.3 | 1.456× |

Separate whole-process baseline/candidate batches initially suggested gains
near 2×. Their baseline timings drifted by roughly 50% between batches; those
readings were discarded. Alternating both solvers in one process produced
consistent ratios on the two repeats. These are local CPU measurements, not a
promise of rendered frame rate or performance on another machine.

All snapshots use the final retention-tuning graph/wheel source captured for
this investigation. Exact SHA-256 hashes are in the report. Later changes to
those files require rerunning the comparison.

## What costs time

The separately instrumented 120 km/h cases attribute the full step as follows:

| Phase | Full width | Offset |
|---|---:|---:|
| Distance/suspension link projections | 71.0% | 68.8% |
| Wheel contact | 8.5% | 10.5% |
| Lateral/angular mounts | 6.2% | 5.5% |
| Link damping | 6.3% | 6.1% |
| Body floor/barrier contact | 3.5% | 7.0% |
| Symmetry | 2.3% | 0.1% |
| Prediction, velocity, break checks, diagnostics combined | 2.1% | 2.0% |

Phase timing includes its measurement overhead, so percentages are approximate.
The repeated 187-link sweeps are the first useful target. Removing all energy
and failure diagnostics would save less than 1% here and would remove useful
checks. Halving contact or damping work alone cannot deliver 2× overall.

## Reversible exact-math candidate

`tools/performance_candidates/full_solver.patch` applies only inside a scratch
snapshot created by `tools/benchmark_full_solver.py`. It:

- Uses direct point/velocity array access in full mode, retaining the original
  compact constraint path.
- Precomputes reverse traversal, body-node and suspension-link indices, plastic
  limits and denominators derived from unchanged material data. The XPBD alpha
  cache refreshes when the timestep changes. Projection order is preserved.
- Gates hardening/plastic calculations behind a **conservative force bound**.
  With nonnegative hardening, force below the base yield cannot cause yielding;
  tension only raises the threshold. The weakened-rail factor is included in
  the lower bound. Above that bound, the original yield/hardening/capping math
  runs. Every elastic projection, peak-force update, contact sweep, mount,
  damping and failure check still runs.
- Avoids scanning all structural links when checking suspension-link failure.

The cache assumes this project's fixed graph/material definitions after setup.
Topology/material edits need cache reconstruction; broken links retain their
existing flags and are still skipped. The runner checks nonnegative hardening
and the expected 480 Hz/eight-sweep baseline. Direct private link projection
fixtures initialize the timestep cache with a normal step first. This is a
review candidate, not a general-purpose replacement API.

## Accuracy evidence and acceptance

Across both eight-case batches, 60 samples per case were compared at 50 ms
intervals. The maximum node-position difference, plastic-rest-length difference
and accumulated-plastic-work difference are all **zero**. Front/cabin shortening,
yielded-link counts, sampled broken-link/detached-wheel masks and all final wheel
metrics also match exactly. This includes wheel/body-contact events/impulses,
permanent mount damage, release reasons and tire compression.

An additional **192 direct link-load fixtures** compare compression/extension
near and above base yield for body, front rail/brace, sill, engine and suspension
members, with both weak-rail settings. Force, multiplier, plastic length/work,
damage and corrected points match exactly. The direct wheel/body-contact
fixture matches and conserves the centre of mass within approximately
`3.9e-9 m`. Finite-state, maximum kinetic-energy and floor/barrier clearance
checks pass for all crash cases; sampled clearance remains within the existing
5 mm tolerance.

These comparisons establish reproducibility for this controlled graph and
bench. They do not establish physical calibration, arbitrary external loads,
all possible terrains, or equivalence at every unrecorded intermediate state.
Before live integration, run the existing combined structural, wheel, mount,
driving, adaptive and ramp suites, then inspect a rendered severe crash.

For a later approximate candidate, use these review thresholds: sampled node
error at most 20 mm, plastic-work change at most 2%, front/cabin shortening
change at most 10 mm or 2% (whichever is larger), unchanged failed supports and
detached wheels, unchanged contact-ablation effect, finite state, existing
energy limits and at most 5 mm penetration. Capture failure timing every
substep before accepting an approximate candidate; the current 50 ms masks
are insufficient to establish exact event timing.

## The tempting 2× candidate fails

Keeping the optimized code but reducing to four sweeps produces 2.43–2.52×
relative to the original eight-sweep solver in three critical paired cases:

| Case | Speedup | Maximum sampled node error | Other change |
|---|---:|---:|---|
| 20 km/h full width | 2.507× | 55.6 mm | Up to 773 J plastic-work difference |
| 120 km/h full width | 2.515× | 161.9 mm | Front shortening changes by 20 mm |
| 120 km/h offset | 2.430× | 10.055 m | Different failure/detachment states; up to 7.71 kJ work difference |

The offset node error includes divergent detached-wheel motion; it is still a
material outcome change. **Reject this candidate.** It demonstrates why a
nominal timing target is insufficient evidence for lowering iteration counts.

## Recommendation

Review the exact-math candidate separately from the adaptive runtime and baked
probe work. Its measured gain is useful, but retain eight sweeps/480 Hz. The
force-based material gate is the supported meaningful criterion from this
experiment.

Do not skip an elastic member merely because it is undamaged or below yield:
it still transmits collision loads. Do not reuse stale contact sets across
substeps without a conservative swept/deformation bound. Both changes could
alter failure order. More conservative broad-phase and allocation work can be
measured next, but contact is too small a fraction to explain another doubling
by itself. The next larger experiment should target the link-projection hot
loop's execution/data-access cost while preserving sweep order and floating
point operation order, potentially with a compiled implementation. That would
introduce a packaging tradeoff and needs its own benchmark; no 2× gain is
assumed.

## Artifacts and reproduction

- `tools/benchmark_full_solver.py`: frozen scratch copies, candidate patch,
  alternating paired timing, trajectory/contact/energy comparison, load
  fixtures and optional phase instrumentation. Uses standard Python, git and
  Godot; it never patches the live source. A rejected accuracy comparison exits
  with status 1.
- `tools/performance_candidates/full_solver.patch`: isolated candidate changes.
- `verification/full_solver_performance.json`: two-batch timings, metrics,
  source hashes, exact accuracy comparisons and phase profile.
- `verification/full_solver_reduced_sweeps.json`: rejected four-sweep experiment.
- `verification/full_solver_performance_traces.json.gz`: retained raw paired
  trajectories, rejected-run trajectories and load fixtures (about 2 MB).

Reproduce the full eight-case result, with a third timing repeat by default:

```sh
python3 tools/benchmark_full_solver.py --profile
```

Or specify the executable, repeats and isolated destination explicitly:

```sh
python3 tools/benchmark_full_solver.py \
  --godot /Applications/Godot.app/Contents/MacOS/Godot \
  --repeats 2 --profile --scratch /tmp/car-full-solver-recheck
```

Reproduce the rejected candidate over all eight cases (expected status 1):

```sh
python3 tools/benchmark_full_solver.py --candidate-sweeps 4 --repeats 1 \
  --output verification/full_solver_reduced_sweeps_recheck.json
```

The delivered rejected report uses the three critical cases listed above. The
runner's reduced-sweep command deliberately checks all eight on reproduction.
Original scratch files/logs are at `/tmp/car-crash-performance`; the compressed
archive retains the review evidence independently of that temporary directory.
Run timing in an otherwise quiet window; Godot correctness suites were paused
while the delivered timing batches ran.
