extends RefCounted
## Contact-location directions in the pristine CAR frame: +X front, +Y roof, -Z left.
static func directions() -> Array:
 var cases: Array=[]
 for elevation in [45,-45]:
  for azimuth in range(0,360,45):
   var a:=deg_to_rad(float(azimuth));var e:=deg_to_rad(float(elevation))
   cases.append(_descriptor(('upper' if elevation>0 else 'lower')+'_az%03d'%azimuth,Vector3(cos(e)*cos(a),sin(e),-cos(e)*sin(a)),float(azimuth),float(elevation)))
 cases.append(_descriptor('top',Vector3.UP,0,90))
 cases.append(_descriptor('underside',Vector3.DOWN,0,-90))
 return cases
static func _descriptor(key: String,direction: Vector3,azimuth: float,elevation: float) -> Dictionary:
 var axis:=direction.cross(Vector3.DOWN)
 var rotation:=Basis.IDENTITY
 if axis.length_squared()>1e-12:rotation=Basis(axis.normalized(),acos(clampf(direction.dot(Vector3.DOWN),-1,1)))
 elif direction.dot(Vector3.DOWN)<0:rotation=Basis(Vector3.RIGHT,PI)
 var q:=rotation.get_rotation_quaternion()
 return {'version':1,'key':key,'family':'multiaxis_floor','azimuth_deg':azimuth,'elevation_deg':elevation,'incoming_car_direction':[direction.x,direction.y,direction.z],'reaction_car_normal':[-direction.x,-direction.y,-direction.z],'rotation_xyzw':[q.x,q.y,q.z,q.w],'world_velocity_direction':[0,-1,0],'world_normal':[0,1,0],'clearance_m':1.0,'contact_policy':'earliest_body_sphere_or_oriented_tire_or_panel_cage_floor_contact','closed_latched_initial_panels':true}
static func find(key: String) -> Dictionary:
 for descriptor in directions():
  if descriptor.key==key:return descriptor
 return {}
static func specifications(speeds: Array=[60,120]) -> Array:
 var result: Array=[]
 for descriptor in directions():
  for speed in speeds:
   var spec: Dictionary=descriptor.duplicate(true)
   spec['speed_kmh']=float(speed);spec['id']=spec.key+'_'+str(roundi(float(speed)));result.append(spec)
 return result
