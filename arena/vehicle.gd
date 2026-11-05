extends 'res://scripts/driving_vehicle.gd'
## Arena-only static boundary adapter; normal car dynamics remain shared.
const Terrain=preload('res://arena/terrain.gd')
var boundary_contacts:=0
func _rigid_body_contacts(dt: float) -> void:
 super._rigid_body_contacts(dt)
 # The seat ring begins behind this visible retaining wall. No seat traversal.
 if Vector2(compact.center.x,compact.center.z).length_squared()>pow(Terrain.RADIUS-4,2):
  for iteration in 3:
   for index in compact.indices:
    var p: Vector3=compact.point(index)
    if p.y>2.4:continue
    var horizontal:=Vector3(p.x,0,p.z)
    var radius: float=horizontal.length()
    var depth: float=radius+solver.radii[index]-Terrain.RADIUS
    if depth>0 and radius>.1:
     _rigid_contact(index,-horizontal/radius,depth,dt);boundary_contacts+=1
 compact.flush()
 for w in solver.wheels.wheels:
  var p: Vector3=solver.points[w.node]
  if p.y>2.5:continue
  var radial:=Vector3(p.x,0,p.z);var r: float=radial.length()
  if r+w.radius>Terrain.RADIUS and r>.1:
   var outward: Vector3=radial/r
   solver.points[w.node]-=outward*(r+w.radius-Terrain.RADIUS)
   var speed: float=solver.velocities[w.node].dot(outward)
   if speed>0:solver.velocities[w.node]-=outward*speed
   boundary_contacts+=1
func _contact_event(_horizon: float) -> Dictionary:
 # The circular arena isn't the recorded full-width planar benchmark wall.
 # Keep cheap rigid contact, never misapply a pristine wall bake at an arch.
 return {}
