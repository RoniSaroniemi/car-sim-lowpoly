extends VBoxContainer
## Reusable ordinary panel controls for either shared driving scene.
var vehicle: RefCounted
var labels: Dictionary={}
func setup(owner: RefCounted) -> void:
 vehicle=owner
 var title:=Label.new();title.text='Doors and body panels';add_child(title)
 for item in [['door_left','Left door',70],['door_right','Right door',70],['bonnet','Bonnet',65],['tailgate','Rear hatch',85]]:
  var row:=HBoxContainer.new();add_child(row)
  var label:=Label.new();label.text=item[1];label.custom_minimum_size.x=100;row.add_child(label)
  for command in [['Open',item[2]],['Close',0]]:
   var button:=Button.new();button.text=command[0];button.pressed.connect(_command.bind(item[0],command[1]));row.add_child(button)
  var state:=Label.new();state.add_theme_font_size_override('font_size',11);row.add_child(state);labels[item[0]]=state
func _command(id: String,angle: float) -> void:
 if not vehicle.set_panel_open(id,angle):labels[id].text='Unavailable until repaired' if vehicle.mode!='BAKED' else 'Crash replay in progress'
func _process(_dt: float) -> void:
 if vehicle==null:return
 for id in labels:
  var p: Dictionary=vehicle.panel_state(id)
  if p.is_empty():continue
  labels[id].text='Detached' if p.detached else 'Damaged' if p.anchors.any(func(a):return a.broken) else 'Closed' if p.latched else '%.0f°'%rad_to_deg(p.angle)
