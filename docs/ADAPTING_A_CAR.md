# Procedure: adapt the example to another car

Work in a new repository/branch or copy. First reproduce the supplied Niva and keep its passing report as a control. The renderer contains vehicle-specific assumptions: swapping a GLB alone is insufficient.

## 1. Establish one coordinate system

Use metres, +X forward, +Y up and Z across the car in the Godot runtime. Put ground at Y=0. Verify wheelbase, track, overall height and axle centres before tuning damage.

For reference sheets, crop views independently and align structural landmarks. Side view can define wheelbase/height; front/rear constrain width; top constrains plan shape. Different image panels may require different X/Y scale corrections. Do not stretch the finished mesh independently in each view to hide inconsistent references. Record the transforms used and the uncertainty in unobserved regions.

Apply mesh transforms or bake them consistently before binding. Keep a common origin for the physical graph and the imported car. An unrecognised unit conversion can make correct-looking node placement produce extremely wrong stiffness or impact energy.

## 2. Segment by physical behaviour

Separate these concerns before building a dense mesh:

- Deformable body shell: rails, sills, floor, pillars, roof and crossmembers.
- Stiffer mass clusters: engine/gearbox and other concentrated heavy components.
- Oriented wheel assemblies, six hub hardpoints per wheel, yielding angular knuckles and selected nearby body-contact segments.
- Render-only small details: trim, handles, grille internals, markings and fine seams.

Keep rigid components out of broadly blended shell weights. Existing doors, bonnet and tailgate can remain part of the deformation skin initially; opening hinges, thickness and later detachment need their own coherent ownership. This crash example does not operate the source GLB's panel animations or lights.

## 3. Place a sparse load-bearing graph

Start with the seven body sections in `scripts/build_structure.py`. Place section changes at the rear structure, rear cabin, middle cabin, firewall, engine bay and front impact structure. Fit lower/upper section corners to structural load paths rather than every visible exterior contour.

The current generator assumes **four nodes per section and exactly seven sections**. For a first adaptation, keep those counts and change the station positions, upper heights and widths. That lets you reuse the rest of the code while learning what each member group does.

Add longitudinal lower/upper members, cross-section rings, selected diagonal shear support and longer bending-support links. A box formed only from freely rotating edges can shear into a mechanism; cross-bracing provides the missing resistance. Excessively strong braces can also prevent the crumpling you want. Distinguish actual members from numerical shell-stiffness substitutes in your notes.

Small deterministic initial curvature can guide buckling. Keep its magnitude small relative to the body dimensions and explain it as an initial imperfection, not an authored crash result.

## 4. Assign mass once

Choose the total vehicle mass, then distribute it deliberately. Keep much of the passenger/body mass low. Model a heavy engine as a stiff cluster attached by yielding mounts; avoid giving the roof a large share of the mass just because it has many nodes.

Sum all node masses. If you add interior components with their own physical mass, subtract that mass from the lumped body allocation. A render seat does not need to be a separate solver object. Do not add a second full-mass rigid chassis when integrating with an engine.

The demo and validation hardcode 1,210 kg in places. Update the assertions when deliberately changing the example's mass. Preserve an explicit accounting check.

## 5. Tune basic support before crashes

Set moderate connection stiffness and damping, then check that the graph remains supported under gravity. Watch the bare structure. Run the wheel standing-support check before crash tuning; it catches hubs collapsing under gravity without an impact. A car that folds or oscillates uncontrollably before impact needs geometry/constraint fixes before material tuning.

Use a low-speed frontal run first. Check that connections rebound elastically below yield and retain rest-length changes above yield. Increase speed gradually. Tune the crumple-zone load path before changing the cabin; inspect whether engine inertia and mounts contribute as intended.

Keep the fixed timestep and iteration count unchanged while comparing materials. Change one member group at a time. Record parameters and outcomes; otherwise strength, symmetry and contact changes can be confused with one another.

## 6. Bind the render model

In `structural_skin.gd`, update the GLB path and mesh naming rules. This implementation recognises `Niva_Body_Static`, `Panel_*`, `Glass_*`, `Niva_Interior_Static` and `Wheel_*`; source wheel names distinguish front/rear and Left/Right. Unrecognised meshes may receive inappropriate general body weights.

For body vertices, interpolate between nearby structural sections. In this example each vertex uses up to eight weights from two four-corner sections. Check that all weights sum to one. Inspect rigid items and wheel meshes separately rather than applying shell blending everywhere.

The current script includes a hardcoded engine-interior region. Replace it with a named engine mesh or an appropriate region for the new car. Inspect through the windows, under the car and at door openings.

Use the plain-body view with local folds disabled. If the large-scale shape is wrong, adjust the structural layout or binding rather than hiding it with texture damage.

## 7. Add enough topology where it matters

Only add subdivisions to render panels that must bend visibly. Preserve UVs and normals. The example refines selected triangles at load time; it never runs render-mesh subdivision as part of a physics step.

More render vertices make a folded silhouette smoother but do not add physical load paths. More physical nodes add solver cost and can change stiffness/mass behaviour. Treat those as independent decisions.

Watch aperture edges, bonnet borders and wheel arches during deformation. Broad skinning weights can pull a window opening or rigid trim into a curved sheet. Improve the part's binding or segmentation before raising global triangle count.

## 8. Adapt the damage shader

Keep procedural coordinates in rest space so creases travel with the material. Protect glass, tires and rigid components with eligibility masks. Separate small geometric folds from fine normal detail and roughness changes.

Update the shader's `section_x()` positions to match the graph. Its arrays currently contain seven entries. The current signal is longitudinal section compression; it does not distinguish left-side from right-side strain. For offset damage, an eventual per-node/per-panel field would provide better localisation than multiplying up the existing wear value.

Keep the fold amplitude subordinate to the skeleton-driven shape. Turn the detail off and on during inspection. Shader-displaced geometry has no matching collision in this baseline, so avoid large displacements that imply new structural contact.

## 9. Validate matched cases

Run identical speed, contact, symmetry and material conditions when comparing changes. At minimum inspect:

1. Pristine car and gravity support.
2. Low-speed impact with limited permanent damage.
3. Higher-speed impact with front collapse and, when appropriate, cabin involvement.
4. Symmetry-free strong and weak versions under the same boundary conditions.
5. Mesh anchors, weight sums, replay pristine state and reset.

Check finite positions/velocities, total mass, wall/floor penetration and unexpected energy growth. These are sanity checks, not crash-test calibration. A credible real-car prediction requires independent geometry/material/impact data beyond this example.

## 10. Generalise only after the first adaptation works

These locations currently rely on Niva-specific topology:

| Location | Assumption to update |
|---|---|
| `build_structure.py` | Seven stations, four nodes per station, explicit engine/pillar/wheel connections |
| `structure_solver.gd` | Station indexing, shortening metrics and paired-node symmetry map |
| `wheel_physics.gd` / `wheel_assemblies` | Tire dimensions, inertia approximation, body-frame anchors and contact capsules; see [wheel configuration](WHEEL_PHYSICS.md) |
| `structural_skin.gd` | Seven frames, mesh names, engine region, floor height and refinement limits |
| `damage_surface.gdshader` | Seven section coordinates and fixed fold scale |
| `structural_probe.gd` | Speeds, camera framing and validation expectations |

If you change section/node counts, update all of these together. This is a complete example implementation, not a vehicle-independent graph compiler. Once a second car works, extract the common layout/schema with evidence from both vehicles.

## Share a fitted car between scenes

Create a profile alongside `vehicles/niva.json` with the fitted graph/model
paths and dynamics values. Set `vehicle_profile` on either scene. The two scenes
then use the same runtime, wheel implementation and skin. A profile does not
remove the topology/fitting requirements above. See [Shared runtime](SHARED_VEHICLE_RUNTIME.md).
