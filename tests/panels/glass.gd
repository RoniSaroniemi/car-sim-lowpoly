extends SceneTree
const Vehicle=preload('res://scripts/driving_vehicle.gd')
const Attachment=preload('res://scripts/car_attachment.gd')
func _initialize() -> void:
 var v:=Vehicle.new();v.setup();v.baked_enabled=false;v.solver.barrier_enabled=false
 v.set_panel_open('door_right',65)
 for i in 360:v.step(1.0/120)
 var glass: RefCounted=v.solver.effects.glass;var pane: Dictionary=glass.panes.door_right
 assert(pane.stage==0)
 var frames: Array=Attachment.rotations(v.solver)
 var current: PackedVector3Array=glass._node_world(pane,frames)
 var frame: Transform3D=glass._frame(pane,frames)
 var rigid_error:=0.
 for i in current.size():rigid_error=maxf(rigid_error,(frame.affine_inverse()*current[i]).distance_to(pane.rest_frame.affine_inverse()*pane.node_rest[i]))
 assert(rigid_error<.002)
 # Glass fragments inherit the open moving panel, rather than body AABB motion.
 var p: Dictionary=v.panel_state('door_right');p.reduced_data.linear=Vector3(7,0,-3);p.reduced_data.omega=Vector3(0,2,0);v.reduced_panels._publish(p);v.solver.panels.pose_revision+=1
 var uv:=Vector2(.3,.7);var binding: Dictionary=v.solver.panels.point_binding(p.id,glass._rest_at(pane,uv))
 var point_: Vector3=v.solver.panels.mapped(binding)
 assert(glass._point_velocity(pane,uv).distance_to(p.reduced_data.linear+p.reduced_data.omega.cross(point_-p.reduced_data.center))<.0001)
 glass.synchronize();glass.hit_window('door_right',1.3)
 assert(glass.debris.size()>0)
 var snapshot: Dictionary=glass.capture();var count: int=glass.debris.size()
 glass.begin_playback(snapshot);glass.restore_interpolated(snapshot,snapshot,0);assert(glass.debris.size()==count)
 assert(glass.membrane_solve_steps==0)
 print('PANEL_GLASS_PASS rigid_error=',rigid_error,' moving panel velocity, temper event deduplication')
 quit()
