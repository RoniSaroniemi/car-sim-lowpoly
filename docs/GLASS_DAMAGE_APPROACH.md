# Bakeable vehicle-glass damage: evidence and implementation approach

Research/design note, 5 November 2026. This document proposes an implementation; it does not claim that the current car already has glass fracture or that its thresholds have been calibrated against crash tests. The separate glass probe should supply measured visual, replay and performance evidence before integration.

## Material behaviour to preserve

**Do not treat all car windows as laminated.** AGC describes laminated windscreens and generally tempered door/rear glass. A laminated pane has glass plies joined by an interlayer; the broken glass can remain attached to that sheet. Tempered glass can granulate into small pieces and lose its retention. Exact 1977 Niva glazing specifications were not verified from an authoritative model-specific source in this research. Make material type a per-window configuration, with laminated windscreen and tempered sides/rear as provisional defaults. [AGC automotive glass explanation](https://www.agc.com/en/everyday/mobility/uv_privashield.html), [NHTSA comparison of retention and fracture behaviour](https://www.nhtsa.gov/interpretations/aiam2224).

For laminated glass, **cracking, deformation, interlayer tearing and mounting release are separate outcomes**. A published automotive-glazing study models two glass plies and PVB, and evaluates crack initiation/location under impact. That supports separating these mechanisms; it does not provide a universal game threshold for this car or prove that every high-speed crash should eject a windscreen. [Zhao et al., automotive laminated-glazing impact research](https://scholarsmine.mst.edu/mec_aereng_facwork/876/).

For tempered side glass, a long-lived visibly cracked-but-solid pane is usually the wrong default. It can pass rapidly through a granulated-but-still-supported state before portions fall away. Film, rubber seals and remaining supports can change retention. The user's desired jagged remnants are a useful configurable visual target, **not a rule that every broken pane must retain a complete perimeter**. A missing tempered pane, a retained shattered laminate and an ejected whole laminate should look different.

BeamNG's documented baseline uses structural deformation groups to switch glass damage textures. That is a useful cheap coupling pattern, but the requested retained holes, stages and debris go beyond that documented texture switch. [BeamNG glass damage textures](https://documentation.beamng.com/modding/vehicle/vehicle-art/texturing/glass-damage-textures/).

## What this repository already provides

- The GLB has six independent meshes: `Glass_Windscreen`, `Glass_Rear`, `Glass_Door_Left`, `Glass_Door_Right`, `Glass_Quarter_Left`, `Glass_Quarter_Right`.
- `scripts/structural_skin.gd` already binds those meshes to the structural skeleton. Its `Glass_` branch preserves their original transparent material and bypasses the metal damage material. This is the natural rendering adapter; the body shell already has real openings.
- The exported panes have position/normal attributes but **no UV coordinates**. `model/source/build_niva.py` removes UV layers from materials without textures. The runtime's UV2 is a world-horizontal `(x,z)` projection, unsuitable as pane-local coordinates for side-window holes/cracks. Generate a dedicated normalized pane UV once at bind/preprocess time, from a cached rest-space tangent basis.
- `structure_solver.gd` exposes 38 structural/wheel positions, per-node damage/contact, link plastic lengths/damage, and some wall impulse metrics. It has no glass constitutive model and no accurate per-window glass impact force. These values are exposure proxies, not calibrated fracture stresses.
- `crash_bake_recorder.gd` records the 480 Hz full solve into 120 Hz frames. `baked_crash_clip.gd` saves/restores body and wheel state; there are currently no glass events.
- The driving sandbox now has a baked mode designed to avoid full deformation solves. Glass must consume recorded events in that mode; it must not wake the structural solver merely to create cracks or debris.

## Recommended first implementation

Keep three small pieces: per-window damage state, the pane visual, and one pooled debris system. Do not add another vehicle solver or a `RigidBody3D` for each shard.

| Material | Initial damage | Higher damage | Release / debris |
|---|---|---|---|
| Laminated | Local star/radial cracks; sheet retained | Denser cracks and a deformed retained sheet; local perforation where justified | Tear cells or mounting release can open a hole; a retained jagged band and/or larger attached sheet can remain |
| Tempered | Very short granulation stage | Partial cell release if supports/film retain some areas | Many small granular pieces; retained edge islands where configured; large portions may disappear |

Use the same user-facing stages where useful—intact, cracked, cracked/deformed or partially shattered, largely open—but allow material-specific paths. A laminated pane should not automatically become a cloud of disconnected granules just because a global speed threshold was crossed.

A pane record needs: material, rest boundary, pane-local UV basis, structural anchor weights, mounting/retention parameters, pattern seed, monotonic damage stage, retained-cell mask and tear/release amount. Keep the per-car configuration separate from the glass behaviour so a second car can supply its own outlines, supports and material types.

**Start with prefractured visual patterns.** Generate a small seeded triangulation/cell pattern offline, with matching crack lines and released fragment outlines. A 6×4 or 8×6 cell map is enough to prove partial retention; this is visual segmentation, not a claim that actual glass fractures into those cells. Do not build a new Voronoi tessellation every frame. Crack shading can use cached line data or a crack atlas. Hole masks can discard released cells while retained material stays on the existing skinned pane. Selectively add geometry only where bending/tearing must change the silhouette.

## How a crash drives glass damage

Use two inputs, rather than the vehicle's speed alone:

1. **Opening distortion.** Cache four or more boundary/support points and their structural bone weights. Evaluate edge/diagonal length changes and out-of-plane warp relative to the rest opening. These measures must remain unchanged under a rigid translation/rotation. This catches pillar/roof/sill deformation without simulating every glass vertex.
2. **Direct local contact or penetration.** A small collider/projectile may crack or puncture a pane while the body frame barely changes. Test its swept intersection against a thin pane polygon, get local UV/normal and relative velocity, and trigger a local event. Add contact energy/impulse only where the collision path supplies it. Do not infer a puncture from the coarse impact voxel alone.

Opening strain is an art-directed proxy for glass stress. Direct contact needs its own geometry and event input; neither source should be labelled a measured fracture force. For the first probe, feed explicit controlled impacts and opening distortions, compare both material responses, and tune separate thresholds with the user.

During offline full-crash recording, evaluate these small pane metrics each structural substep and emit transitions when a threshold is crossed. For existing clips, opening-distortion events can be derived from their saved positions at 120 Hz without re-running the solver; that route cannot recover missing direct glass contacts or sub-sample timing. Save which method produced the events.

## Bake the state changes; keep debris live

Add an optional versioned `glass` section beside the body/wheel frames. Legacy clips without it remain intact. A compact event could be:

```json
{"id":12,"time_s":0.1833,"window":"Glass_Windscreen",
 "stage":"perforated","pattern_id":2,"seed":17391,
 "impact_uv":[0.63,0.42],"retained_cells":"bitset",
 "release_cells":[8,9,15],"local_emit_velocity":[1.2,0.6,2.4]}
```

The clip should carry the glass-profile and fracture-pattern versions/hashes, and event cause (`opening_distortion` or `direct_contact`). Typical six-pane clips need only a few transitions per pane; record those events rather than 120 Hz trajectories for hundreds of fragments. Storage size is a design target to measure in the probe, not an established result.

At replay, evaluate the event cursor from the same clip clock as the structural pose. Apply the material state and retained mask, then emit each release event **once**. Register the local emission point/normal/velocity through the selected clip's world transform, and inherit current car point velocity (`linear + angular × offset`) before adding the release impulse. This keeps glass aligned when the car or selected bake is rotated/translated.

Debris motion can stay live and collide with the current level even though its emission is baked. Replaying against a different environment guarantees the same release events, not identical fragment trajectories. Repair must clear the owning car's pane damage and transient debris. Scrubbing backward must clear/reconstruct the event cursor and particle pool; it must not emit the same release repeatedly. For exact visual review, deterministically resimulate only the short debris lifetime after a seek, or add sparse debris checkpoints later.

## Collision, mass ownership and performance

**Recommended for this project:** a capped CPU particle array rendered with `MultiMesh`, using swept analytic floor/box collisions first. The existing Compatibility renderer does not support particle SDF collision; GPU particle collision also requires explicit particle collision shapes rather than automatically using the whole physics world. Migrating renderer solely for this probe would add unrelated work. [Godot particle collisions and renderer limits](https://docs.godotengine.org/en/stable/tutorials/3d/particles/collision.html).

`MultiMesh` batches repeated shard meshes efficiently, but culls the collection as a group. Use a bounded pool per nearby car/burst, with a correct AABB, rather than one scene node per fragment or one giant world-wide collection. [Godot MultiMesh guidance](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html).

Proposed starting budgets, **to measure rather than advertise as achieved**:

- 64–128 visible colliding fragments per nearby car; hard global cap of 512.
- Fixed 60 Hz debris update; swept segment/plane or expanded-box tests, capped to two collision resolutions per step. Endpoint-only tests can tunnel through thin walls at crash velocities.
- 2–4 s lifetime, final fade, early sleep after low-speed settling; remove far/offscreen bursts sooner. No shard-to-shard collision.
- One or a few instanced mesh/material draws per car; avoid hundreds of overlapping transparent nodes. Tiny visual glints may be a separate noninteractive effect.
- Suggested acceptance target: bounded allocations and no persistent work after pool expiry; report measured physics/upload cost separately from rendering/FPS.

These fragments are **cosmetic one-way collision particles**: world contacts affect them, but they do not push the car or add new mass to its existing 1,210 kg. A physically interactive ejected windscreen would require removing its mass from the body aggregate and transferring momentum into a new owned body. Defer that until whole-pane interaction is actually required.

## Probe evidence and integration acceptance

The separate probe should show paired laminated/tempered panes under the same controlled impulse, then each requested stage, with near views of retained boundaries and a moving view of colliding fragments. At minimum it should provide:

1. A low exposure that cracks/retains laminated glass, a stronger local perforation, and a high-release case; a tempered case with granulation and configurable retention.
2. Retained edge islands that move with the pane and match the hole mask, rather than a permanently uniform decorative ring.
3. A baked-event round trip with identical pane stages/masks/seeds/times, one emission per event, correct repair and scrub/reset behaviour.
4. Swept floor/wall collision evidence, no unbounded active fragments, and zero active debris after maximum lifetime.
5. A timing report at the declared shard cap and a real rendered capture; no claimed calibrated glass force thresholds.

After that review, integrate one windscreen and one side window on the car, using existing skin anchors. Reprocess the current bank for frame-distortion events, add a direct-contact fixture, and verify the structural/wheel frames are byte-for-byte unchanged. Only then expand to all six panes and extra fracture patterns. This preserves the current cheap baked driving path while making the glass outcome part of each stored crash.
