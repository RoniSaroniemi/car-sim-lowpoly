# Baked crash status and optimization work

Baking and contact-time playback work, but the baked asset format, loading and
playback pipeline are **not yet optimized for shipping**. Continuous tracks are
still **120 Hz**: a 2.5-second impact normally stores **301 full snapshots**.
This is independent of rendering FPS. Offline authoring generally uses 1,920 Hz
physics; the driving root, wheels and baked sampling advance at 120 Hz.

The main bank contains **132 recordings, 622.18 MiB compressed on disk**. The
separate multi-car example adds one opposed-impact composite. These are file
sizes, not decoded/peak RAM measurements. Current counts are saved in
[the release inventory](evidence/release_2026_11_05/bake_inventory.json).

| Main family | Clips | Compressed MiB |
| --- | ---: | ---: |
| Horizontal directions | 37 | 175.66 |
| Partial/corner wall contacts | 48 | 245.51 |
| Conditioned three-impact sequence | 3 | 15.41 |
| Moving roof landings | 6 | 24.35 |
| Older roof inspection fixtures | 2 | 7.34 |
| Experimental multiaxis | 36 | 153.90 |
| **Total** | **132** | **622.18** |

The driving adapter eagerly loads 94 standard/partial/conditioned/roof-landing
recordings and shares those arrays across cars. Surface, roof-response and local
shape caches add preparation time and memory. Source files use compression;
source sharing and zero-full-solver playback already help runtime cost. There is
no shipping lazy-load/prefetch budget, packed numeric track format, lossy
quantization, event-separated storage, keyframe reduction or measured decoded
RAM budget yet. Startup/loading is excluded from the historical playback-only
CPU benchmarks. Do not use those timings as a whole-game FPS claim.

## Measured prototype, separate from shipping playback

The [single-clip sampling/packing/streaming experiment](BAKE_SAMPLING_PROBE.md)
now demonstrates about80% compressed size reduction and96% held-data heap
reduction with adaptive keys, compact channels and exact sparse events. It has
native visual comparisons and independent half-second packets. These are one-
clip measurements, not bank-wide savings. The main format and runtime have not
adopted those changes. Tests across the remaining cases are still needed.

## Next optimization experiments

1. Measure disk, decoded/peak RAM, cold/warm loading, allocations and playback
   mean/p95/p99 separately from rendering and per-car state.
2. Add a small metadata catalog and shared bounded clip cache, with measured
   prefetch and explicit cold-contact behavior. Keep heavy physics asleep.
3. Separate continuous shape/pose tracks from persistent damage and discrete
   failure/release events; pack reusable numeric buffers instead of copying
   nested dictionaries each sample.
4. Compare 120/60/30 Hz and adaptive keys on the same reference impacts.
   Preserve exact hinge failures, glass release/deployment timestamps and part
   ownership; retain denser keys where fast motion needs them.
5. Test quantization/delta compression independently, then combine demonstrated
   savings. Compare intermediate times, native renders, event momentum,
   sequential impacts, seeking, reset and multiple cars sharing the bank.

No percentage improvement is claimed before measurement. Existing original
recordings remain the reference. Any format change must retain source/version
checks, immutable shared data, one mass owner, previous damage and zero full
structural/membrane/cloth solves in baked mode.

## Coverage is distinct from physical quality

Source/replay audits check provenance, stored components and replay registration;
they do not certify every authoring trajectory as physically valid. The original
experimental multiaxis campaign retains eight upper-angle energy-quality
failures in its historical [campaign statistics](evidence/bake_campaign_stats.json).
Those recordings remain reference material. Runtime roof landings use the
separate softened-roof recipe and explicit game-directed playback response.
See [current supported behavior and limitations](STATUS.md).
