"""Build an exterior game asset from the supplied four-view reference.

Usage: blender -b --factory-startup --python source/build_niva.py
Coordinates: metres, Z up, X forward; root origin at ground / wheelbase centre.
"""
from pathlib import Path
import bpy, bmesh, math, json, sys
from mathutils import Vector, Matrix

ROOT=Path(__file__).resolve().parents[1]
S=2.2/501
ATLAS=2048
sys.path.insert(0,str(ROOT/'source'))
from vehicle_interior import add_interior
from vehicle_operations import make_operable
swatches=json.loads((ROOT/'source/swatch_coordinates.json').read_text())
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for coll in list(bpy.data.collections):
    if coll.name!='Collection': bpy.data.collections.remove(coll)
asset=bpy.data.collections.new('NIVA_LOD0'); bpy.context.scene.collection.children.link(asset)
studio=bpy.data.collections.new('STUDIO'); bpy.context.scene.collection.children.link(studio)
collision=bpy.data.collections.new('COLLISION_optional'); bpy.context.scene.collection.children.link(collision)
collision.hide_render=True
root=bpy.data.objects.new('Niva_2121',None); asset.objects.link(root)
root['description']='Reference-matched exterior game asset. X forward, Z up, metres.'
root['reference_scale']='Wheelbase 2.20m; other dimensions follow normalized artwork.'

def material():
    mat=bpy.data.materials.new('Niva / 2K PBR atlas'); mat.use_nodes=True
    n=mat.node_tree.nodes; l=mat.node_tree.links; bs=n.get('Principled BSDF')
    tex=n.new('ShaderNodeTexImage'); tex.image=bpy.data.images.load(str(ROOT/'textures/Niva_BaseColor.png'))
    tex.image.colorspace_settings.name='sRGB'; tex.label='Reference detail / base color'; tex.location=(-600,200)
    l.new(tex.outputs['Color'],bs.inputs['Base Color'])
    orm=n.new('ShaderNodeTexImage'); orm.image=bpy.data.images.load(str(ROOT/'textures/Niva_ORM.png'))
    orm.image.colorspace_settings.name='Non-Color'; orm.location=(-600,-60)
    sep=n.new('ShaderNodeSeparateColor'); sep.mode='RGB'; sep.location=(-330,-60)
    l.new(orm.outputs['Color'],sep.inputs['Color']); l.new(sep.outputs['Green'],bs.inputs['Roughness']); l.new(sep.outputs['Blue'],bs.inputs['Metallic'])
    texn=n.new('ShaderNodeTexImage'); texn.image=bpy.data.images.load(str(ROOT/'textures/Niva_Normal.png'))
    texn.image.colorspace_settings.name='Non-Color'; texn.location=(-600,-330)
    norm=n.new('ShaderNodeNormalMap'); norm.inputs['Strength'].default_value=.55; norm.location=(-310,-300)
    l.new(texn.outputs['Color'],norm.inputs['Color']); l.new(norm.outputs['Normal'],bs.inputs['Normal'])
    bs.inputs['Coat Weight'].default_value=.015
    bs.inputs['Coat Roughness'].default_value=.25
    bs.inputs['Specular IOR Level'].default_value=.25
    mat.diffuse_color=(.24,.29,.10,1)
    return mat
MAT=material()

def interp(x, points):
    if x<=points[0][0]: return points[0][1]
    for (a,b),(c,d) in zip(points,points[1:]):
        if x<=c: return b+(d-b)*(x-a)/(c-a)
    return points[-1][1]

def xyz(u,v,y): return ((u-500.5)*S,y,(991-v)*S)
def sideuv(p): return (p[0]/S+500.5,991-p[2]/S)
def frontuv(p): return (1233.5+p[1]/S,479-p[2]/S)
def rearuv(p): return (1233-p[1]/S*418/419,990-p[2]/S*408/411)
def topuv(p): return (86+(p[0]/S+500.5-59)*788/851,269.5-p[1]/S*361/419)
def uv(p,view):
    if isinstance(view,tuple): return view
    if view in swatches: return swatches[view]
    return {'side':sideuv,'front':frontuv,'rear':rearuv,'top':topuv}[view](p)

class Builder:
    def __init__(self): self.v=[]; self.f=[]; self.uv=[]
    def face(self,pts,view,tex=None):
        i=len(self.v); self.v.extend(pts); self.f.append(tuple(range(i,i+len(pts))))
        if tex is None and isinstance(view,str) and view in swatches:
            normal=(Vector(pts[1])-Vector(pts[0])).cross(Vector(pts[2])-Vector(pts[0]))
            dominant=max(range(3),key=lambda k:abs(normal[k]))
            axes=[k for k in range(3) if k!=dominant]; cx,cy=swatches[view]
            tex=[(cx+p[axes[0]]*8,cy+p[axes[1]]*8) for p in pts]
        self.uv.append(tex if tex else [uv(p,view) for p in pts])
    def grid(self,rows,view):
        for a,b in zip(rows,rows[1:]):
            for j in range(len(a)-1): self.face([a[j],b[j],b[j+1],a[j+1]],view)
    def finish(self,name,smooth=True,collection=asset,parent=root,pivot=None):
        mesh=bpy.data.meshes.new(name); mesh.from_pydata(self.v,[],self.f); mesh.update()
        layer=mesh.uv_layers.new(name='UV0')
        for poly,coords in zip(mesh.polygons,self.uv):
            for li,(u,v) in zip(poly.loop_indices,coords): layer.data[li].uv=(u/ATLAS,1-v/ATLAS)
        bm=bmesh.new(); bm.from_mesh(mesh); bmesh.ops.remove_doubles(bm,verts=bm.verts,dist=.00002)
        bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(mesh); bm.free(); mesh.update()
        for poly in mesh.polygons: poly.use_smooth=smooth
        obj=bpy.data.objects.new(name,mesh); collection.objects.link(obj); mesh.materials.append(MAT)
        if parent: obj.parent=parent
        if pivot:
            mesh.transform(Matrix.Translation(-Vector(pivot))); obj.location=pivot
        return obj

def move_collection(obj,coll):
    for c in list(obj.users_collection): c.objects.unlink(obj)
    coll.objects.link(obj)

def box(name,loc,dim,view='rubber',bevel=.015,collection=asset):
    x,y,z=loc; a,b,c=[v/2 for v in dim]; build=Builder()
    vs=[(x-a,y-b,z-c),(x+a,y-b,z-c),(x+a,y+b,z-c),(x-a,y+b,z-c),
        (x-a,y-b,z+c),(x+a,y-b,z+c),(x+a,y+b,z+c),(x-a,y+b,z+c)]
    for ids in [(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]:
        build.face([vs[i] for i in ids],view)
    obj=build.finish(name,smooth=False,collection=collection,parent=root if collection==asset else None)
    if bevel:
        mod=obj.modifiers.new('Small manufactured edge radius','BEVEL'); mod.width=bevel; mod.segments=2
        mod.affect='EDGES'
        bpy.context.view_layer.objects.active=obj; obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=mod.name); obj.select_set(False)
        mod=obj.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL'); mod.keep_sharp=True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj

def rod(name,p0,p1,radius,view='undercarriage',segments=10):
    a,b=Vector(p0),Vector(p1); axis=(b-a).normalized()
    tangent=axis.cross(Vector((0,0,1)))
    if tangent.length<.01: tangent=axis.cross(Vector((1,0,0)))
    tangent.normalize(); bitangent=axis.cross(tangent).normalized()
    rows=[]
    for p in (a,b):
        rows.append([tuple(p+radius*(math.cos(2*math.pi*i/segments)*tangent+math.sin(2*math.pi*i/segments)*bitangent)) for i in range(segments+1)])
    build=Builder(); build.grid(rows,view); build.face(list(reversed(rows[0][:-1])),view); build.face(rows[1][:-1],view)
    return build.finish(name)

def vbase(u): return interp(u,[(92,741),(105,718),(130,712),(625,711),(650,711),(700,714),(810,723),(850,733),(868,748)])
def width(u,v):
    longitudinal=interp(u,[(92,.84),(110,.895),(140,.920),(820,.920),(850,.90),(868,.855)])
    vertical=interp(v,[(710,.968),(742,1),(764,.998),(820,.972),(880,.915)])
    return longitudinal*vertical
def cabinwidth(u,v):
    d=max(0,vbase(u)-v)
    return width(u,vbase(u))-d*.0014-.022*min(1,d/20)
arch=[(145,878),(156,844),(175,814),(196,795),(223,783),(250,779),(280,785),(308,802),(330,833),(346,878)]
def bottom(u):
    v=interp(u,[(92,859),(120,877),(360,881),(635,881),(860,873),(868,850)])
    for offset in (0,501):
        if arch[0][0]+offset<=u<=arch[-1][0]+offset:
            v=min(v,interp(u-offset,arch))
    return max(vbase(u)+5,v)

# Body panels use the original side projection. Arch openings are actual cutouts,
# with dark return surfaces inside them; they are not painted over solid boxes.
shell=Builder()
uvals=sorted(set([92,100,105,110,120,130,140,145,156,175,196,223,250,280,308,330,346,360,
                  390,400,500,550,600,625,635,640,645,646,657,676,697,724,751,781,809,831,847,850,860,868]
                 +list(range(100,868,12))))
for sign in (-1,1):
    rows=[]
    for u in uvals:
        row=[]; v0=vbase(u); v1=bottom(u)
        for t in (0,.10,.28,.5,.73,.9,1):
            v=v0+(v1-v0)*t
            lip=.012*math.exp(-((v-v1)/7)**2) if v1<870 else 0
            row.append(xyz(u,v,sign*(width(u,v)+lip)))
        rows.append(row)
    shell.grid(rows,'side')
    for offset in (0,501):
        cavity=Builder(); lipbuild=Builder()
        pts=[(u+offset,v) for u,v in arch]
        rows2=[]
        for u,v in pts:
            rows2.append([xyz(u,v,sign*(width(u,v)+.012)),xyz(u,v+2,sign*.64)])
        cavity.grid(rows2,'rubber')
        # A dark inner backing closes the wheel well above / behind the tyre.
        # Without it an orthographic side view can see through the whole car.
        backing=[xyz(u,v+2,sign*.64) for u,v in pts]
        backing.extend([xyz(pts[-1][0],893,sign*.64),xyz(pts[0][0],893,sign*.64)])
        cavity.face(backing,'rubber')
        cavity.finish(('L' if sign<0 else 'R')+('_Rear' if offset==0 else '_Front')+'_WheelWell')

# Cabin shell and rounded roof: reference silhouettes, narrower at roof level.
roofline=[(92,741),(100,720),(110,700),(150,634),(180,598),(195,589),(220,586),
          (480,586),(526,589),(545,591),(560,608),(600,661),(640,708),(650,711)]
cu=sorted(set([p[0] for p in roofline]+list(range(110,650,15))+[195,545]))
for sign in (-1,1):
    rows=[]
    for u in cu:
        vt=interp(u,roofline); vb=vbase(u)
        rows.append([xyz(u,vt+(vb-vt)*t,sign*cabinwidth(u,vt+(vb-vt)*t)) for t in (0,.12,.34,.64,.86,1)])
    shell.grid(rows,'side')
cross=(-1,-.98,-.9,-.65,0,.65,.9,.98,1)
for u0,u1 in zip(cu,cu[1:]):
    rows=[]
    for u in (u0,u1):
        vt=interp(u,roofline); w=cabinwidth(u,vt)
        crown=interp(u,[(92,0),(180,2),(220,6),(480,6),(545,2),(650,0)])
        rows.append([xyz(u,vt-crown*(1-t*t),w*t) for t in cross])
    view='rear' if (u0+u1)/2<195 else 'front' if (u0+u1)/2>545 else 'top'
    shell.grid(rows,view)

# Bonnet has a real crowned top and rounded outer shoulder.
hu=[650,657,670,695,730,770,810,835,850,860,868]
rows=[]
for u in hu:
    vt=vbase(u); w=width(u,vt)
    crown=interp(u,[(650,2),(690,6),(810,5),(850,3),(868,1)])
    rows.append([xyz(u,vt-crown*(1-t*t),w*t) for t in cross])
shell.grid(rows,'top')

# Nose and tail close the shell. View-dependent UVs preserve the source grille,
# round lights, tailgate seams, rectangular tail lamps and plates.
for u,view,va,vb in [(868,'front',748,850),(92,'rear',741,859)]:
    rows=[]
    for v in [va,va+6,va+17,(va+vb)/2,vb-8,vb]:
        w=width(u,v)
        rows.append([xyz(u,v,w*t) for t in cross])
    shell.grid(rows,view)
body=shell.finish('Body_Shell_LOD0')
body['detail_strategy']='Panel seams, fuel flap, vents, grille, badges and lamp internals are UV texture detail.'
body['glass']='Actual openings and separate transparent panes.'
interior_builder, interior_report=add_interior(body,asset,root,ROOT)

# Main underside: a dark floor closes the shell behind the actual arch openings.
box('Underbody_Floor',(-.04,0,.49),(3.28,1.30,.12),'undercarriage',.025)
for sy in (-1,1):
    box(('Left' if sy<0 else 'Right')+'_Rocker_Sill',(-.02,sy*.827,.485),(1.29,.065,.082),'rubber',.012)

# Four wheels. Revolved cross sections, actual tyre width and dished steel rims;
# the small ventilation holes, stamped rings and sidewall lettering are textured.
def wheel(x,sy,name,n=48):
    center=(x,sy*.795,.390)
    assembly=bpy.data.objects.new(name,None); asset.objects.link(assembly); assembly.parent=root; assembly.location=center
    b=Builder()
    profile=[(.254,.111),(.315,.119),(.371,.109),(.389,.075),(.391,.045),(.391,-.045),(.389,-.075),(.371,-.109),(.315,-.119),(.254,-.111)]
    rows=[]
    for radius,depth in profile:
        rows.append([(x+radius*math.cos(2*math.pi*i/n),center[1]+sy*depth,center[2]+radius*math.sin(2*math.pi*i/n)) for i in range(n+1)])
    for j,(a,brow) in enumerate(zip(rows,rows[1:])):
        for i in range(n):
            pts=[a[i],a[i+1],brow[i+1],brow[i]]
            if 2<=j<=6:
                t0=i/n; t1=(i+1)/n; v0=1104+(j-2)/5*278; v1=1104+(j-1)/5*278
                tex=[(t0*1534,v0),(t1*1534,v0),(t1*1534,v1),(t0*1534,v1)]
            else:
                tex=[(250+(p[0]-x)/S,902.2-(p[2]-center[2])/S) for p in pts]
            b.face(pts,'side',tex)
    tire=b.finish(name+'_Tyre',pivot=center); tire.parent=assembly; tire.location=(0,0,0)
    rim=Builder(); rows=[]
    profile=[(.001,.132),(.038,.132),(.061,.119),(.11,.095),(.19,.084),(.226,.105),(.245,.111),(.254,.107)]
    for radius,depth in profile:
        rows.append([(x+radius*math.cos(2*math.pi*i/n),center[1]+sy*depth,center[2]+radius*math.sin(2*math.pi*i/n)) for i in range(n+1)])
    for a,brow in zip(rows,rows[1:]):
        for i in range(n):
            pts=[a[i],a[i+1],brow[i+1],brow[i]]
            rim.face(pts,'side',[(250+(p[0]-x)/S,902.2-(p[2]-center[2])/S) for p in pts])
    rr=rim.finish(name+'_Steel_Rim',pivot=center); rr.parent=assembly; rr.location=(0,0,0)
    # Inner dish avoids a visible open back when inspecting from below.
    inner=Builder(); pts=[(x+.254*math.cos(2*math.pi*i/n),center[1]-sy*.107,center[2]+.254*math.sin(2*math.pi*i/n)) for i in range(n)]
    inner.face(pts,'undercarriage'); obj=inner.finish(name+'_Inner_Rim',pivot=center); obj.parent=assembly; obj.location=(0,0,0)
    return assembly
for x,ax in [(-1.1,'Rear'),(1.1,'Front')]:
    for sy,side in [(-1,'Left'),(1,'Right')]: wheel(x,sy,f'Wheel_{ax}_{side}')

# Steel bumpers with actual rounded rubber ends; their broad faces inherit the
# original satin metal strip / front plate through the orthographic projection.
for x,name,view in [(1.72,'Front','front'),(-1.817,'Rear','rear')]:
    # Use source bumper UVs for broad visible face, constant rubber on returns.
    box(name+'_Bumper',(x,0,.625),(.19,1.89,.145),view,.018)
    for sy in (-1,1): box(name+'_Bumper_RubberEnd_'+str(sy),(x,sy*.878,.625),(.205,.17,.158),'rubber',.023)

# Round headlamp lenses are shallow low-poly domes so they catch real highlights.
for sy in (-1,1):
    cy=sy*(1387-1233.5)*S; cz=(479-292)*S
    b=Builder(); rings=[]
    for radius,depth in [(.114,0),(.109,.009),(.100,.014),(.070,.019),(.001,.023)]:
        rings.append([(1.625+depth,cy+radius*math.cos(i*2*math.pi/32),cz+radius*math.sin(i*2*math.pi/32)) for i in range(33)])
    b.grid(rings,'front'); b.finish(('L' if sy<0 else 'R')+'_Headlight_Lens')

# Front and rear plate cards, on tiny raised carriers to preserve readable text.
for x,z,view,name,w,h in [(1.826,.5555,'front','Front',.593,.127),(-1.807,.847,'rear','Rear',.594,.128)]:
    # Rear plate belongs above the bumper; front belongs at bumper height.
    plate=Builder()
    pts=[(x,-w/2,z-h/2),(x,w/2,z-h/2),(x,w/2,z+h/2),(x,-w/2,z+h/2)]
    plate.face(pts,view); plate.finish(name+'_Number_Plate',False)

# Side handles, mirrors and mudflaps add silhouette / parallax at low cost.
for sy,side in [(-1,'Left'),(1,'Right')]:
    u,v=419,729; p=xyz(u,v,sy*(width(u,v)+.011))
    box(side+'_Door_Handle',p,(.15,.025,.041),'side',.009)
    anchor=xyz(594,716,sy*.879); end=xyz(583,690,sy*.91)
    rod(side+'_Mirror_Stem',anchor,end,.009,'steel',8)
    box(side+'_Mirror_Housing',xyz(582,689,sy*.91),(.09,.155,.105),'steel',.016)
    box(side+'_Mirror_Glass',xyz(571,689,sy*.91),(.006,.135,.085),'mirror',.002)
    for x,ax in [(-1.1,'Rear'),(1.1,'Front')]:
        box(side+'_'+ax+'_Mudflap',(x-.485,sy*.785,.382),(.025,.26,.31),'rubber',.01)

# Visible undercarriage (coarse, deliberately economical).
for x,ax in [(-1.1,'Rear'),(1.1,'Front')]:
    rod(ax+'_Axle',(x,-.75,.365),(x,.75,.365),.045,'undercarriage',12)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=1,location=(x,0,.365))
    obj=bpy.context.object; obj.name=ax+'_Differential'; obj.scale=(.115,.15,.12)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); move_collection(obj,asset); obj.parent=root; obj.data.materials.append(MAT)
    layer=obj.data.uv_layers.active
    layer.name='UV0'
    for q in layer.data:
        q.uv=(swatches['undercarriage'][0]/2048+(q.uv.x-.5)*.02,1-swatches['undercarriage'][1]/2048+(q.uv.y-.5)*.02)
    for sy in (-1,1):
        rod(ax+'_Suspension_Link_'+str(sy),(x-.24,sy*.39,.50),(x+.10,sy*.64,.35),.024,'undercarriage',8)
rod('Propeller_Shaft',(-1.1,0,.37),(1.1,0,.40),.026,'undercarriage',10)
rod('Exhaust_Pipe',(-1.48,-.40,.46),(.25,-.40,.46),.025,'steel',12)
rod('Exhaust_Tailpipe',(-1.84,-.53,.35),(-1.45,-.40,.46),.025,'steel',12)
box('Exhaust_Silencer',(-.70,-.48,.47),(.53,.17,.12),'undercarriage',.035)

# Wipers, washer jets and vent slots stay in the texture, as appropriate for the
# exterior game asset and the resolution of the supplied reference.

# Collision is separate, named for common engine import conventions.
box('UCX_Niva_Body_00',(-.02,0,.90),(3.43,1.74,.70),'paint',0,collision)
box('UCX_Niva_Cabin_01',(-.40,0,1.42),(1.93,1.41,.71),'paint',0,collision)
collision.hide_viewport=True

operations=make_operable(body,interior_builder,asset,root,ROOT,{'side':sideuv,'front':frontuv,'rear':rearuv,'top':topuv})

# Five render meshes / one material: join static pieces, retain four independently
# rotatable wheel pivots. This avoids dozens of draw calls for cosmetic details.
def join_objects(objects,active,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects: o.select_set(True)
    bpy.context.view_layer.objects.active=active; bpy.ops.object.join(); active.name=name
    return active
for assembly in [o for o in asset.objects if o.type=='EMPTY' and o.name.startswith('Wheel_')]:
    parts=[o for o in assembly.children if o.type=='MESH']
    join_objects(parts,parts[0],assembly.name+'_Mesh')
interior_obj=join_objects(list(interior_builder.parts),interior_builder.parts[0],'Niva_Interior_Static')
interior_obj['role']='configurable_interior'
static=[o for o in asset.objects if o.type=='MESH' and o.parent==root and not o.name.startswith('Lamps_')]
body=join_objects(static,body,'Niva_Body_Static')
for obj in asset.all_objects:
    if obj.type=='MESH':
        bm=bmesh.new(); bm.from_mesh(obj.data)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.000001)
        bmesh.ops.dissolve_degenerate(bm,dist=0.0000001,edges=list(bm.edges))
        ngons=[f for f in bm.faces if len(f.verts)>4]
        if ngons: bmesh.ops.triangulate(bm,faces=ngons)
        bm.to_mesh(obj.data); bm.free(); obj.data.update()
        obj.data.validate(clean_customdata=False)
        # Glass and vertex-colour furniture do not consume UVs or tangents.
        if all(not any(n.type=='TEX_IMAGE' for n in m.node_tree.nodes) for m in obj.data.materials if m and m.use_nodes):
            for layer in list(obj.data.uv_layers):obj.data.uv_layers.remove(layer)

# Export evaluated, triangulated game meshes with one atlas material.
def mesh_stats(objs):
    tris=verts=0
    for o in objs:
        if o.type=='MESH':
            o.data.calc_loop_triangles(); tris+=len(o.data.loop_triangles); verts+=len(o.data.vertices)
    return {'triangles':tris,'mesh_vertices_before_uv_splits':verts,'mesh_objects':sum(o.type=='MESH' for o in objs)}
def select_collection(coll):
    bpy.ops.object.select_all(action='DESELECT')
    for o in coll.all_objects: o.select_set(True)
def export(coll,path):
    select_collection(coll)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
        export_yup=True,export_apply=True,export_texcoords=True,export_normals=True,
        export_tangents=True,export_materials='EXPORT',export_cameras=False,export_lights=False,
        export_extras=True,export_animations=True,export_animation_mode='ACTIVE_ACTIONS',
        export_nla_strips_merged_animation_name='Panels_Open_Close',export_frame_range=True,export_force_sampling=True)

stats={'LOD0':mesh_stats(asset.all_objects),'units':'metres','blender_axes':'X forward, Z up','gltf_axes':'X forward, Y up (Blender export conversion)',
       'wheelbase_m':2.2,'reference_dimensions_are_approximate':True,'texture_resolution':[2048,2048],
       'texture_materials':len({m.name for o in asset.all_objects if o.type=='MESH' for m in o.data.materials}),'operations':'vehicle_controls.json','interior':'Configurable interior with transparent glazing',
       'interior_config':'source/interior_config.json','interior_fit':interior_report,
       'reference_corrections':json.loads((ROOT/'source/reference_transforms.json').read_text())}
export(asset,ROOT/'Niva_2121_LOD0.glb')

# A practical second distance level, kept as a separate file so engines can
# assign their own switching distances. Original pivots and hierarchy survive.
lod1=bpy.data.collections.new('NIVA_LOD1'); bpy.context.scene.collection.children.link(lod1)
mapping={}
for obj in asset.all_objects:
    cp=obj.copy()
    if obj.type=='MESH': cp.data=obj.data.copy()
    lod1.objects.link(cp); mapping[obj]=cp
for old,cp in mapping.items():
    cp.parent=mapping.get(old.parent)
    if cp.type=='MESH' and len(cp.data.polygons)>20 and not cp.name.startswith('Glass_'):
        bpy.context.view_layer.objects.active=cp
        mod=cp.modifiers.new('Distance simplification','DECIMATE'); mod.ratio=.48
        bpy.ops.object.modifier_apply(modifier=mod.name)
        cp.data.validate(clean_customdata=False);cp.data.update()
stats['LOD1']=mesh_stats(lod1.all_objects)
original_names={o:o.name for o in mapping}
for old in mapping:old.name='LOD0__'+original_names[old]
for old,cp in mapping.items():cp.name=original_names[old]
export(lod1,ROOT/'Niva_2121_LOD1.glb')
for old,cp in mapping.items():cp.name='LOD1__'+original_names[old]
for old,name in original_names.items():old.name=name
lod1.hide_render=True; lod1.hide_viewport=True

# Review studio (not exported to the game asset).
scene=bpy.context.scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
scene.render.engine='CYCLES'; scene.cycles.samples=32
scene.cycles.use_denoising=True
scene.render.resolution_x=1500; scene.render.resolution_y=1080; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.film_transparent=False
scene.world.color=(.23,.23,.23)
world=scene.world; world.use_nodes=True; world.node_tree.nodes['Background'].inputs[0].default_value=(.24,.28,.33,1); world.node_tree.nodes['Background'].inputs[1].default_value=.45
scene.view_settings.view_transform='AgX'
groundmat=bpy.data.materials.new('Studio / warm grey'); groundmat.diffuse_color=(.17,.19,.17,1); groundmat.use_nodes=True
groundmat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.17,.19,.17,1)
groundmat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.86
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.005)); ground=bpy.context.object; ground.name='Studio_Ground'; move_collection(ground,studio); ground.data.materials.append(groundmat)
def light(name,loc,power,size,color):
    data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.shape='DISK'; data.size=size; data.color=color
    o=bpy.data.objects.new(name,data); studio.objects.link(o); o.location=loc; o.rotation_euler=(Vector((0,0,.7))-o.location).to_track_quat('-Z','Y').to_euler()
light('Key',(1,-4,6),650,5,(1,.91,.78))
light('Fill',(-3,3,4),500,4,(.75,.85,1))
light('Rim',(0,4,5),650,3,(1,.98,.87))
camdata=bpy.data.cameras.new('Review_Camera'); cam=bpy.data.objects.new('Review_Camera',camdata); studio.objects.link(cam); scene.camera=cam
def aim(loc,target=(0,0,.86)):
    cam.location=loc; cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
camdata.type='ORTHO'; camdata.ortho_scale=5.8; aim((5,-7,4.0))
select_collection(asset); bpy.context.view_layer.objects.active=body
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':
        area.spaces.active.region_3d.view_distance=5.5
        area.spaces.active.region_3d.view_location=(0,0,.85)
        area.spaces.active.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
        area.spaces.active.shading.type='MATERIAL'
for image in bpy.data.images:
    if image.source=='FILE': image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Niva_2121.blend'))
(ROOT/'asset_manifest.json').write_text(json.dumps(stats,indent=2))
if '--skip-renders' in sys.argv:
    print('ASSET_GEOMETRY_COMPLETE',json.dumps(stats['LOD0']),json.dumps(stats['LOD1']))
    raise SystemExit(0)

# The interior-aware renderer also makes cockpit, roof-lining, cutaway and
# opaque occupancy-mask passes for fair exterior silhouette comparisons.
import runpy
runpy.run_path(str(ROOT/'source/render_interior.py'),run_name='__main__')
print('ASSET_COMPLETE',json.dumps(stats['LOD0']),json.dumps(stats['LOD1']))
