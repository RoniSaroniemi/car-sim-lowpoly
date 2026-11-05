# Measured sampling, packing and streaming experiment

The [complete experiment and reproducible commands](../probes/bake_sampling/README.md)
include native comparison images/video, raw trials and the prototype codec.

One existing frontal 120 km/h recording, authored at 1,920 Hz and saved at 120 Hz,
was compared with 30 Hz,15 Hz and error-bounded adaptive keys. Rendering still
interpolates every display frame; the original physics is not rerun at the lower
frequencies.

| Approach | Compressed file | Reduction from original |
| --- | ---: | ---: |
| Original 120 Hz | 5.22 MB | — |
| Adaptive keys, snapshot size baseline | 1.93 MB | 63% |
| Adaptive keys plus compact state/events | 1.07 MB | 80% |

The adaptive candidate kept 112 instead of 301 poses. Its worst body/wheel control
point error was 0.98 cm; panel proxies stayed within 1.49 cm. Held decoded-data
heap fell from 56.6 MiB to 2.24 MiB on this clip. These are Godot-tracked data
allocations, not total game RAM or OS RSS. Flags, masks and failure timestamps
retain the saved 120 Hz reference semantics.

Uniform 30 Hz and 15 Hz had much larger worst shape errors during rapid impact,
even though their interpolation was smooth. Adaptive density tapered from 43
keys in the first half-second to 8 in the last.

An independently decoded half-second packet player matched its full-file variant
through boundaries and rewind. The adaptive header plus first packet was about
422 KB and loaded/decoded in about 1.5 ms in the local warm-filesystem test. Real
network latency, cold storage and production shared caching/prefetch are not
measured here.

**This remains an isolated one-clip experiment.** Main sandbox playback, its
132 recordings and their 120 Hz sampling are unchanged. More impact types,
consumer/handoff validation and allocation/streaming work are required before
adopting the format.

[Comparison video](../probes/bake_sampling/evidence/comparison.mp4) ·
[Early-frame comparison](../probes/bake_sampling/evidence/early_17ms.png) ·
[Measurement summary](../probes/bake_sampling/evidence/summary.json)
