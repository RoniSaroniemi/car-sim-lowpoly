extends SceneTree
const Vehicle=preload('res://scripts/driving_vehicle.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const State=preload('res://scripts/panel_snapshot.gd')
const Player=preload('res://scripts/baked_crash_player.gd')
const Author=preload('res://scripts/conditioned_crash_authoring.gd')
const States=preload('res://scripts/conditioned_crash_transitions.gd')
func _initialize() -> void:
 var v:=Vehicle.new();v.setup();v.solver.barrier_enabled=false
 v.set_panel_open('door_right',65)
 for i in 360:v.step(1.0/120)
 var origin:=Vector3(23,4,-12);var rotation:=Basis.from_euler(Vector3(.3,.7,-.2))
 var a: Dictionary=v.solver.capture();var local: Dictionary=Clip.local_frame(v.solver,Vector3(-9,0,0))
 var clip: Dictionary={'metadata':{'id':'panel_roundtrip','sample_hz':120,'duration_s':1.0/120,'heading_deg':0,'speed_kmh':60},'frames':[local,local.duplicate(true)]}
 Clip.save(clip,'user://panel_roundtrip.crashclip',false);clip=Clip.read('user://panel_roundtrip.crashclip')
 assert(clip.metadata.panels_schema==1)
 var frame_bytes: PackedByteArray=var_to_bytes(clip.frames)
 var calls: int=v.solver.step_count;var cages: int=v.solver.panels.active_steps
 Clip.apply(v.solver,clip,1.0/240,origin,rotation)
 var p: Dictionary=v.panel_state('door_right');var source: Dictionary=local.panels.panels[1]
 for i in 10:
  assert(p.points[i].distance_to(rotation*source.points[i]+origin)<.0001)
  assert(p.velocity[i].distance_to(rotation*source.velocity[i])<.0001)
 assert(p.reduced_data.center.distance_to(rotation*source.reduced_data.center+origin)<.0001)
 assert(absf(p.reduced_data.rotation.dot(rotation.get_rotation_quaternion()*source.reduced_data.rotation))>.99999)
 assert(p.reduced_data.offsets==source.reduced_data.offsets)
 assert(absf(v.solver.owned_mass_kg()-1210)<.01)
 assert(v.solver.step_count==calls and v.solver.panels.active_steps==cages)
 assert(var_to_bytes(clip.frames)==frame_bytes)
 var other:=Vehicle.new();other.setup();other.solver.restore(a)
 var second:=Vehicle.new();second.setup();second.solver.restore(a)
 var before_other: PackedVector3Array=other.panel_state('door_right').points.duplicate()
 second.panel_state('door_right').points[0]+=Vector3(1,0,0)
 assert(other.panel_state('door_right').points==before_other)
 # Seeking is exact and doesn't heal manufactured prior damage.
 p.anchors[0].broken=true;p.angular_mount.plastic_rad=.12
 var prior: Dictionary=v.solver.panels.capture()
 State.retain_failures(v.solver.panels,prior);assert(p.anchors[0].broken)
 Clip.apply(v.solver,clip,0,origin,rotation);assert(not p.anchors[0].broken)
 # Explicit repair/seek restores recorded state. Runtime sequence floor preserves failures.
 State.retain_failures(v.solver.panels,prior);assert(p.anchors[0].broken)
 # Detached panel world ownership survives external staging.
 p.detached=true;p.active=true;p.reduced=true
 var detached: PackedVector3Array=p.points.duplicate();var detached_velocity: PackedVector3Array=p.velocity.duplicate()
 v.solver.panels.playback=false
 Author.prepare(v.solver,{'angle':-20,'speed':60},40)
 assert(p.points==detached and p.velocity==detached_velocity)
 # Ownership unit fixture deliberately offers an incompatible closed-component
 # clip directly to the player. The public selector rejects such a pairing;
 # even if called directly, it cannot reattach/teleport an existing free piece.
 for anchor in p.anchors:anchor.broken=true
 for seat in p.closing_supports:seat.broken=true
 p.closing_engaged=false;p.latched=false
 v.solver.effects.glass.hit_window('door_right',1.3)
 var glass_before: Dictionary=v.solver.effects.glass.capture().panes.door_right
 var free_before: PackedVector3Array=p.points.duplicate()
 var player:=Player.new();player.attach_live(v,[clip],{}, {'index':0})
 assert(p.detached and p.active)
 assert(v.solver.effects.glass.capture().panes.door_right.mask==glass_before.mask)
 for k in 10:assert(p.points[k].distance_to(free_before[k])<.0001)
 player.advance(1.0/240)
 assert(p.detached and absf(v.solver.owned_mass_kg()-1210)<.001)
 assert(v.solver.effects.glass.capture().panes.door_right.mask==glass_before.mask)
 assert(v.solver.step_count==calls and v.solver.panels.active_steps==cages)
 # Runtime strict path remains cheap with an open panel, no banks required.
 v.reset();v.solver.barrier_enabled=false;v.baked_enabled=true;v.set_panel_open('door_right',55)
 for i in 240:v.step(1.0/120)
 assert(v.full_steps==0 and v.solver.panels.active_steps==0)
 assert(v.solver.effects.glass.membrane_solve_steps==0)
 print('PANEL_SNAPSHOTS_PASS registered pose/velocity/rigid fields, disk seek, owned mass, free-piece staging, strict zero-solves')
 quit()
