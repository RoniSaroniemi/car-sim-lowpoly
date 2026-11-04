# Snapshot provenance and rights

This repository packages the validated structural Niva crash probe as an independent learning example. The original release came from a fixed pre-wheel archive; the current revision includes a coherent copy of the later oriented-wheel/breakable-suspension implementation, reverified in this isolated repository. It does not read or modify the active driving sandbox or crash projects, and it has no runtime dependency on those directories.

The original archive hash, current wheel-source hashes, runtime paths, topology counts and tested Godot identity are recorded in `handover_manifest.json`. `checksums.json` records hashes of the shipped implementation, definition and model inputs. The historical `baseline.json` belongs to the older 175-link topology. The current handover structural and wheel reports belong to the 187-link topology. Fresh local runs produce a separate ignored report.

## Code and documentation

The repository's authored solver, render-binding code, shaders, generation scripts, tooling and documentation are provided under the root MIT license. The work is an approximate game prototype. Referenced papers, Godot, Blender and BeamNG remain separately owned and are linked as background; their implementations and engine distributions are not bundled here.

## Example assets

The Niva example geometry was built procedurally for this project from a user-supplied four-view reference illustration, then extended with an interior and opening panels. The Blender source and GLBs are supplied so a colleague can reproduce and study the example locally. Original authored geometry and asset-building code are covered by the root MIT license to the extent owned by the contributor.

`model/source/reference.png` is the supplied reference illustration. The base-colour atlas includes projected details from that illustration. The original illustration's separate ownership/licence was not recorded in the source package, and this repository does not assert a new licence over underlying third-party imagery. Vehicle names, badges and other marks remain the property of their respective owners; this project is not an official or endorsed vehicle asset. Replace reference-derived artwork with material you control where your distribution requires independent asset rights.

This is a provenance distinction between the reusable implementation and its illustrative input, not a claim that the reference is public-domain artwork.

## Reproducibility boundaries

- Running the demo uses the committed GLB and embedded materials.
- Regenerating `structure.json` uses Python's standard library and is byte-checked.
- Rebuilding the model uses the included Blender/Python construction source and prepared maps.
- Regenerating the reference-derived atlas additionally uses the supplied illustration and optional Pillow/NumPy.
- Game parameters were fitted for visual prototyping, not measured factory material data.
- The current wheel implementation is included and checked by its own seven-case suite and focused support/detachment tests. Its parameters remain approximate game values.
