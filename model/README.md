# Editable car model

The runnable demo loads `../assets/Niva_2121_LOD0.glb`; Blender is not required. The GLB includes embedded textures. External PNG copies are also supplied for editing and engine workflows. LOD1 is included as a starting distance asset; the crash viewer currently loads LOD0.

`Niva_2121.blend` is the packed-texture Blender 4.5 source for the operable/interior car used by the structural example. It contains a studio scene and model collections. The source car has separate opening panels, transparent windows and a simple interior. The crash viewer removes source animation players and binds render meshes to the structural skeleton instead of operating those animations.

`model/.gdignore` keeps the Blender source out of Godot's import scan. Preserve it so opening the crash project does not require a Blender installation.

## Rebuild with Blender

The model-building Python and configuration are included under `source/`; the already-prepared texture maps are under `textures/`. Use Blender 4.5:

```sh
python3 model/source/test_cabin_fit.py
blender --background --factory-startup --python model/source/build_niva.py -- --skip-renders
```

The script locates its paths relative to itself and writes fresh `.blend`, LOD0/LOD1 GLBs, operation metadata and reports inside `model/`. It does not overwrite the runtime assets automatically. `--skip-renders` avoids the extra Cycles inspection renders. Remove that flag if you want those images under `model/previews/`.

After reviewing the rebuilt GLB, explicitly copy the chosen model into `assets/Niva_2121_LOD0.glb`, reimport in Godot and run the structural verification. A model rebuild can change node ordering or exporter details; compare scene/mesh names, scale and the resulting skin rather than assuming byte-identical exports.

## Regenerate the atlas (optional)

The prebuilt maps are enough to rebuild the model. To reproduce the photographic atlas itself, install Pillow and NumPy in your own Python environment, then run:

```sh
python3 model/source/prepare_textures.py
```

This uses `source/reference.png` and writes `textures/` plus swatch metadata. Some lighting from the supplied four-view illustration remains in the base colour; it is not a physically de-lit scan. The source-reference rights are separate from the authored code; see [provenance](../docs/PROVENANCE.md).

## Coordinate and texture conventions

- Blender: metres, +X forward, +Z up; root at ground beneath the axle midpoint.
- GLB/Godot: metres, +X forward, +Y up; wheel rotation axis along Z.
- Wheelbase: 2.20 m. Other proportions follow corrected reference artwork, not a factory dimensional survey.
- Base colour: 2048², sRGB.
- Normal map: 2048², OpenGL tangent-space +Y; linear/non-colour.
- ORM: R = 1 (no baked AO), G = roughness, B = metallic; linear/non-colour.
- Separate roughness and metallic maps are supplied for tools that need them.

The interior is approximate and configurable through `source/interior_config.json`. The source hierarchy and panel configuration are useful for studying segmentation; this handover's running example remains the controlled structural crash bench.
