# Shared candidate damage materials: sandbox and saved animations

The gallery treatment is integrated as a **candidate**, not an artistically accepted final texture. The driving sandbox, structural bench and baked crash bench use the same `damage_skin.gd` renderer and the same surface-state owner under `vehicle_effects.gd`. Physics, source GLB, original texture atlas, glass/interior attachment ownership and the 1,210 kg mass are unchanged.

## Integration plan and ownership

1. Promote the reusable rest-space material and native skin binding out of the gallery. Keep art-direction controls and historical variants in the gallery.
2. Add one cosmetic surface owner to the existing effects lifecycle, with live updates, capture/restore and repair. Give newly authored clips an explicit optional surface schema; derive legacy tracks once from their existing saved fields.
3. Retain earlier surface marks across conditioned transitions and resumed driving. Seeking a standalone clip restores its exact sampled surface state. Neither path wakes structural, glass, seat or airbag solvers.
4. Verify the real driving journey, native renders, saved-frame correctness, repair and existing checks; integrate into the main sandbox branch. Artistic acceptance remains a separate user decision.

| Module | Responsibility |
|---|---|
| `vehicle_surface.gd` | Read-only graph observation at up to 120 Hz; peak damage/contact/compression and bounded rest-space footprints; versioned persistence |
| `vehicle_effects.gd` | Shared setup, live/playback transitions, surface snapshots and repair, alongside existing glass/interior |
| `damage_skin.gd` | Native bones, full 3D rest position/normal attributes, construction-time refinement, cached uniform uploads |
| `damage_layers.gdshader` | Directional chipped paint, primer/peeling lip, metal/roughness, residue and cosmetic crumple displacement |
| `baked_crash_clip.gd` | In-memory derived legacy tracks, deterministic sampled restoration, new surface schema/provenance and compatibility reporting |
| `baked_crash_player.gd` | Retain the incoming car's surface floor while sampling a subsequent clip |
| `vehicles/niva_surface.json` | Candidate material parameters, separate from recorded physical tuning |

## Live behaviour

Surface observation reads the existing node signals and link plastic lengths. It does not write graph positions, velocities, links, contacts or mass. Peak compression survives unloading. Marks are seeded in full 3D rest space, so rotations do not move their noise and mirrored UV0 does not mirror unique damage onto the other side. Contact normals are transformed to vehicle-local space before storage.

Each impact footprint has an ID, fixed rest-space centre, expanding radii, peak intensity and direction. A maximum of eight footprints bounds shader work. If a later event exceeds that capacity, the nearest existing fixed centre expands its support and retains its previous peak, rather than discarding an old footprint. This is a bounded cosmetic approximation, not exact scrape/slip reconstruction. The density noise remains anchored to absolute rest space; subsequent hits cannot re-seed/heal earlier chips. Old footprint supports and nodal fields are retained on transition.

Live updates use the shared effects clock. They run at most 120 Hz even when structural authoring runs at 1,920 Hz. A baked-to-live transition clears the active event cursor while keeping its irreversible cosmetic state, so recording clocks cannot suppress a later impact. Repair resets all fields, footprints and cursors. Ordinary rigid unsupported contacts in baked mode still do not invent a new deformation simulation or a recorded sliding scrape.

## Baked animations and compatibility

Existing version-3 clips remain unmodified. At library setup, a pure pass over their frames derives a cumulative surface track using saved node damage/contact, saved plastic lengths, fixed rest coordinates and the clip's dominant local normal. No graph mutation or physics solve is required. The derived track is cached in memory, not written into the archive or built repeatedly during playback.

Standalone/random/backward seeking restores the earlier saved sample's surface state exactly. Cosmetic events are discrete, rather than interpolated into existence before their recorded sample. The normal player retains the incoming car's surface floor on every sample, preserving earlier damage across the supported conditioned sequence and after return to driving. Cosmetic state is excluded from the **physical** conditioned descriptor hash; glass/interior, body shape, links, wheels and other physical selection checks remain intact. Cosmetic preservation is tested separately rather than making an existing physical transition dependent on an artist's preset.

New recordings include `effects.surface.version = 1`, packed 38-node peak fields and the bounded footprint list. `Clip.save` adds `metadata.surface_schema = 1` and hashes the surface state/renderer/shader/preset sources for provenance. It excludes derived caches from serialization. Malformed or unsupported explicit surface tracks fail preparation; unknown future schema versions are rejected on read. Parameters are not per-frame texture snapshots.

Historical input hashes are retained. Two cosmetic adapter files changed: `vehicle_effects.gd` and `baked_crash_clip.gd`. `bakes/surface_adapter_compatibility.json` records exact old/current hashes for those changes. `Clip.input_compatibility` reports whether source inputs are exact or require that receipt; unknown adapter revisions and changed physical inputs are rejected. Verification checks *playback compatibility*, without claiming the historical authoring sources are identical to today's renderer. Conditioned authoring also uses that explicit receipt when validating a historical prefix.

## Controls and reproduction

The normal sandbox flow is unchanged:

```sh
python3 tools/demo.py drive
python3 tools/demo.py drive-sequence
python3 tools/demo.py baked
```

R repairs, B selects live/baked mode, and the existing local-detail checkbox in the crash bench isolates the cosmetic treatment. No material editor was added to normal driving UI.

```sh
# Gallery for continuing art direction, preserving v1/v2/v3 variants:
python3 tools/demo.py damage-studio

# Candidate surface lifecycle, seeking, persistence and native binding:
python3 tools/demo.py verify-surfaces --no-import

# Actual sandbox three-impact → resumed driving → repair, then live oblique:
python3 tools/demo.py capture-surfaces --no-import

# Full existing suite, now including the focused surface checks:
python3 tools/demo.py verify --no-import
```

Generated proof lives under `verification/damage_surface/`, and the focused machine report is `verification/vehicle_surface_validation.json`. Retained review images and reports are under `docs/evidence/damage_materials/`. The capture script adjusts only its inspection camera, leaving normal sandbox cameras and controls unchanged.

The Niva uses `vehicles/niva_surface.json` by default, matching the existing glass/interior profile conventions. Another vehicle profile can provide `effects.surface.preset` and `effects.surface.enabled`. `enabled: false` retains the source material path. Gallery presets are independent: a gallery change is not silently promoted into the runtime preset.

## Verification and material limits

The full repository suite passes: six structural runs; wheel/mount/retention, driving/adaptive/ramps, 27-clip saved poses, driving bake handoffs, glass/interior, conditioned state/bank/sequence, quality smoke and roof playback. The new focused suite has 24 passing checks, including explicit surface disk roundtrip, deterministic seeking, future/malformed schema rejection, all-layer repair, unchanged graph/mass/solver counters, full 3D rest attributes, no per-update topology rebuild, bounded overflow preservation and exact-revision provenance rejection.

Actual sandbox native renders were captured and inspected for the first/second/third baked impacts, resumed driving, live oblique damage, geometry-only comparison and repair. The three-clip journey used zero structural, membrane or cloth solves; live rendering uses the real live impact path. These are integration proofs, not artistic acceptance.

The candidate native mesh has 57,624 triangles/car and 39 bones. Refinement and rest attributes are assembled once at construction; parameter/pose updates do not rebuild topology. Cosmetic displacement is outward along the post-skin surface normal and capped at 65 mm. Its small impact-core faces grow into larger peripheral folds; large-scale collapse remains the original skeleton. No source mesh or collider changes were made. The shader retains procedural-noise cost and bounded footprint evaluations; gallery timings do not establish gameplay GPU cost or FPS, and Compatibility GPU timestamps were unavailable.

Paint eligibility is still reconstructed from this Niva's olive atlas and is not production-ready multi-paint eligibility. Peeling edges are shaded relief rather than independent curled paint meshes. Dust/grime direction is art-directed from a dominant impact normal and rest-space flow; old clips have no exact slip history. There is no automatic claim of burning, physical holes or torn edge geometry. Extreme structural self-intersections remain visible. Preset refinement and final texture approval remain open.
