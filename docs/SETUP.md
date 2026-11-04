# Local setup and reproduction

## Dependencies

| Task | Dependency |
|---|---|
| Open/run/import the demo | Standard Godot 4.7.2, graphical driver supporting its Compatibility renderer |
| Launch/check/regenerate the graph with supplied tools | Python 3.10+ standard library |
| Edit/rebuild the car | Blender 4.5; uses Blender's bundled Python and mathutils |
| Regenerate the photographic texture atlas | Optional Pillow and NumPy in a separate Python environment |

Install dependencies yourself. This repository contains no engine binaries, virtual environment or vendored packages. Godot includes Jolt; an external Jolt extension is unnecessary. The `.NET` editor is unnecessary.

## First run

1. Clone or download/extract the complete repository. Preserve relative paths.
2. Import `project.godot` with Godot. Let the GLB and texture import finish.
3. Press F5 and click **Run structural impact**. For automatic playback use `python3 tools/demo.py run` instead.
4. The default is an offset impact at 120 km/h. Choose Full-width frontal for the symmetric bench. Select **Textured car**, disable **Structure overlay** and inspect the body. Compare with **Plain bodywork** and **Bare structure**.
5. Scrub the replay after the three simulated seconds finish. Reset before changing speed or rail strength.

The Python runner can locate Godot in PATH or in the usual macOS application location. Pass `--godot "..."` for portable Windows executables or nonstandard installations. `Open_Demo.command` and `Open_Demo.bat` call the same runner.

Direct commands, if you prefer not to use Python:

```sh
godot --headless --path . --editor --import --quit
godot --path . -- --autoplay
```

Replace `godot` with the full executable path as needed. Export templates are not required for editor playback or the verification commands.

## Verify before modifying

```sh
python3 tools/demo.py check
python3 tools/demo.py verify
```

`check` regenerates the graph deterministically and checks that its bytes match the committed definition. It also checks mass, link endpoints, GLB mesh naming, Blender-file presence and file hashes. It does not prove dynamic correctness.

`verify` imports with the selected Godot, then runs 20/50/80/120 km/h structural impacts, two symmetry-free 80 km/h strength comparisons, and seven wheel cases including offset impacts and a wheel/body-contact ablation. It exits nonzero if a required check fails. Read the fresh JSON report rather than treating the screenshots as validation. On a slower machine, allow the process to finish; headless playback runs at a fixed presentation rate but still performs the structural substeps.

For only the wheel suite, use `python3 tools/demo.py verify-wheels`. The suite also checks gravity support, equal/opposite internal contact response, detachment continuity, detached-wheel contact, replay and reset. See [wheel setup](WHEEL_PHYSICS.md).

## Regenerate and tune the structure

```sh
python3 scripts/build_structure.py
```

The generator is authoritative when used: it overwrites `structure.json`. For persistent changes edit the generator; for a quick experiment edit a copy of the JSON and do not regenerate over it. Restart the running demo after graph or script changes.

After changing physics parameters, run `verify` again. The baseline thresholds include this example's mass and topology. Changing those deliberately requires updating the checks with a clear reason; changing a threshold merely to make a failed run pass hides a problem.

## Capture actual screenshots

```sh
python3 tools/demo.py capture
```

This uses a GPU SubViewport while starting the main window minimised. A graphical session is required; do not add `--headless` and expect useful rendered evidence. Images are written under `verification/`. The committed examples under `docs/images/` are from this snapshot's original validation, not generated mockups.

## Common problems

| Symptom | Check |
|---|---|
| GLB cannot be loaded | Run the editor/import command first; keep all asset paths intact |
| A different Godot starts | Pass `--godot` explicitly and inspect the printed version |
| Blender is requested when opening the demo | `model/.gdignore` must remain present; the runtime uses GLB, not `.blend` |
| Bare bars appear instead of the car | Press 3 or choose Textured car |
| Car remains stationary | Click Run or use the `--autoplay` runner |
| Slow playback | Disable Slow motion for real-time feeding; physics still runs at 1/480 s |
| Wall disappears after impact | Intended inspection behaviour; B toggles the marker, not contact physics |
| New model deforms in the wrong direction | Check metres, axes, baked transforms, station coordinates and mesh naming |

The baseline holds the state after three simulated seconds, even if some residual motion remains. This makes replay inspection repeatable; it is not an automatic equilibrium detector.
