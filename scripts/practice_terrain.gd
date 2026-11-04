extends RefCounted
## Smooth heightfield humps, used for BOTH rendered ramps and contact queries.
var ramps: Array[Dictionary]=[
 {'name':'LOW JUMP','start':-10.0,'length':16.0,'height':.9,'z':-22.0,'width':10.0},
 {'name':'HIGH JUMP','start':8.0,'length':20.0,'height':1.7,'z':22.0,'width':10.0}
]

func sample(p: Vector3) -> Vector4:
 var height:=0.0
 var dx:=0.0
 var dz:=0.0
 for ramp in ramps:
  var u: float=(p.x-float(ramp.start))/float(ramp.length)
  var side: float=absf(p.z-float(ramp.z))
  var half: float=float(ramp.width)*.5
  if u<0 or u>1 or side>=half:continue
  var blend:=1.0
  var blend_dz:=0.0
  var feather:=2.0
  if side>half-feather:
   var t: float=(side-half+feather)/feather
   blend=.5+.5*cos(PI*t)
   blend_dz=-.5*PI/feather*sin(PI*t)*signf(p.z-float(ramp.z))
  var longitudinal: float=sin(PI*u)*sin(PI*u)
  height+=float(ramp.height)*longitudinal*blend
  dx+=float(ramp.height)*PI/float(ramp.length)*sin(TAU*u)*blend
  dz+=float(ramp.height)*longitudinal*blend_dz
 var n:=Vector3(-dx,1,-dz).normalized()
 return Vector4(n.x,n.y,n.z,height)

func mesh(ramp: Dictionary) -> ArrayMesh:
 var vertices:=PackedVector3Array()
 var normals:=PackedVector3Array()
 var indices:=PackedInt32Array()
 var nx:=80
 var nz:=24
 for x in nx+1:
  for z in nz+1:
   var p:=Vector3(float(ramp.start)+float(ramp.length)*x/nx,0,float(ramp.z)-float(ramp.width)*.5+float(ramp.width)*z/nz)
   var surface: Vector4=sample(p)
   p.y=surface.w
   vertices.append(p)
   normals.append(Vector3(surface.x,surface.y,surface.z))
 for x in nx:
  for z in nz:
   var a: int=x*(nz+1)+z
   var b: int=(x+1)*(nz+1)+z
   indices.append_array(PackedInt32Array([a,b,a+1,b,b+1,a+1]))
 var arrays: Array=[]
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=vertices
 arrays[Mesh.ARRAY_NORMAL]=normals
 arrays[Mesh.ARRAY_INDEX]=indices
 var result:=ArrayMesh.new()
 result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 return result
