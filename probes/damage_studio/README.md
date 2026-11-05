# Nine-case damage material studio

Run from this worktree (Godot 4.7.2 Compatibility):

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --resolution 1600x1000 res://probes/damage_studio/studio.tscn
```

The native window remains open for direct art direction. Click a cell or press 1–9 to focus; drag to orbit, wheel to zoom, C for close-up, 0/Esc to return. B switches the same saved pose between original section treatment and layered materials. Buttons also select original paint. Independent toggles isolate folds, normal creases, coating/metal and roughness, with masks and plain geometry diagnostics. The nine board cameras reset to fixed positions on return from focus.

Sliders update all nine cars. Edit `presets/current.json` and press R to reload. Type a filename without extension into the name field to save/load a named JSON preset. `presets/starting.json` preserves the initial appearance. Primer/metal colors use HTML sRGB colors; shader uploads convert them to linear. Loss threshold increases coating retention, pattern scale increases spatial frequency, and crease scale changes normal-detail frequency. Fold strength scales cosmetic displacement only.

P/Capture saves the real Godot window plus a timestamped JSON containing the exact parameters, toggles, camera and source cases. Stable latest images live in `captures/latest_board_layers.png`, `latest_case06_layers.png` and `latest_case06_baseline.png`. Timestamped variants remain alongside them. Capture action renders on demand. Restart with `-- --studio-capture` to capture the board and matched case 6 A/B, measure idle/focus/orbit, then return to the board and stay open.

## Saved states

| Case | Source | Time (s) |
|---|---|---|
| 1 | `probes/damage_surfaces/data/light_20.crashclip` | 0.000000 |
| 2 | `probes/damage_surfaces/data/light_20.crashclip` | 2.500000 |
| 3 | `bakes/impact_030_60.crashclip` | 0.008333 |
| 4 | `bakes/impact_000_60.crashclip` | 1.000000 |
| 5 | `bakes/impact_030_60.crashclip` | 1.000000 |
| 6 | `bakes/impact_090_120.crashclip` | 1.000000 |
| 7 | `bakes/impact_180_60.crashclip` | 1.000000 |
| 8 | `bakes/conditioned/front_60_60_120_step_2.crashclip` | 0.750000 |
| 9 | `bakes/roof/roof_corner_35.crashclip` | 1.000000 |

All frames, histories and 3D rest-space fields are prepared once at startup. Material edits upload uniforms only; they do not read crash clips, resample frames, update fields, or solve physics. Nine independent viewports request UPDATE_ONCE when changed; focus orbits request a render only for the selected car. The root UI runs at a 60 FPS cap. The same studio environment/exposure is used throughout. Detached wheels remain in their recorded positions, so some leave the material-focused crop. Case 3 is an early recorded corner dent, not an invented sliding scuff.

## Verification and scope

`check.gd` passes 16 focused checks covering all nine key selections, board camera restoration, shared uniforms, plain isolation, original shader baseline, named preset roundtrip, unchanged saved states/field counts and zero structural/glass/cloth steps. Run:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://probes/damage_studio/check.gd
```

The existing damage-surface suite also passes all 26 checks. Real native screenshots were visually inspected; `captures/checks.json` and `captures/measurements.json` contain results.

Latest native Apple M3 run: startup 4.49s; nine-car material uniform update 0.56ms CPU; root frame intervals 16.64ms board idle, 16.65ms focus idle and 16.67ms orbit at the 60 FPS cap. GPU timestamps return zero/unavailable. These are bounded preview measurements, not GPU cost or gameplay performance claims.

The original layered shader remains unchanged under `probes/damage_surfaces`; this studio owns its shader copy and parameter presets. All shared simulation, model and source texture files are unchanged. Starting art still shows repeated peel bands and a broad side scuff; these are candidates for the user's next visual direction, not a finished realistic texture claim. Contact fields are scalar peaks with a dominant clip normal; exact scrape/slip history is unavailable. Color-based olive paint eligibility is still Niva-specific. UV0 remains untouched; 3D rest attributes preserve left/right and height locality. Coating loss does not represent a torn hole. Extreme geometry self-intersections remain visible.

## Angular folds and chipped paint, v2

The new treatment uses irregular rest-space cell faces meeting at angular crease junctions, in place of periodic section stripes. The saved skeleton remains unchanged. Cosmetic vertex relief stays outward and is capped at 32 mm so it does not cut through the inner liner; small fold gradients supply the sharper highlights. The can reference guides crease form, while the supplied blue-car reference guides paint loss and peeling edges.

Shallow scuffs lighten the body color and raise roughness. More severe damage crosses a separate coating threshold into sparse narrow gouges; a sharp metal mask has a thin primer fringe and a raised paint-edge normal/highlight. The edge is a material approximation, without separate curling paint geometry. Adjustable dust/grime is projected along an art-directed rearward tangent, with a downward fallback for front-facing panels. It is dirt/residue, not evidence of burning or recorded slip.

Additional sliders: Paint scuff, Peel edge, Grime, Grime trail. `trail_direction` in the preset controls the art-directed longitudinal trail sign (-1 rearward). Masks now display metal red, paint scuff green, residue blue. The previously overwritten layer toggles now survive uniform updates. Non-body materials retain their original damage eligibility.

V / Previous-new switches v1 and v2 shaders using the same parameters, frame and camera. B still selects the original section baseline. The exact original shader is preserved in `variants/v1/studio_layers.gdshader`; the user's earlier saved parameters remain in `presets/user-20261105-134309.json`. `presets/angular-peel-v2.json` and current.json contain the new starting variant. Snapshots record shader variant and SHA256 alongside parameters.

Native board, case 6 baseline, and case 5 previous/new comparisons were captured and inspected after refinement. The final focused suite has 20 passing checks, including toggle persistence, previous-shader availability, non-body eligibility and no physics/field resampling. Latest measurements remain in captures/measurements.json; root frame intervals remain capped around 16.7 ms and GPU timestamps remain unavailable. Further aesthetic tuning should follow direct user feedback.

## Impact-centred taper and displacement, v3

V now compares v3 to the preserved v2 shader; v1 is also retained on disk. V3 keeps v2's metal, primer, lifted coating lip and roughness response, while replacing isolated line gouges with a shared elliptical impact envelope and high-contrast layered point/stretched noise. Intensity fades out of the same region that controls the crumple. `Impact spread` adjusts its extent.

Each case's centre and radii are precomputed from recorded body-node contact, plastic damage and peak compression, using a weighted rest-space centroid and variance. If body contact scalars are absent (the roof clip), the recorded body hit nodes supply the centre. First-contact wheel nodes are excluded. This is a cosmetic placement heuristic from coarse data, not a recovered contact/slip map. Global strength follows measured front/cabin/width/roof deformation, keeping the light fixture restrained. Per-case centres/radii/strengths are included in capture case metadata.

Procedural height is sampled for real outward post-skin vertex displacement as well as finer normal gradients. There is no constant-height pedestal; the old clamp plateau is removed. Cell coordinates change continuously from smaller core faces to larger peripheral faces, and relief amplitude fades toward untouched paint. Height is capped at 65 mm, with no negative liner-crossing offsets. The studio now refines paint-region geometry more densely once during construction: 57,624 triangles/car (previously 39,673). No mesh rebuild, solver step, frame read or field resampling occurs during slider changes. Body mass, source GLB and shared runtime are unchanged.

`presets/impact-core-v3.json` preserves the new starting preset, also loaded as current.json. V2 shader/preset are under `variants/v2/`. The final suite passes 24 checks, including contact-side placement, roof fallback, light restraint and increased displacement vertex coverage. Native board and matched case 5 close-up V2/V3 were rendered and visually inspected. Latest native load was about 4.83 s; nine-car uniform upload about 0.62 ms, root frame intervals about 16.67 ms under the 60 cap; GPU timestamps remain unavailable.
