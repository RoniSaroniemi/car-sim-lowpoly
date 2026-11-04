# Baked crash library: local verification

Godot 4.7.2, macOS / Apple M3. 26 saved clips; all 264 library checks passed.

All 26 authored approaches selected their own recording. All 27 unrecorded angle checks selected a compatible nearby angle at the correct speed. No structural solver steps were executed by any replay.

Maximum authored position error: 0 m. Maximum final registered position error: 0 m. Maximum contact-handoff displacement: 2.32830644e-10 m.

Saved damage, link lengths/broken flags, wheel orientation/spin and detachment states matched their authored samples. All frames remained finite. Impact speed was checked against the requested 60/120 km/h.

| Recording | Heading | Impact km/h | Selected fit | Full solver steps in replay |
|---|---:|---:|---:|---:|
| frontal_120 | 0° | 120 | 100.0% | 0 |
| front_left_20_120 | 20° | 120 | 100.0% | 0 |
| front_right_20_120 | -20° | 120 | 100.0% | 0 |
| impact_000_60 | 0° | 60 | 100.0% | 0 |
| impact_030_60 | 30° | 60 | 99.9% | 0 |
| impact_060_60 | 60° | 60 | 99.9% | 0 |
| impact_090_60 | 90° | 60 | 86.6% | 0 |
| impact_120_60 | 120° | 60 | 99.9% | 0 |
| impact_150_60 | 150° | 60 | 99.9% | 0 |
| impact_180_60 | -180° | 60 | 100.0% | 0 |
| impact_210_60 | -150° | 60 | 99.9% | 0 |
| impact_240_60 | -120° | 60 | 99.9% | 0 |
| impact_270_60 | -90° | 60 | 86.6% | 0 |
| impact_300_60 | -60° | 60 | 99.9% | 0 |
| impact_330_60 | -30° | 60 | 99.9% | 0 |
| impact_030_120 | 30° | 120 | 100.0% | 0 |
| impact_060_120 | 60° | 120 | 100.0% | 0 |
| impact_090_120 | 90° | 120 | 100.0% | 0 |
| impact_120_120 | 120° | 120 | 100.0% | 0 |
| impact_150_120 | 150° | 120 | 100.0% | 0 |
| impact_180_120 | -180° | 120 | 100.0% | 0 |
| impact_210_120 | -150° | 120 | 100.0% | 0 |
| impact_240_120 | -120° | 120 | 100.0% | 0 |
| impact_270_120 | -90° | 120 | 100.0% | 0 |
| impact_300_120 | -60° | 120 | 100.0% | 0 |
| impact_330_120 | -30° | 120 | 100.0% | 0 |

The fit score includes contact-zone overlap and local impact normal, rather than being a probability. For some side cases the common pristine approach touches two conservative probes while the prepared recording first touches one, reducing the fit score even at the same requested angle.

These checks validate recording fidelity and controlled selection. They do not calibrate crash physics, establish accurate contact for intermediate angles, or validate free-driving integration. See [the procedure and limitations](BAKED_CRASH_PROBE.md).

Fresh local reports are generated in `verification/`; the saved clip catalog is [bakes/library.json](../bakes/library.json).
