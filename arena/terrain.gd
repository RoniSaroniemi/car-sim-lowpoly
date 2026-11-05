extends RefCounted
## This descriptor drives both the visible mesh and the car's analytic floor.
const RADIUS=76.0
var features: Array[Dictionary]=[
 {'id':'sand','name':'SAND TABLETOP','start':-38.0,'length':27.0,'height':2.0,'z':-25.0,'width':14.0,'kind':0},
 {'id':'concrete','name':'CONCRETE ROLL','start':-30.0,'length':24.0,'height':2.5,'z':25.0,'width':13.0,'kind':2},
 {'id':'wood','name':'TIMBER JUMP','start':8.0,'length':22.0,'height':2.4,'z':-18.0,'width':11.0,'kind':3},
 {'id':'pipe','name':'CONCRETE HALFPIPE','start':23.0,'length':35.0,'height':5.0,'z':28.0,'width':19.0,'kind':2,'pipe':true},
 {'id':'pair','name':'42° / 24° PAIRED RAMPS','start':-10.0,'length':24.0,'height':3.8,'z':-50.0,'width':10.0,'kind':2,'pair':true}
]
var queries:=0
func feature_height(f: Dictionary,x: float,z: float) -> float:
 var u: float=(x-f.start)/f.length
 var side: float=absf(z-f.z)/(f.width*.5)
 if u<=0 or u>=1 or side>=1:return 0
 if f.get('pair',false):return _pair_triangle(f,x,z)
 var side_fade:=1.0
 if side>.68:side_fade=.5+.5*cos(PI*(side-.68)/.32)
 var longitudinal:=pow(sin(PI*u),2)
 if f.get('pipe',false):
  # Two rounded quarter-pipes, with sloping filled backs; no hidden overhangs.
  var q: float=(u-.5)*2
  var a: float=absf(q)
  if a<.70:longitudinal=pow(a/.70,2)
  else:longitudinal=.5+.5*cos(PI*(a-.70)/.30)
 return f.height*longitudinal*side_fade
func _paired_vertex(f: Dictionary,x: float,z: float) -> float:
 var distance: float=clampf(x-f.start,0,f.length)
 var grade: float=lerpf(tan(deg_to_rad(42.0)),tan(deg_to_rad(24.0)),smoothstep(-.62,.62,z-f.z))
 var end_straight: float=f.height/grade
 var amount:=0.0
 if distance<2:amount=grade*distance*distance/4
 elif distance<end_straight:amount=grade*(distance-1)
 elif distance<end_straight+2:
  var t: float=distance-end_straight;amount=grade*(end_straight-1+t-t*t/4)
 elif distance<12:amount=f.height
 else:amount=f.height*(.5+.5*cos(PI*(distance-12)/12))
 var edge: float=absf(z-f.z)/(f.width*.5)
 var feather: float=1.0 if edge<.70 else .5+.5*cos(PI*(edge-.70)/.30)
 return amount*maxf(0,feather)
func _pair_triangle(f: Dictionary,x: float,z: float) -> float:
 # The exact same regular triangles are used for collision and rendering.
 var u: float=clampf((x-f.start)/f.length*120,0,119.999999)
 var v: float=clampf((z-f.z+f.width*.5)/f.width*200,0,199.999999)
 var ix:=floori(u);var iz:=floori(v);var tx: float=u-ix;var tz: float=v-iz
 var x0: float=f.start+f.length*ix/120;var z0: float=f.z-f.width*.5+f.width*iz/200
 var dx: float=f.length/120;var dz: float=f.width/200
 var a:=_paired_vertex(f,x0,z0);var b:=_paired_vertex(f,x0+dx,z0);var c:=_paired_vertex(f,x0,z0+dz)
 if tx+tz<=1:return a+(b-a)*tx+(c-a)*tz
 var d:=_paired_vertex(f,x0+dx,z0+dz)
 return d+(c-d)*(1-tx)+(b-d)*(1-tz)
func height(x: float,z: float) -> float:
 var h:=0.0
 for f in features:
  if x>f.start and x<f.start+f.length and absf(z-f.z)<f.width*.5:h=maxf(h,feature_height(f,x,z))
 return h
func sample(p: Vector3) -> Vector4:
 queries+=1
 var nearby:=false
 for f in features:
  if p.x>f.start and p.x<f.start+f.length and absf(p.z-f.z)<f.width*.5:nearby=true;break
 if not nearby:return Vector4(0,1,0,0)
 var h: float=height(p.x,p.z)
 var e:=.02
 var n:=Vector3(-(height(p.x+e,p.z)-height(p.x-e,p.z))/(2*e),1,-(height(p.x,p.z+e)-height(p.x,p.z-e))/(2*e)).normalized()
 return Vector4(n.x,n.y,n.z,h)
func feature_mesh(f: Dictionary,step: float=.35) -> ArrayMesh:
 var nx: int=ceili(f.length/step);var nz: int=ceili(f.width/step)
 if f.get('pair',false):nx=120;nz=200
 var v:=PackedVector3Array();var n:=PackedVector3Array();var uv:=PackedVector2Array();var c:=PackedColorArray();var ix:=PackedInt32Array()
 for x in nx+1:
  for z in nz+1:
   var p:=Vector3(f.start+f.length*x/nx,0,f.z-f.width*.5+f.width*z/nz)
   var surface:=sample(p);p.y=surface.w+.004
   v.append(p);n.append(Vector3(surface.x,surface.y,surface.z));uv.append(Vector2(p.x,p.z))
   var edge: float=1-smoothstep(.0,.7,p.y)
   c.append(Color(edge*.30,1,0,1))
 for x in nx:
  for z in nz:
   var a: int=x*(nz+1)+z;var b: int=(x+1)*(nz+1)+z
   ix.append_array(PackedInt32Array([a,b,a+1,b,b+1,a+1]))
 var a: Array=[];a.resize(Mesh.ARRAY_MAX)
 a[Mesh.ARRAY_VERTEX]=v;a[Mesh.ARRAY_NORMAL]=n;a[Mesh.ARRAY_TEX_UV]=uv;a[Mesh.ARRAY_COLOR]=c;a[Mesh.ARRAY_INDEX]=ix
 var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a);return mesh
