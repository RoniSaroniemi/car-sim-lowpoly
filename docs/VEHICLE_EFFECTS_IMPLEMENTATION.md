# Main-simulation implementation contract

Accepted user scope: integrate glass, seats/airbag, multiaxis body deformation, sensitive baked contact and conditioned sequential impacts into live authoring and baked driving. This is game physics, with measured probes as reference; there is no crash-safety calibration claim.

Authority: current main runtime at `13b637e` plus the user's implementation authorization. Compatibility: `vehicle_simulation.gd` owns the live graph, `driving_vehicle.gd` owns strict baked/rigid mode, `baked_crash_clip.gd` stores absolute graph frames, and `structural_skin.gd` binds the actual GLB. Probe results establish feasibility, not interchangeable physical outcomes. In particular, sequential delta stacking was rejected by its measured error.

| Unit | Construction path / owner | Contract | Verification |
|---|---|---|---|
| Glass | Adapt cloth/fragment probe; glass agent | Six actual panes; separate laminate/tempered settings; live mounted sheet/tears; baked state; bounded cosmetic debris | Actual car render, rigid-motion invariance, tears/release/replay, no membrane solve in baked mode |
| Interior | Adapt seat/cloth probe; interior agent | Two real front-seat groups, floor mounts, optional steering airbag; live response; baked state | No extra vehicle mass, low/high pulse, exact playback, no cloth solve in baked mode |
| Central effects/bake wiring | Implement small owned boundary; root | Explicit glass + interior composition, shared clock, optional versioned frame state | Legacy defaults, repair, seek, transition, no duplicate emissions, input fingerprints |
| Multiaxis body | Adapt verified material variant; body agent | Promote targeted roof/side strengths, preserve mass/topology/suspension; fixtures/roof bake descriptors | Full regression, roof/side permanent collapse, default graph regenerated and bank rebuilt |
| Contact sensitivity | Adapt measured armed sensor; trigger agent | Cheap nodal prediction arms wider manifold; actual contact still required; corner coverage stays explicit | Pitched hits, cancellation/no early playback, bounded cost, zero full solver |
| Sequential impacts | Adapt conditioned recordings; sequence agent | Select transition from current irreversible state; never replace with pristine state | 60→60→120 sequence, monotonic damage/release, no teleport/reattach, zero full solver |

## Effects controller interface

Root owns `scripts/vehicle_effects.gd` and central call sites. Agents provide separate `scripts/vehicle_glass.gd` and `scripts/vehicle_interior.gd`. Both extend RefCounted and expose:

```gdscript
setup(graph: RefCounted, settings: Dictionary = {}) -> void
reset() -> void
synchronize() -> void
step_live(dt: float) -> void
step_debris(dt: float) -> void
capture() -> Dictionary
begin_playback(initial_state: Dictionary) -> void
restore_interpolated(a: Dictionary, b: Dictionary, alpha: float) -> void
create_visual(skin_view: Node3D, model_root: Node3D) -> Node3D
```

`graph` references must be weak. Interior may implement `step_debris` as a no-op. `synchronize` resets motion caches after fixture teleports/relaunches without clearing irreversible damage. `reset` repairs damage and clears owned debris. Visual creation returns an unparented Node3D; root adds it under the skin view after normal binding. Visual update may be driven by that node; it must respect inspection mode and restore/hide original GLB geometry correctly. Agents may provide owned helpers/config/shaders; root owns edits to shared skin.

Snapshots are plain Godot Variant dictionaries/packed arrays, with version/profile identity. Store membrane/airbag poses in their attachment-local coordinates; rendering maps them through the current car mounts, so root registration does not need to rewrite effects coordinates. Snapshots include monotonic pane/seat/deployment/tear state and stable release-event IDs. Cosmetic particle trajectories are not recorded. `begin_playback` restores the initial snapshot and initializes emission history without re-emitting releases already present there. `restore_interpolated` performs no simulation; discrete state/events advance on their recorded sample, and node poses/hinge angles interpolate. Forward application emits each new release once. A backward seek resets/reconstructs its cursor and clears transient debris; repair clears everything.

## Main lifecycle and persisted format

The graph gets an optional `effects` owner, composed explicitly of the two controllers. Root hooks it into vehicle setup/reset, post-physics live stepping, and snapshots. Strict baked/lightweight driving runs only cosmetic debris; it never evaluates membrane/airbag/seat solvers. Baked playback applies snapshots and advances debris on the same playback clock. After a clip ends, effects keep their final state without restarting expensive simulation in strict baked mode. Live mode resumes live controllers.

New frame format is version 3, with optional `frame.effects = {version: 1, glass: {...}, interior: {...}}`. Clip metadata identifies effects profiles/code and body material profile. Legacy frames with no effects represent intact/undeployed defaults in standalone playback; rebuilt main libraries carry explicit effects. The recorder samples effects at the same 120 Hz as the body, after live authoring steps. Setup/relaunch calls `synchronize` before recording an imposed velocity boundary. All libraries are regenerated after shared physics/effects edits settle.

Glass agent owns a pure `scripts/car_attachment.gd` helper for car-rest-space mapping, with `point(graph, rest_point) -> Vector3` and `frame(graph, rest_origin) -> Transform3D`; interior may use it or its own explicit lower-floor mount basis. No GLB rebuild is needed unless root approves a coordinated asset change. Glass can extract actual pane outlines/UVs; interior can extract existing disconnected seat component groups without losing triangles/materials.

## Integration ownership and order

Agents commit only their owned modules/config/tests/docs in isolated worktrees. Root cherry-picks and owns central runtime, skin, recorder/player, sandbox UI, package runner and manifest. Contact/sequential agents provide helper APIs plus focused wiring instructions, rather than competing edits to `driving_vehicle.gd`. Root merges body profile, controllers, sensor and transition helper before re-baking the standard and conditioned banks. Existing stable sandbox remains available until that rebuild verifies.

Ready for implementation dispatch: no unresolved contract blocks the controller, material, sensor or conditioned-transition units. Rendering detail, parameter tuning and fragment budgets remain local implementation decisions behind the above interface. Missing partial-wall/low-wall recordings must remain explicit incompatible coverage rather than being hidden by a looser sensor.
