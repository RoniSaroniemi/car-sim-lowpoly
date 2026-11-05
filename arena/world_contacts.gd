extends RefCounted
## Finite annular retaining wall. Static signed point distances, no added mass.
const RADIUS=76.0
const HEIGHT=2.45
const THICKNESS=2.0
const CRASH_MIN=Vector3(40,0,-8)
const CRASH_MAX=Vector3(41,3,8)
var contact_samples:=0
func nearby(p: Vector3,radius: float) -> bool:
 return Vector2(p.x,p.z).length_squared()>=pow(maxf(0,RADIUS-radius),2) and p.y<=HEIGHT+radius and p.y>=-radius
func sample(p: Vector3) -> Dictionary:
 var radial:=Vector3(p.x,0,p.z);var r:=radial.length()
 if r<.01:return {'distance':INF,'normal':Vector3.ZERO,'source':'none'}
 var q:=Vector2(absf(r-RADIUS-THICKNESS*.5)-THICKNESS*.5,absf(p.y-HEIGHT*.5)-HEIGHT*.5)
 var outside:=q.max(Vector2.ZERO)
 var distance: float=outside.length()+minf(maxf(q.x,q.y),0)
 var radial_sign: float=-1.0 if r<RADIUS+THICKNESS*.5 else 1.0
 var vertical_sign: float=-1.0 if p.y<HEIGHT*.5 else 1.0
 var n:=radial/r*radial_sign
 if outside.length_squared()>.00000001:n=(radial/r*radial_sign*outside.x+Vector3.UP*vertical_sign*outside.y).normalized()
 elif q.y>q.x:n=Vector3.UP*vertical_sign
 if distance<.5:contact_samples+=1
 return {'distance':distance,'normal':n,'source':'arena_ring'}
func forecast(center: Vector3,extent: Vector3,linear: Vector3,_angular: Vector3,horizon: float,padding: float) -> Dictionary:
 var clear: Dictionary={'risk':false,'reason':'clear','time_to_contact_s':-1.0,'clearance_m':INF}
 var start:=Vector2(center.x,center.z);var end:=start+Vector2(linear.x,linear.z)*horizon
 var bound: float=Vector2(extent.x,extent.z).length()+padding
 if maxf(start.length(),end.length())+bound<RADIUS:return clear
 if minf(center.y,center.y+linear.y*horizon)-extent.y>HEIGHT+padding:return clear
 var closing: float=Vector2(linear.x,linear.z).dot(start.normalized())
 var clearance: float=RADIUS-start.length()-bound
 return {'risk':true,'reason':'forecast_arena_ring','time_to_contact_s':clampf(clearance/maxf(.001,closing),0,horizon),'clearance_m':clearance}
