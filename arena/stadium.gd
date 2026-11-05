extends Node3D
const Terrain=preload('res://arena/terrain.gd')
var terrain: RefCounted
var materials: Array[ShaderMaterial]=[]
var mesh_triangles:=0
var instances:=0
var batches:=0
var load_ms:=0.0
var mesh_array_bytes:=0
var measured_meshes: Dictionary={}
var sun: DirectionalLight3D
var environment: Environment
func build(t: RefCounted) -> void:
 var began:=Time.get_ticks_usec();terrain=t
 for entry in [[0,'#baa071'],[1,'#b8a382'],[2,'#a9aaa1'],[3,'#94683b']]:
  var mat:=ShaderMaterial.new();mat.shader=load('res://arena/material.gdshader');mat.set_shader_parameter('kind',entry[0]);mat.set_shader_parameter('base_color',Color(entry[1]).srgb_to_linear());materials.append(mat)
 _lighting()
 var ground:=PlaneMesh.new();ground.size=Vector2(2000,2000);ground.subdivide_width=4;ground.subdivide_depth=4
 var ground_arrays: Array=ground.surface_get_arrays(0)
 var ground_colors:=PackedColorArray();ground_colors.resize(ground_arrays[Mesh.ARRAY_VERTEX].size());ground_colors.fill(Color(.02,1,0,1));ground_arrays[Mesh.ARRAY_COLOR]=ground_colors
 var ground_mesh:=ArrayMesh.new();ground_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,ground_arrays)
 _mesh(ground_mesh,materials[0])
 _mesh(_ring(76,78,0,2.2,144),materials[1])
 _mesh(_ring(75.9,78.3,2.2,2.45,144),materials[2])
 _mesh(_ring(78,102,0,.9,144),materials[1])
 for row in 12:
  _mesh(_ring(78.3+row*1.75,80.1+row*1.75,.9+row*.64,1.55+row*.64,144),materials[1])
 var chair:=_boxes([[Vector3(1.10,.28,.70),Vector3(0,.14,0)],[Vector3(1.10,.52,.15),Vector3(0,.50,.29)]])
 var seat_transforms: Array[Transform3D]=[]
 for row in 12:
  var radius:=79.05+row*1.75;var count:=floori(TAU*radius/1.40)
  for i in count:
   var angle:=TAU*i/count
   # Four clear radial aisles divide the seating into repeated banks.
   if absf(sin(angle*2))<.075:continue
   seat_transforms.append(Transform3D(Basis(Vector3.UP,-angle+PI*.5),Vector3(cos(angle)*radius,1.55+row*.64,sin(angle)*radius)))
 # Eight culling sectors; seats share one cached mesh/material.
 for sector in 8:
  var subset: Array[Transform3D]=[]
  for tr in seat_transforms:
   var angle:=fposmod(atan2(tr.origin.z,tr.origin.x),TAU)
   if floori(angle/TAU*8)==sector:subset.append(tr)
  _instances(chair,materials[1],subset)
 var arch_mesh:=_arch(4.6,5.8,7.6,2.7,14)
 var arches: Array[Transform3D]=[];var piers: Array[Transform3D]=[]
 for i in 48:
  var angle:=TAU*i/48
  arches.append(Transform3D(Basis(Vector3.UP,-angle+PI*.5),Vector3(cos(angle)*102,0,sin(angle)*102)))
  angle+=PI/48
  piers.append(Transform3D(Basis(Vector3.UP,-angle+PI*.5),Vector3(cos(angle)*102,0,sin(angle)*102)))
 _instances(arch_mesh,materials[1],arches)
 _instances(_boxes([[Vector3(1.7,8.3,3.4),Vector3(0,4.15,0)],[Vector3(2.3,.5,3.9),Vector3(0,.25,0)],[Vector3(2.1,.45,3.8),Vector3(0,8.1,0)]]),materials[1],piers)
 _mesh(_ring(99.5,104.5,13.0,13.65,144),materials[1])
 _mesh(_ring(100.1,104.0,13.65,14.15,144),materials[2])
 for f in terrain.features:
  _mesh(terrain.feature_mesh(f),materials[int(f.kind)])
  if f.kind==3:_wood_details(f)
  if f.get('pair',false):_pair_markers(f)
 _markers()
 load_ms=(Time.get_ticks_usec()-began)/1000.0
func _lighting() -> void:
 var world:=WorldEnvironment.new();environment=Environment.new()
 var sky:=Sky.new();var sky_mat:=ProceduralSkyMaterial.new()
 sky_mat.sky_top_color=Color('#5584ab');sky_mat.sky_horizon_color=Color('#d8ded4');sky_mat.ground_bottom_color=Color('#786348');sky_mat.ground_horizon_color=Color('#c9b890');sky_mat.sky_energy_multiplier=.85
 sky.sky_material=sky_mat;environment.background_mode=Environment.BG_SKY;environment.sky=sky
 environment.ambient_light_source=Environment.AMBIENT_SOURCE_SKY;environment.ambient_light_energy=.48
 environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY;environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
 world.environment=environment;add_child(world)
 sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-46,-28,0);sun.light_color=Color('#fff1d2');sun.light_energy=1.0
 sun.shadow_enabled=true;sun.directional_shadow_max_distance=160;sun.shadow_bias=.045;sun.shadow_normal_bias=.7
 sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS;sun.directional_shadow_blend_splits=true;sun.light_angular_distance=.15
 add_child(sun)
func _mesh(mesh: Mesh,mat: Material) -> MeshInstance3D:
 var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=mat;add_child(node)
 _measure(mesh)
 mesh_triangles+=mesh.get_faces().size()/3
 batches+=1;return node
func _instances(mesh: Mesh,mat: Material,transforms: Array[Transform3D]) -> void:
 var node:=MultiMeshInstance3D.new();var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=transforms.size()
 for i in transforms.size():mm.set_instance_transform(i,transforms[i])
 node.multimesh=mm;node.material_override=mat;add_child(node);instances+=transforms.size();batches+=1
 _measure(mesh)
 mesh_triangles+=transforms.size()*mesh.surface_get_array_index_len(0)/3
func _measure(mesh: Mesh) -> void:
 if measured_meshes.has(mesh.get_instance_id()):return
 measured_meshes[mesh.get_instance_id()]=true
 for surface in mesh.get_surface_count():mesh_array_bytes+=var_to_bytes(mesh.surface_get_arrays(surface)).size()
func _arrays() -> Array:
 var a: Array=[];a.resize(Mesh.ARRAY_MAX);a[Mesh.ARRAY_VERTEX]=PackedVector3Array();a[Mesh.ARRAY_NORMAL]=PackedVector3Array();a[Mesh.ARRAY_TEX_UV]=PackedVector2Array();a[Mesh.ARRAY_COLOR]=PackedColorArray();a[Mesh.ARRAY_INDEX]=PackedInt32Array();return a
func _quad(a: Array,p: Vector3,q: Vector3,r: Vector3,s: Vector3,grime: float=.0,occlusion: float=1) -> void:
 var count: int=a[Mesh.ARRAY_VERTEX].size();var n: Vector3=(q-p).cross(r-p).normalized()
 for v in [p,q,r,s]:a[Mesh.ARRAY_VERTEX].append(v);a[Mesh.ARRAY_NORMAL].append(n);a[Mesh.ARRAY_TEX_UV].append(Vector2(v.x,v.z));a[Mesh.ARRAY_COLOR].append(Color(grime,occlusion,0,1))
 a[Mesh.ARRAY_INDEX].append_array(PackedInt32Array([count,count+2,count+1,count,count+3,count+2]))
func _finish(a: Array) -> ArrayMesh:
 var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a);return mesh
func _ring(inner: float,outer: float,bottom: float,top: float,count: int) -> ArrayMesh:
 var a:=_arrays()
 for i in count:
  var d:=Vector3(cos(TAU*i/count),0,sin(TAU*i/count));var e:=Vector3(cos(TAU*(i+1)/count),0,sin(TAU*(i+1)/count))
  _quad(a,d*inner+Vector3.UP*top,e*inner+Vector3.UP*top,e*outer+Vector3.UP*top,d*outer+Vector3.UP*top,.08,1)
  _quad(a,d*inner+Vector3.UP*bottom,e*inner+Vector3.UP*bottom,e*inner+Vector3.UP*top,d*inner+Vector3.UP*top,.4,.82)
  _quad(a,e*outer+Vector3.UP*bottom,d*outer+Vector3.UP*bottom,d*outer+Vector3.UP*top,e*outer+Vector3.UP*top,.24,.90)
 return _finish(a)
func _boxes(specs: Array) -> ArrayMesh:
 var a:=_arrays()
 for spec in specs:
  var box:=BoxMesh.new();box.size=spec[0];var b: Array=box.surface_get_arrays(0);var start: int=a[Mesh.ARRAY_VERTEX].size()
  for i in b[Mesh.ARRAY_VERTEX].size():
   var p: Vector3=b[Mesh.ARRAY_VERTEX][i]+spec[1]
   a[Mesh.ARRAY_VERTEX].append(p);a[Mesh.ARRAY_NORMAL].append(b[Mesh.ARRAY_NORMAL][i]);a[Mesh.ARRAY_TEX_UV].append(b[Mesh.ARRAY_TEX_UV][i])
   a[Mesh.ARRAY_COLOR].append(Color(.35*(1-smoothstep(-spec[0].y*.5,spec[0].y*.3,b[Mesh.ARRAY_VERTEX][i].y)),.85+.15*maxf(0,b[Mesh.ARRAY_NORMAL][i].y),0,1))
  for index in b[Mesh.ARRAY_INDEX]:a[Mesh.ARRAY_INDEX].append(start+index)
 return _finish(a)
func _arch(inner: float,outer: float,base: float,depth: float,segments: int) -> ArrayMesh:
 var a:=_arrays()
 for i in segments:
  var t:=PI*i/segments;var u:=PI*(i+1)/segments
  var p:=Vector3(cos(t)*inner,base+sin(t)*inner,0);var q:=Vector3(cos(u)*inner,base+sin(u)*inner,0)
  var r:=Vector3(cos(t)*outer,base+sin(t)*outer,0);var s:=Vector3(cos(u)*outer,base+sin(u)*outer,0)
  var z:=Vector3.BACK*depth*.5
  _quad(a,p-z,q-z,s-z,r-z,.12);_quad(a,q+z,p+z,r+z,s+z,.12)
  _quad(a,q-z,p-z,p+z,q+z,.46,.73);_quad(a,r-z,s-z,s+z,r+z,.05)
 return _finish(a)
func _wood_details(f: Dictionary) -> void:
 var transforms: Array[Transform3D]=[]
 var rail:=_boxes([[Vector3(.10,.14,.12),Vector3.ZERO]])
 # Board end-grain ribs rise only 8 mm above the common collision deck.
 var n:=floori(f.length/.55)
 var boards: Array[Transform3D]=[]
 var plank:=_boxes([[Vector3(.045,.016,f.width*.63),Vector3.ZERO]])
 for i in range(1,n):
  var x: float=f.start+f.length*i/n;var surface: Vector4=terrain.sample(Vector3(x,0,f.z))
  var basis:=Basis(Vector3.BACK,atan2(-surface.x,surface.y))
  boards.append(Transform3D(basis,Vector3(x,surface.w+.012,f.z)))
 _instances(plank,materials[3],boards)
 for side in [-1,1]:
  for x in range(2,int(f.length)-1,3):
   var px: float=f.start+x;var z: float=f.z+side*f.width*.30;var y: float=terrain.height(px,z)
   if y<.2:continue
   var post:=_mesh(_boxes([[Vector3(.20,y,.20),Vector3(0,y*.5,0)]]),materials[3]);post.position=Vector3(px,0,z)
func _markers() -> void:
 for f in terrain.features:
  var label:=Label3D.new();label.text=f.name;label.position=Vector3(f.start-3,1.3,f.z+f.width*.5+2);label.font_size=42;label.pixel_size=.012;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.modulate=Color('#fff3d5');label.visibility_range_end=45;label.outline_size=4;add_child(label)
func _pair_markers(f: Dictionary) -> void:
 var mat:=StandardMaterial3D.new();mat.albedo_color=Color('#eee2b9').srgb_to_linear();mat.roughness=.95
 for i in 8:
  var stripe:=_mesh(_boxes([[Vector3(.65,.012,.05),Vector3.ZERO]]),mat)
  stripe.position=Vector3(f.start-13+i*1.4,.012,f.z)
 for side in [-1,1]:
  var label:=Label3D.new();label.text='STEEP 42°' if side<0 else 'MEDIUM 24°';label.position=Vector3(f.start-5,.6,f.z+side*3.0);label.font_size=42;label.pixel_size=.012;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.outline_size=4;label.visibility_range_end=40;add_child(label)
