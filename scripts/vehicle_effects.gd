extends RefCounted
## Explicit cosmetic glass/interior ownership. Never contributes vehicle mass.
var graph: WeakRef
var glass: RefCounted
var interior: RefCounted
var surface: RefCounted
var playback:=false
var visual_nodes: Array[Node3D]=[]

func setup(owner: RefCounted,settings: Dictionary={}) -> void:
 surface=load('res://scripts/vehicle_surface.gd').new();surface.setup(owner,settings.get('surface',{}))
 graph=weakref(owner)
 glass=load('res://scripts/vehicle_glass.gd').new()
 interior=load('res://scripts/vehicle_interior.gd').new()
 glass.setup(owner,settings.get('glass',{}))
 interior.setup(owner,settings.get('interior',{}))
 reset()

func reset() -> void:
 playback=false
 if surface!=null:surface.reset()
 if glass!=null:glass.reset()
 if interior!=null:interior.reset()

func synchronize() -> void:
 var owner: RefCounted=graph.get_ref()
 if owner!=null and owner.panels_runtime_enabled:owner.panels.synchronize_inactive()
 if glass!=null:glass.synchronize()
 if interior!=null:interior.synchronize()

func resume_live() -> void:
 if playback:
  synchronize();surface.resume_live()
 playback=false

func step_live(dt: float) -> void:
 resume_live()
 glass.step_live(dt);interior.step_live(dt);surface.step_live(dt)
 step_debris(dt)

func step_debris(dt: float) -> void:
 glass.step_debris(dt);interior.step_debris(dt)

func capture() -> Dictionary:
 return {'version':1,'glass':glass.capture(),'interior':interior.capture(),'surface':surface.capture()}

func begin_playback(initial: Dictionary) -> void:
 playback=true
 if initial.has('surface'):surface.restore(initial.surface)
 glass.begin_playback(initial.get('glass',{}))
 interior.begin_playback(initial.get('interior',{}))

func restore_interpolated(a: Dictionary,b: Dictionary,alpha: float) -> void:
 if not playback:begin_playback(a)
 glass.restore_interpolated(a.get('glass',{}),b.get('glass',{}),alpha)
 interior.restore_interpolated(a.get('interior',{}),b.get('interior',{}),alpha)
 if a.has('surface'):surface.restore(a.surface)

func bind_visual(skin_view: Node3D,model_root: Node3D) -> void:
 for controller in [glass,interior]:
  var visual: Node3D=controller.create_visual(skin_view,model_root)
  if visual!=null:skin_view.add_child(visual);visual_nodes.append(visual)
