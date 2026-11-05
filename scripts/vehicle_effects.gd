extends RefCounted
## Explicit cosmetic glass/interior ownership. Never contributes vehicle mass.
var graph: WeakRef
var glass: RefCounted
var interior: RefCounted
var playback:=false
var visual_nodes: Array[Node3D]=[]

func setup(owner: RefCounted,settings: Dictionary={}) -> void:
 graph=weakref(owner)
 glass=load('res://scripts/vehicle_glass.gd').new()
 interior=load('res://scripts/vehicle_interior.gd').new()
 glass.setup(owner,settings.get('glass',{}))
 interior.setup(owner,settings.get('interior',{}))
 reset()

func reset() -> void:
 playback=false
 if glass!=null:glass.reset()
 if interior!=null:interior.reset()

func synchronize() -> void:
 if glass!=null:glass.synchronize()
 if interior!=null:interior.synchronize()

func resume_live() -> void:
 if playback:synchronize()
 playback=false

func step_live(dt: float) -> void:
 resume_live()
 glass.step_live(dt);interior.step_live(dt)
 step_debris(dt)

func step_debris(dt: float) -> void:
 glass.step_debris(dt);interior.step_debris(dt)

func capture() -> Dictionary:
 return {'version':1,'glass':glass.capture(),'interior':interior.capture()}

func begin_playback(initial: Dictionary) -> void:
 playback=true
 glass.begin_playback(initial.get('glass',{}))
 interior.begin_playback(initial.get('interior',{}))

func restore_interpolated(a: Dictionary,b: Dictionary,alpha: float) -> void:
 if not playback:begin_playback(a)
 glass.restore_interpolated(a.get('glass',{}),b.get('glass',{}),alpha)
 interior.restore_interpolated(a.get('interior',{}),b.get('interior',{}),alpha)

func bind_visual(skin_view: Node3D,model_root: Node3D) -> void:
 for controller in [glass,interior]:
  var visual: Node3D=controller.create_visual(skin_view,model_root)
  if visual!=null:skin_view.add_child(visual);visual_nodes.append(visual)
