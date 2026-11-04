"""Reusable Blender interior and glazing builder.

The host supplies an exterior shell with UV0. Vehicle-specific window outlines,
cabin envelope and furniture sizes live in interior_config.json, in metres / Z up.
"""
import bpy, bmesh, math, json
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from cabin_fit import validate_config, fit_points, clearance_at, boundary_clearance_at

EPS=1e-7

def clean_polygon(poly):
    clean=[]
    for item in poly:
        if not clean or (clean[-1][0]-item[0]).length>1e-7:clean.append(item)
    if len(clean)>1 and (clean[0][0]-clean[-1][0]).length<1e-7:clean.pop()
    changed=True
    while changed and len(clean)>3:
        changed=False
        for i in range(len(clean)):
            a,b,c=clean[i-1][0],clean[i][0],clean[(i+1)%len(clean)][0]
            if (b-a).cross(c-b).length<1e-11:
                clean.pop(i);changed=True;break
    return clean

def area2(poly):
    return sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(poly,poly[1:]+poly[:1]))

def normalized_polygon(poly):
    poly=[tuple(p) for p in poly]
    if area2(poly)<0:poly.reverse()
    for a,b,c in zip(poly,poly[1:]+poly[:1],poly[2:]+poly[:2]):
        if (b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0]) < -EPS:
            raise ValueError('Window outlines must be convex; split a concave pane into convex panes.')
    return poly

def clip(poly,a,b,inside):
    """Clip 3D points + UV coordinates against an image-space half plane."""
    if not poly:return []
    def distance(p):
        q=p[1];return (b[0]-a[0])*(q[1]-a[1])-(b[1]-a[1])*(q[0]-a[0])
    out=[]
    for p,q in zip(poly,poly[1:]+poly[:1]):
        dp,dq=distance(p),distance(q)
        pin=dp>=-EPS if inside else dp<=EPS
        qin=dq>=-EPS if inside else dq<=EPS
        if pin:out.append(p)
        if pin!=qin and abs(dp-dq)>EPS:
            t=dp/(dp-dq);out.append((p[0].lerp(q[0],t),p[1].lerp(q[1],t)))
    out=clean_polygon(out)
    if len(out)<3:return []
    normal=(out[1][0]-out[0][0]).cross(out[2][0]-out[0][0])
    if normal.length<1e-11:return []
    return out

def subtract(poly,window):
    remaining=poly;outside=[]
    for a,b in zip(window,window[1:]+window[:1]):
        fragment=clip(remaining,a,b,False)
        if fragment:outside.append(fragment)
        remaining=clip(remaining,a,b,True)
        if not remaining:break
    return outside,remaining

def world_mesh(name,faces,material,collection,parent,colors=None,uvs=None,role=0,smooth=False):
    verts=[];indices=[]
    for face in faces:
        start=len(verts);verts.extend([tuple(p) for p in face]);indices.append(tuple(range(start,len(verts))))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],indices);mesh.update()
    layer=mesh.uv_layers.new(name='UV0')
    for i,poly in enumerate(mesh.polygons):
        pts=faces[i]
        n=(Vector(pts[1])-Vector(pts[0])).cross(Vector(pts[2])-Vector(pts[0]))
        axes=[k for k in range(3) if k!=max(range(3),key=lambda k:abs(n[k]))]
        for j,li in enumerate(poly.loop_indices):
            layer.data[li].uv=uvs[i][j] if uvs else (pts[j][axes[0]]*4,pts[j][axes[1]]*4)
        poly.use_smooth=smooth
    mesh.materials.append(material)
    obj=bpy.data.objects.new(name,mesh);collection.objects.link(obj);obj.parent=parent
    if colors:
        ca=mesh.color_attributes.new(name='InteriorTint',type='FLOAT_COLOR',domain='CORNER')
        for i,poly in enumerate(mesh.polygons):
            for li in poly.loop_indices:ca.data[li].color=(*colors[i],1)
    category=mesh.attributes.new('interior_role','INT','FACE')
    for item in category.data:item.value=role
    return obj

def paint_object(obj,mat,color,role):
    obj.data.materials.clear();obj.data.materials.append(mat)
    ca=obj.data.color_attributes.new(name='InteriorTint',type='FLOAT_COLOR',domain='CORNER')
    for loop in ca.data:loop.color=(*color,1)
    obj.data.uv_layers.new(name='UV0')
    layer=obj.data.uv_layers.active
    for poly in obj.data.polygons:
        axes=[k for k in range(3) if k!=max(range(3),key=lambda k:abs(poly.normal[k]))]
        for li in poly.loop_indices:
            p=obj.data.vertices[obj.data.loops[li].vertex_index].co
            layer.data[li].uv=(p[axes[0]]*8,p[axes[1]]*8)
    attr=obj.data.attributes.new('interior_role','INT','FACE')
    for q in attr.data:q.value=role

class Interior:
    def __init__(self,config,collection,root,output):
        validate_config(config);self.c=config;self.collection=collection;self.output=output;self.parts=[];self.fit_report=[]
        self.root=bpy.data.objects.new('Niva_Interior',None);collection.objects.link(self.root);self.root.parent=root
        self.glass_root=bpy.data.objects.new('Niva_Glazing',None);collection.objects.link(self.glass_root);self.glass_root.parent=root
        self.mat=bpy.data.materials.new('Interior / configurable vertex colours');self.mat.use_nodes=True
        bs=self.mat.node_tree.nodes.get('Principled BSDF');v=self.mat.node_tree.nodes.new('ShaderNodeVertexColor');v.layer_name='InteriorTint'
        self.mat.node_tree.links.new(v.outputs['Color'],bs.inputs['Base Color'])
        bs.inputs['Roughness'].default_value=.68;bs.inputs['Specular IOR Level'].default_value=.27
        self.mat.diffuse_color=(*config['colors']['seat'],1)
        self.glass=bpy.data.materials.new('Glazing / transparent tinted glass');self.glass.use_nodes=True
        g=self.glass.node_tree.nodes.get('Principled BSDF');g.inputs['Base Color'].default_value=(*config['glass']['color'],1)
        g.inputs['Alpha'].default_value=config['glass']['alpha'];g.inputs['Roughness'].default_value=config['glass']['roughness']
        g.inputs['IOR'].default_value=1.45;g.inputs['Specular IOR Level'].default_value=.5
        self.glass.diffuse_color=(*config['glass']['color'],config['glass']['alpha'])
        self.glass.surface_render_method='BLENDED';self.glass.use_backface_culling=False
        if hasattr(self.glass,'use_transparency_overlap'):self.glass.use_transparency_overlap=False
        self.glass['purpose']='Actual alpha-blended glazing with no photographed interior texture.'

    def color(self,key):return self.c['colors'][key]

    def box(self,name,center,size,color='trim',bevel=.018,rotation=0,role=2):
        bpy.ops.object.select_all(action='DESELECT')
        bpy.ops.mesh.primitive_cube_add(size=1,location=center)
        obj=bpy.context.object;obj.name='Interior_'+name;obj.scale=size
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        if bevel:
            mod=obj.modifiers.new('Soft manufactured edges','BEVEL');mod.width=min(bevel,min(size)*.35);mod.segments=2
            bpy.ops.object.modifier_apply(modifier=mod.name)
            mod=obj.modifiers.new('Weighted normals','WEIGHTED_NORMAL');mod.keep_sharp=True
            bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.rotation_euler.y=math.radians(rotation)
        for coll in list(obj.users_collection):coll.objects.unlink(obj)
        self.collection.objects.link(obj);obj.parent=self.root
        paint_object(obj,self.mat,self.color(color),role);self.parts.append(obj)
        return obj

    def rod(self,name,p0,p1,r,color='trim',segments=10,role=3):
        p0,p1=Vector(p0),Vector(p1);axis=(p1-p0).normalized();u=axis.cross(Vector((0,0,1)))
        if u.length<.01:u=axis.cross(Vector((0,1,0)))
        u.normalize();v=axis.cross(u).normalized();faces=[]
        ring=[]
        for p in (p0,p1):ring.append([p+r*(math.cos(i*math.tau/segments)*u+math.sin(i*math.tau/segments)*v) for i in range(segments)])
        for i in range(segments):j=(i+1)%segments;faces.append([ring[0][i],ring[0][j],ring[1][j],ring[1][i]])
        faces.extend([list(reversed(ring[0])),ring[1]])
        obj=world_mesh('Interior_'+name,faces,self.mat,self.collection,self.root,[self.color(color)]*len(faces),role=role,smooth=True)
        self.parts.append(obj);return obj

    def fit(self,name,parts,anchor):
        bpy.context.view_layer.update()
        points=[tuple(o.matrix_world@v.co) for o in parts for v in o.data.vertices]
        scale,gap=fit_points(points,self.c['envelope'],anchor,self.c['fit'])
        if scale<1:
            for o in parts:o.location=Vector(anchor)+(o.location-Vector(anchor))*scale;o.scale*=scale
        bpy.context.view_layer.update()
        self.fit_report.append({'component':name,'scale':scale,'minimum_envelope_clearance_m':round(gap,5),'vertices_checked':len(points)})
        for o in parts:o['fitted_component']=name

    def shell_and_glass(self,host):
        mesh=host.data;mesh.calc_loop_triangles();uv0=mesh.uv_layers.active.data;size=self.c['atlas_size']
        windows=[{**w,'polygon':normalized_polygon(w['polygon_px'])} for w in self.c['windows']]
        kept=[];glazing={w['name']:[] for w in windows}
        for tri in mesh.loop_triangles:
            poly=[(mesh.vertices[mesh.loops[li].vertex_index].co.copy(),Vector((uv0[li].uv.x*size,(1-uv0[li].uv.y)*size))) for li in tri.loops]
            fragments=[poly]
            for w in windows:
                center=sum((p[0] for p in poly),Vector())/3
                if 'side_sign' in w and center.y*w['side_sign']<.3:continue
                a=w['polygon'];lo=[min(p[k] for p in a) for k in (0,1)];hi=[max(p[k] for p in a) for k in (0,1)]
                if any(max(p[1][k] for p in poly)<lo[k] or min(p[1][k] for p in poly)>hi[k] for k in (0,1)):continue
                fresh=[]
                for f in fragments:
                    outside,cut=subtract(f,a);fresh.extend(outside)
                    if cut:glazing[w['name']].append(cut)
                fragments=fresh
            kept.extend(fragments)
        # Replace opaque shell faces with fragments that actually surround holes.
        outer=world_mesh('Temporary_cut_body',[[p[0] for p in f] for f in kept],mesh.materials[0],self.collection,host.parent,
                         uvs=[[(p[1].x/size,1-p[1].y/size) for p in f] for f in kept],smooth=True)
        old=host.data;host.data=outer.data;bpy.data.objects.remove(outer,do_unlink=True)
        if old.users==0:bpy.data.meshes.remove(old)
        # Inward-facing roof, pillars, upper door rails, and cut-edge returns.
        lining=[];colours=[];xmin,xmax=self.c['lining']['x_bounds'];thickness=self.c['lining']['thickness']
        for f in kept:
            pts=[p[0] for p in f];center=sum(pts,Vector())/len(pts)
            if not (xmin<=center.x<=xmax and center.z>=self.c['lining']['min_z']):continue
            n=(pts[1]-pts[0]).cross(pts[2]-pts[0]).normalized()
            target=Vector((-.5-center.x,-center.y,1.05-center.z))
            inward=n if n.dot(target)>0 else -n
            inner=[p+inward*thickness for p in pts]
            # Orient towards the cabin instead of relying on double-sided paint.
            if n.dot(inward)<0:inner.reverse()
            lining.append(inner)
            colours.append(self.color('headliner' if center.z>1.66 and abs(n.z)>.55 else 'pillar'))
            for (p,uvp),(q,uvq) in zip(f,f[1:]+f[:1]):
                on_window=False
                for w in windows:
                    if 'side_sign' in w and center.y*w['side_sign']<.3:continue
                    for a,b in zip(w['polygon'],w['polygon'][1:]+w['polygon'][:1]):
                        edge=Vector(b)-Vector(a);length=edge.length
                        if length<EPS:continue
                        d1=abs(edge.x*(uvp.y-a[1])-edge.y*(uvp.x-a[0]))/length
                        d2=abs(edge.x*(uvq.y-a[1])-edge.y*(uvq.x-a[0]))/length
                        if max(d1,d2)<.01:on_window=True;break
                    if on_window:break
                if on_window:
                    lining.append([p,q,q+inward*thickness,p+inward*thickness]);colours.append(self.color('trim'))
        liner=world_mesh('Interior_Headliner_and_Pillars',lining,self.mat,self.collection,self.root,colours,role=1)
        self.parts.append(liner)
        glass_report=[]
        for name,fragments in glazing.items():
            if not fragments:raise ValueError('No glazing cut for '+name)
            faces=[[p[0] for p in f] for f in fragments]
            obj=world_mesh('Glass_'+name,faces,self.glass,self.collection,self.glass_root,
                           uvs=[[(p[1].x/size,1-p[1].y/size) for p in f] for f in fragments],smooth=True)
            obj.visible_shadow=False;obj['role']='transparent_glazing';obj['window_name']=name
            obj.data.calc_loop_triangles();area=sum(t.area for t in obj.data.loop_triangles)
            if area<.02:raise ValueError('Implausibly small window '+name)
            glass_report.append({'window':name,'area_m2':round(area,4),'host_fragments_replaced':len(fragments)})
        self.glass_report=glass_report
        return liner

    def front_seat(self,y,label):
        c=self.c['front_seats'];start=len(self.parts);x,z=c['x'],c['cushion_z'];w,d,t=c['width'],c['depth'],c['cushion_thickness']
        self.box(label+'_Cushion',(x,y,z),(d,w,t),'seat',.035)
        self.box(label+'_Cushion_Insert',(x+.015,y,z+t/2-.004),(d*.80,w*.73,.017),'seat_insert',.008)
        for sy in (-1,1):
            self.box(label+'_Cushion_Bolster_'+str(sy),(x,y+sy*w*.43,z+.035),(d*.93,w*.13,.095),'seat',.024)
            self.box(label+'_Rail_'+str(sy),(x-.03,y+sy*w*.34,self.c['floor']['z']+.036),(d*.85,.032,.045),'metal',.008)
        bx=x-d*.5-.015;bz=z+t*.35+c['back_height']*.5
        self.box(label+'_Back',(bx,y,bz),(c['back_thickness'],w,c['back_height']),'seat',.03,-c['recline_degrees'])
        # Raised insert lies on the front side of the actual sloped backrest.
        self.box(label+'_Back_Insert',(bx+.059,y,bz+.004),(.015,w*.72,c['back_height']*.78),'seat_insert',.01,-c['recline_degrees'])
        for i in range(5):
            self.box(label+'_Stitch_'+str(i),(x-.15+i*.075,y,z+t/2+.006),(.006,w*.70,.008),'seat',.002)
        if c['headrest']:
            hx=bx-.065;hz=bz+c['back_height']*.5+.095
            self.box(label+'_Headrest',(hx,y,hz),(.12,c['headrest_width'],c['headrest_height']),'seat',.035)
            for sy in (-1,1):self.rod(label+'_Headrest_Post_'+str(sy),(hx,y+sy*.075,hz-.13),(hx,y+sy*.075,hz-.07),.008,'metal',8,2)
        self.box(label+'_Belt_Buckle',(x-.17,y+(.27 if y<0 else -.27),z+.04),(.055,.035,.08),'trim',.009)
        self.fit(label,self.parts[start:],(x,y,z))

    def bench(self):
        c=self.c['rear_bench'];start=len(self.parts);x,z=c['x'],c['cushion_z'];w,d,t=c['width'],c['depth'],c['cushion_thickness']
        self.box('Rear_Bench_Cushion',(x,0,z),(d,w,t),'seat',.035)
        for sy in (-1,1):self.box('Rear_Bench_Insert_'+str(sy),(x+.01,sy*w*.245,z+t/2-.002),(d*.81,w*.43,.018),'seat_insert',.01)
        bx=x-d*.5-.025;bz=z+t*.32+c['back_height']*.5
        self.box('Rear_Bench_Back',(bx,0,bz),(c['back_thickness'],w,c['back_height']),'seat',.035,-c['recline_degrees'])
        for sy in (-1,1):self.box('Rear_Back_Insert_'+str(sy),(bx+.055,sy*w*.245,bz),(.015,w*.43,c['back_height']*.80),'seat_insert',.01,-c['recline_degrees'])
        if c['headrests']:
            for sy in (-1,1):self.box('Rear_Headrest_'+str(sy),(bx-.05,sy*w*.28,bz+c['back_height']*.5+.08),(.12,.25,.17),'seat',.03)
        self.box('Rear_Seat_Base',(x,0,self.c['floor']['z']+.070),(d*.85,w*.90,.10),'trim',.02)
        self.fit('rear_bench',self.parts[start:],(x,0,z))

    def dash_and_controls(self):
        c=self.c['dashboard'];start=len(self.parts);center=c['center'];size=c['size']
        cx,cy,cz=center;dx,dy,dz=size;driver_y=self.c['steering']['center'][1]
        self.box('Dashboard',center,size,'dashboard',.035,role=3)
        self.box('Dashboard_Top',(center[0]-.015,0,center[2]+size[2]/2),(.29,size[1]*.98,.028),'trim',.01,role=3)
        self.box('Glovebox',(center[0]-.147,.37,center[2]-.025),(.012,.48,.105),'trim',.009,role=3)
        self.box('Glovebox_Handle',(center[0]-.159,.37,center[2]-.006),(.012,.08,.012),'metal',.003,role=3)
        self.box('Instrument_Binnacle',(cx-dx*.464,driver_y,cz+dz*.588),(dx*.607,dy*.261,dz*.618),'trim',.02,role=3)
        gx=cx-dx*.83;gz=cz+dz*.594
        for y in (driver_y-.085,driver_y+.08):
            self.rod('Gauge',(gx+.01,y,gz),(gx,y,gz),min(.059,dy*.05),'instrument',24)
            self.rod('Gauge_Needle',(gx-.007,y,gz),(gx-.007,y+.026,gz+.021),.0025,'markings',6)
        for y in (cy-dy*.45,cy+dy*.07,cy+dy*.43):
            vx=cx-dx*.55;vz=cz+dz*.15
            self.box('Vent',(vx,y,vz),(.015,.10,.045),'instrument',.006,role=3)
            for offset in (-.012,0,.012):self.rod('Vent_Slat',(vx-.013,y-.044,vz+offset),(vx-.013,y+.044,vz+offset),.002,'metal',6)
        floor_z=self.c['floor']['z'];console_x=cx-.25
        self.box('Centre_Console',(console_x,cy,floor_z+.228),(dx*1.36,.19,.28),'dashboard',.026,role=3)
        self.box('Radio',(cx-dx*.52,cy,cz-.058),(.012,.155,.052),'instrument',.004,role=3)
        self.rod('Gear_Lever',(console_x-.12,cy,floor_z+.178),(console_x-.185,cy,floor_z+.398),.009,'metal',10)
        self.box('Gear_Knob',(console_x-.185,cy,floor_z+.398),(.05,.05,.06),'trim',.017,role=3)
        self.fit('dashboard',self.parts[start:],(cx-.06,cy,cz-.045))
        start=len(self.parts);cfg=self.c['steering'];p=Vector(cfg['center']);axis=Vector(cfg['axis']).normalized()
        u=Vector((0,1,0));v=axis.cross(u).normalized();n=40;m=8;r=cfg['radius'];tube=cfg['tube_radius'];faces=[]
        def pt(i,j):
            a=i*math.tau/n;b=j*math.tau/m;rad=math.cos(a)*u+math.sin(a)*v
            return p+(r+tube*math.cos(b))*rad+tube*math.sin(b)*axis
        for i in range(n):
            for j in range(m):faces.append([pt(i,j),pt(i+1,j),pt(i+1,j+1),pt(i,j+1)])
        obj=world_mesh('Interior_Steering_Rim',faces,self.mat,self.collection,self.root,[self.color('trim')]*len(faces),role=3,smooth=True);self.parts.append(obj)
        self.rod('Steering_Hub',p-axis*.018,p+axis*.035,.042,'trim',16)
        for angle in (0,math.pi,math.pi*1.5):
            endpoint=p+r*.92*(math.cos(angle)*u+math.sin(angle)*v)
            self.rod('Steering_Spoke',p,endpoint,.013,'trim',8)
        self.rod('Steering_Column',p+axis*.025,cfg['column_end'],.022,'trim',12)
        self.fit('steering',self.parts[start:],tuple(p))

    def trim_and_floor(self):
        f=self.c['floor'];z=f['z'];xmin,xmax=f['x_bounds'];transition=f['width_transition_x'];rw=f['rear_half_width'];fw=f['front_half_width']
        self.box('Rear_Floor',((xmin+transition)/2,0,z),(transition-xmin,rw*2,.026),'carpet',.006,role=5)
        self.box('Front_Floor',((transition+xmax)/2,0,z),(xmax-transition,fw*2,.026),'carpet',.006,role=5)
        tunnel=self.c['center_tunnel']
        self.box('Centre_Tunnel',tunnel['center'],tunnel['size'],'carpet',.035,role=5)
        for panel in self.c['boundary_panels']:
            self.box(panel['name'],panel['center'],panel['size'],panel['color'],.012,role=4)
        c=self.c['trim'];xa,xb=c['door_x_bounds'];za,zb=c['door_z_bounds']
        for sy in (-1,1):
            self.box('Door_Panel_'+str(sy),((xa+xb)/2,sy*c['door_half_width'],(za+zb)/2),(xb-xa,.035,zb-za),'trim',.012,role=4)
            self.box('Door_Armrest_'+str(sy),((xa+xb)/2-.19,sy*(c['door_half_width']-.04),za+(zb-za)*.574),((xb-xa)/3,.075,.06),'pillar',.015,role=4)

    def validate_exterior_intersections(self,host):
        bpy.context.view_layer.update();mesh=host.data;mesh.calc_loop_triangles()
        outer=BVHTree.FromPolygons([v.co for v in mesh.vertices],[t.vertices for t in mesh.loop_triangles],all_triangles=True)
        tested=0;collisions=[]
        boundary_vertices_checked=0
        for obj in self.parts:
            # Headliner/pillars intentionally follow the exterior at a small
            # inward offset. Check all other parts, including floor/door trim.
            if obj.name=='Interior_Headliner_and_Pillars':continue
            obj.data.calc_loop_triangles()
            points=[obj.matrix_world@v.co for v in obj.data.vertices]
            if not obj.get('fitted_component'):
                gap=min(boundary_clearance_at(self.c['envelope'],p,self.c['fit']['boundary_allowance']) for p in points)
                if gap < -1e-6:raise ValueError('Boundary trim outside configured cabin limits: '+obj.name)
                boundary_vertices_checked+=len(points)
            tree=BVHTree.FromPolygons(points,[t.vertices for t in obj.data.loop_triangles],all_triangles=True)
            overlaps=tree.overlap(outer);tested+=1
            if overlaps:collisions.append({'part':obj.name,'triangle_pairs':len(overlaps)})
        if collisions:raise ValueError('Interior furniture intersects exterior: '+json.dumps(collisions))
        window_ray_checks=[]
        for obj in self.glass_root.children:
            obj.data.calc_loop_triangles();tri=max(obj.data.loop_triangles,key=lambda t:t.area)
            p=sum((obj.data.vertices[i].co for i in tri.vertices),Vector())/3;n=tri.normal
            hit=outer.ray_cast(p-n*.02,n,.04)[0]
            if hit is not None:raise ValueError('Opaque host face still covers glass: '+obj.name)
            window_ray_checks.append({'window':obj['window_name'],'opaque_host_under_glass':False})
        report={'config_schema':1,'windows':self.glass_report,'fitted_components':self.fit_report,
                'exterior_triangle_intersections':collisions,'interior_meshes_checked_against_exterior':tested,
                'boundary_trim_vertices_checked':boundary_vertices_checked,'window_opening_ray_checks':window_ray_checks,
                'lining':'Inward-facing copies of retained cabin surfaces and actual window-edge returns.',
                'clearance_scope':'Furniture vertices tested against conservative envelope. Furniture, floor and trim triangles tested against exterior shell. Lining follows the shell inward; trim is not auto-shrunk.'}
        (self.output/'source/interior_fit_report.json').write_text(json.dumps(report,indent=2))
        return report

def add_interior(host,collection,root,output):
    config=json.loads((output/'source/interior_config.json').read_text())
    builder=Interior(config,collection,root,output)
    builder.shell_and_glass(host)
    builder.trim_and_floor()
    for sy,name in [(-1,'Driver_Seat'),(1,'Passenger_Seat')]:builder.front_seat(sy*config['front_seats']['y_offset'],name)
    builder.bench();builder.dash_and_controls()
    report=builder.validate_exterior_intersections(host)
    root['interior']='Configurable front seats, rear bench, dashboard, steering wheel, inward roof/pillars, door trim and floor.'
    root['glazing']='Six real cut-out windows with separate alpha-blended glass, without painted cabin imagery.'
    return builder,report
