# Articulated vehicle panels

The main Niva uses the approved door/bonnet/hatch probe mechanics through the shared `VehicleSimulation` and `DrivingVehicle`. `vehicles/niva.json` explicitly enables them. Bare Structure graphs and other vehicle profiles remain supported without a panel owner. The current component definitions and donor nodes are specific to this Niva; another car needs its own measured component cage/pivots/mass donors, not just the profile enabled.

## Ownership and states

`Structure.panels` owns mechanics (`vehicle_panels.gd`, `road_panel_profile.gd`, `panel_angular_mount.gd`, `reduced_vehicle_panels.gd`). Effects own cosmetic glass, interior and surfaces, and never step panel mechanics.

The gross ledger remains 1,210 kg. Left/right doors 25 kg each, bonnet 18 kg and hatch 22 kg are extracted from existing body-node donors exactly once when independent. `body_mass_kg` and compact inertia describe the remaining body. `config.mass_kg` stays the gross vehicle mass; incident impact estimates still use it. Rest masses, inverse masses and link damping caches are restored/reconciled at mode transfers and snapshots. Wheels remain their existing owned masses.

- Healthy closed panels follow the body with condensed mass and no cage solver.
- Healthy opening disengages closing constraints first; hinges stay attached. Quiet aligned closing reengages only surviving connections and condenses again.
- Closed impact uses reciprocal hinge/latch/frame-seat constraints and a 10-point plastic cage. Door deforms between supported frame locations. Local directional damage and sustained loads govern failure; vehicle speed is not a release command.
- After impact the established shape freezes. A free door uses 120 Hz reduced rigid articulation and reaction impulses. A surviving single hinge resists tilt, yields its local rest axis and can tear under extreme sustained torque. It is not a ball joint.
- Detached panels keep their existing pose/momentum and use five finite support/contact proxies, then sleep. General panel-versus-car self-contact is not implemented; a released door can pass through the remaining car.

Both live authoring and ordinary driving use `road_panels_v2` (16 kN upper hinge, 9.6 kN lower, 8 kN latch). These are conservative game settings, not real Niva crash calibration. The old weak striker example stays isolated under `probes/panels`.

## Rendering, controls and windows

The public `damage_skin.gd` automatically adds the four panel-local cages when enabled. `layered_damage_skin.gd` preserves the merged 603c3fd material implementation. UVs, original trim/inner skins, custom rest attributes and normal semantics are retained; no runtime mesh reconstruction or GPU readback occurs. Forty panel bones add pose-upload work; sleeping physics does not remove that render cost.

`set_panel_open(id,degrees) -> bool`, `panel_state(id)` and `panel_states()` are shared runtime APIs. IDs are `door_left`, `door_right`, `bonnet`, `tailgate`. `panel_controls.gd` is a reusable VBoxContainer with `setup(vehicle)` for either sandbox. Controls never repair damaged mounts. Reset is the explicit repair action.

Door and rear glass use the same four-weight panel mapping as their render skin; fixed windscreen/quarter glass keep the body mapping. Pane frame, membrane targets and inherited point velocities use the owning panel exactly once. Glass mesh rebuilding preserves four versus eight bone weights. Seat/airbag ownership is unchanged.

## Recorded state

Graph snapshots optionally contain `panels_schema:1`, panel state and `mass_nodes`. Panel state version 3 omits immutable rest topology/bindings from every frame; restore merges dynamic values onto the measured component configuration. Captures retain cage pose/velocity, plastic edge lengths/damage, attachment/exposure flags, closing topology, frozen shape, reduced pose/motion, angular plastic rest state, profile and stable events. CPU counters and mapping caches are not replay state.

`panel_snapshot.gd` transforms world cage points, velocities, reduced COM/quaternion/linear/angular velocity and old mount velocity once through clip registration. Frozen component offsets/inertia, attachment-local plastic axes, rest bindings and frozen-local shape remain local. Continuous pose interpolates; failures, ownership and events sample the earlier frame. Constraint accumulators are transient and cleared before new full solves. Conditioned descriptors match irreversible material/attachment history and component shape with 25 mm pose tolerance, while allowing equivalent held-full versus frozen/condensed representation. Existing free pieces ignore a subsequent car clip and continue their world-owned cheap trajectory. Staging likewise moves only attached components.

Strict baked driving never wakes full body/cage/membrane/airbag solvers. Recorded panels are playback-owned; only previously detached pieces step independently. New open/damaged configurations need compatible recordings; otherwise strict mode uses cheap contacts. Historical archives lacking panels remain closed-body inspection recordings. Physical input changes require actual regenerated recordings; the cosmetic material adapter is not used to waive them.

## Verification checkpoint

Commands from the repository root:

```sh
python3 tools/verify_panels.py
```

The runner checks the actual main driving adapter, open-close condensation, mass, moving glass, spatial registration/disk seeking, preexisting free-piece ownership, local side release and stiff hinge reduced motion. `author_roundtrip.gd` generates a fresh 301-frame 60 km/h clip locally; it does not overwrite the shared bank.

Native evidence is in `tests/panels/main_open.png`, `main_inside.png`, `main_deformed.png`; the latter inspects the freshly authored main 60 km/h recording. `driving_results.json` records actual main 60/120 km/h×0/±20/±30 and W-throttle-from-rest outcomes. Measured contact velocities vary with the approach; all closed doors retain their hinges/latch/seats while plastically deforming. Severe local side intrusion can still release a panel. The original 78+84+109 isolated probe checks also pass after promotion.

Checkpoint CPU per 120 Hz update (M3, headless, no renderer): closed mean/p95/p99=1151/1166/1179 µs; damaged free right door 1240/1263/1335 µs; stiff single hinge 1225/1244/1270 µs. All three run zero full structural/cage steps; single-hinge maximum tilt 9.75°. These are solver CPU measurements, not GPU timings or whole-game FPS. Original probe panel pose upload measured roughly 255 µs versus 32 µs body-only; main material/render cost is separate.

The shared physical bank regeneration and complete main verification remain an integration gate; until rebuilt, incompatible historical banks are explicitly rejected by runtime selection.
