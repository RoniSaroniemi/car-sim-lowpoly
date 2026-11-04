"""Rigid opening panels and named switchable lamp surfaces; no skeletal rig.

Vehicle-specific masks, pivots, limits and light strengths are JSON data.
Outer paint and UVs are retained. Inner skins, returns and jambs are real mesh.
"""
import bpy,bmesh,json,math
from mathutils import Vector,Matrix
from vehicle_interior import normalized_polygon,subtract,world_mesh

def center(points):return sum((Vector(p) for p in points),Vector())/len(points)

class Operations:
    def __init__(self,body,interior,collection,root,output,projectors):
        self.body=body;self.interior=interior;self.collection=collection;self.root=root;self.output=output
        self.config=json.loads((output/'source/vehicle_operations.json').read_text());self.panels=self.config['panels']
        self.projectors=projectors;self.pivots={};self.owned={};self.report={'panels':[],'lights':[]}
        for p in self.panels:
            p['_polygon']=normalized_polygon(p['polygon_px'])
            pivot=bpy.data.objects.new(p['node'],None);collection.objects.link(pivot);pivot.parent=root;pivot.location=p['pivot']
            pivot.empty_display_type='ARROWS';pivot.empty_display_size=.14
            pivot['control_id']=p['id'];pivot['open_degrees']=p['open_degrees'];pivot['axis_blender']=p['axis']
            self.pivots[p['id']]=pivot;self.owned[p['id']]=[]
        bpy.context.view_layer.update()

    def make(self,name,records,material,parent=None,role=0):
        if not records:return None
        obj=world_mesh(name,[r['points'] for r in records],material,self.collection,parent or self.root,
            colors=[r['color'] for r in records] if records[0].get('color') else None,
            uvs=[r['uv'] for r in records] if 'uv' in records[0] else None,role=role,smooth=not records[0].get('color'))
        return obj

    def eligible(self,p,points,lining):
        c=center(points)
        if 'side_sign' in p:
            if c.y*p['side_sign']<.60:return False
            if lining:
                n=(Vector(points[1])-Vector(points[0])).cross(Vector(points[2])-Vector(points[0])).normalized()
                if abs(n.y)<.25:return False
        elif p['id']=='tailgate' and lining:
            if c.x> -1.25:return False
            n=(Vector(points[1])-Vector(points[0])).cross(Vector(points[2])-Vector(points[0])).normalized()
            if abs(n.x)<.25:return False
        elif lining:return False
        return True

    def partition(self,obj,lining=False):
        mesh=obj.data;mesh.calc_loop_triangles();uv=mesh.uv_layers.active.data
        ca=mesh.color_attributes.get('InteriorTint');matrix=obj.matrix_world.copy()
        kept=[];pieces={p['id']:[] for p in self.panels}
        for tri in mesh.loop_triangles:
            pts=[matrix@mesh.vertices[mesh.loops[li].vertex_index].co for li in tri.loops]
            colour=tuple(ca.data[tri.loops[0]].color[:3]) if ca else None
            if not lining:
                record=[(point,Vector((uv[li].uv.x*2048,(1-uv[li].uv.y)*2048))) for point,li in zip(pts,tri.loops)]
                fragments=[record]
                for p in self.panels:
                    if not self.eligible(p,pts,False):continue
                    bounds=[(min(q[k] for q in p['_polygon']),max(q[k] for q in p['_polygon'])) for k in (0,1)]
                    if any(max(q[1][k] for q in record)<bounds[k][0] or min(q[1][k] for q in record)>bounds[k][1] for k in (0,1)):continue
                    fresh=[]
                    for frag in fragments:
                        outside,inside=subtract(frag,p['_polygon']);fresh.extend(outside)
                        if inside:pieces[p['id']].append({'points':[q[0] for q in inside],'uv':[(q[1].x/2048,1-q[1].y/2048) for q in inside],'color':colour})
                    fragments=fresh
                kept.extend({'points':[q[0] for q in f],'uv':[(q[1].x/2048,1-q[1].y/2048) for q in f],'color':colour} for f in fragments)
            else:
                # Lining UVs are not photographic; classify it with the matching
                # geometric projection, retaining its existing vertex colours.
                fragments=[pts]
                for p in self.panels:
                    if not self.eligible(p,pts,True):continue
                    project=self.projectors['side' if 'side_sign' in p else 'rear']
                    fresh=[]
                    for points in fragments:
                        record=[(v,Vector(project(v))) for v in points]
                        outside,inside=subtract(record,p['_polygon'])
                        fresh.extend([[q[0] for q in f] for f in outside])
                        if inside:pieces[p['id']].append({'points':[q[0] for q in inside],'color':colour})
                    fragments=fresh
                kept.extend({'points':f,'color':colour} for f in fragments)
        material=mesh.materials[0]
        replacement=self.make('Temporary_operation_shell',kept,material,obj.parent,role=1 if lining else 0)
        old=obj.data;obj.data=replacement.data;bpy.data.objects.remove(replacement,do_unlink=True)
        obj.matrix_world=Matrix.Identity(4)
        if old.users==0:bpy.data.meshes.remove(old)
        return pieces

    def move_to_pivot(self,obj,p):
        if obj is None:return
        matrix=obj.matrix_world.copy();pivot=Vector(p['pivot'])
        obj.data.transform(Matrix.Translation(-pivot)@matrix)
        obj.parent=self.pivots[p['id']];obj.matrix_parent_inverse=Matrix.Identity(4);obj.matrix_basis=Matrix.Identity(4)
        obj['moving_panel']=p['id'];self.owned[p['id']].append(obj)

    def offset(self,p,v):
        depth=p['thickness']
        if 'side_sign' in p:
            t=max(0,min(1,(1.30-v.z)/.08));depth+=(p.get('lower_thickness',depth)-depth)*t
            return Vector((0,-p['side_sign']*depth,0))
        if p['id']=='tailgate':return Vector((depth,0,0))
        return Vector((0,0,-depth))

    def on_edge(self,uvp,uvq,polygon):
        for a,b in zip(polygon,polygon[1:]+polygon[:1]):
            e=Vector(b)-Vector(a)
            if e.length<1e-8:continue
            ds=[abs(e.x*(q.y-a[1])-e.y*(q.x-a[0]))/e.length for q in (uvp,uvq)]
            if max(ds)<.015:return True
        return False

    def build_panels(self):
        outer=self.partition(self.body)
        liner=next(o for o in self.interior.parts if o.name=='Interior_Headliner_and_Pillars')
        inner=self.partition(liner,True)
        jamb=[]
        for p in self.panels:
            records=outer[p['id']]
            if not records:raise ValueError('No outer geometry extracted for '+p['id'])
            paint=self.make('Panel_'+p['id']+'_Outer',records,self.body.data.materials[0]);self.move_to_pivot(paint,p)
            backing=[]
            for r in records:
                pts=r['points'];backing.append({'points':list(reversed([v+self.offset(p,v) for v in pts])),'color':self.interior.color('trim')})
                uvpixels=[Vector((q[0]*2048,(1-q[1])*2048)) for q in r['uv']]
                polygons=[p['_polygon']]
                if p['glass']:
                    window=next(w for w in self.interior.c['windows'] if 'Glass_'+w['name']==p['glass'])
                    polygons.append(normalized_polygon(window['polygon_px']))
                for i,(v,w) in enumerate(zip(pts,pts[1:]+pts[:1])):
                    qv,qw=uvpixels[i],uvpixels[(i+1)%len(pts)]
                    if not any(self.on_edge(qv,qw,poly) for poly in polygons):continue
                    backing.append({'points':[v,w,w+self.offset(p,w),v+self.offset(p,v)],'color':self.interior.color('pillar')})
                    if self.on_edge(qv,qw,p['_polygon']):
                        inset=self.offset(p,v).normalized()*.065
                        jamb.append({'points':[v,w,w+inset,v+inset],'color':self.interior.color('pillar')})
            backing.extend(inner[p['id']])
            skin=self.make('Panel_'+p['id']+'_Inner_and_Edges',backing,self.interior.mat,role=4);self.move_to_pivot(skin,p)
            if p['glass']:self.move_to_pivot(bpy.data.objects[p['glass']],p)
            for name in p['attachments']:
                obj=bpy.data.objects.get(name)
                if obj is None:raise ValueError('Missing panel attachment '+name)
                self.move_to_pivot(obj,p)
            for name in p['interior_parts']:
                obj=bpy.data.objects.get(name)
                if obj is None:raise ValueError('Missing moving trim '+name)
                if name.startswith('Interior_Door_Panel'):
                    obj.location.x=.03;obj.scale.x*=.94/1.08
                if name=='Interior_Tailgate_Inside':obj.location.x=-1.747
                bpy.context.view_layer.update()
                self.interior.parts.remove(obj);self.move_to_pivot(obj,p)
            self.report['panels'].append({'id':p['id'],'node':p['node'],'outer_fragments':len(records),
                'inner_and_edge_faces':len(backing),'children':len(self.owned[p['id']]),'pivot_m':p['pivot'],
                'axis_blender':p['axis'],'maximum_degrees':p['open_degrees']})
        frame=self.make('Interior_Opening_Jambs',jamb,self.interior.mat,role=4);self.interior.parts.append(frame)
        # Real sills keep the door apertures connected to the interior floor.
        for sy in (-1,1):self.interior.box('Door_Sill_'+str(sy),(.03,sy*.78,.585),(.98,.19,.07),'trim',.014,role=4)

    def exposed_bays(self):
        b=self.interior
        b.box('Engine_Bay_Floor',(1.08,0,.725),(.95,1.37,.055),'trim',.015,role=4)
        b.box('Engine_Block',(1.02,0,.865),(.57,.44,.26),'metal',.035,role=4)
        b.box('Valve_Cover',(1.02,0,1.012),(.48,.33,.045),'trim',.015,role=4)
        b.box('Battery',(.82,-.49,.88),(.26,.23,.20),'instrument',.012,role=4)
        b.box('Battery_Top',(.82,-.49,.985),(.26,.23,.018),'trim',.006,role=4)
        b.box('Radiator',(1.47,0,.85),(.055,.95,.28),'instrument',.012,role=4)
        for y in (-.44,.44):b.rod('Engine_Hose',(.92,y*.5,.98),(1.43,y,.94),.025,'trim',10,4)
        b.rod('Air_Filter',(.86,.29,1.018),(.86,.29,1.065),.145,'trim',24,4)
        b.box('Cargo_Tray',(-1.49,0,.80),(.35,1.26,.04),'carpet',.01,role=4)
        self.report['exposed_bays']='Simple engine block, filter, battery, radiator, hoses and cargo tray; approximate display geometry.'

    def light_material(self,key):
        cfg=self.config['lights']['groups'][key]
        mat=self.body.data.materials[0].copy();mat.name=cfg['material']
        bs=mat.node_tree.nodes.get('Principled BSDF')
        bs.inputs['Emission Color'].default_value=(*cfg['color'],1);bs.inputs['Emission Strength'].default_value=0
        mat['light_group']=key;mat['off_strength']=0
        return mat

    def build_lights(self):
        mats={key:self.light_material(key) for key in self.config['lights']['groups']}
        records={k:[] for k in mats}
        # Use real shallow lamp meshes on top of the existing photographic lens
        # outlines. UVs preserve the original lens detail when unlit.
        def patch(key,points,projection):
            records[key].append({'points':[Vector(p) for p in points],'uv':[(u/2048,1-v/2048) for u,v in map(self.projectors[projection],points)]})
        for sy in (-1,1):
            y=sy*.674;z=.821;key='indicator_left' if sy<0 else 'indicator_right'
            for i in range(40):
                a=i*math.tau/40;b=(i+1)*math.tau/40
                patch('headlights',[(1.653,y,z),(1.644,y+.101*math.cos(a),z+.101*math.sin(a)),(1.644,y+.101*math.cos(b),z+.101*math.sin(b))],'front')
            # Front upper indicators, with source atlas coordinates unchanged.
            yc=sy*.674;zc=1.034;w=.19;h=.062
            patch(key,[(1.624,yc-w/2,zc-h/2),(1.624,yc+w/2,zc-h/2),(1.624,yc+w/2,zc+h/2),(1.624,yc-w/2,zc+h/2)],'front')
            # Rear clusters: the long red portion, outer amber and inner white.
            # Looking rearward, image-left corresponds to positive Blender Y.
            for group,uc,vc,wp,hp in [('tail_brake',1124 if sy>0 else 1341,789,48,19),
                                     (key,1082 if sy>0 else 1386,789,22,18),
                                     ('reverse',1088 if sy>0 else 1377,805,30,12)]:
                s=2.2/501;yc=-(uc-1233)*s*419/418;zc=(990-vc)*s*411/408;w=wp*s;h=hp*s
                patch(group,[(-1.803,yc-w/2,zc-h/2),(-1.803,yc+w/2,zc-h/2),(-1.803,yc+w/2,zc+h/2),(-1.803,yc-w/2,zc+h/2)],'rear')
            # Front side marker follows the fixed wing, never the opening door.
            x=(833-500.5)*2.2/501;z=(991-762)*2.2/501
            patch(key,[(x-.045,sy*.915,z-.017),(x+.045,sy*.915,z-.017),(x+.045,sy*.915,z+.017),(x-.045,sy*.915,z+.017)],'side')
        for key,faces in records.items():
            obj=self.make('Lamps_'+key,faces,mats[key]);obj['light_group']=key
            self.report['lights'].append({'group':key,'node':obj.name,'material':mats[key].name,'faces':len(faces)})
        for anchor in self.config['lights']['beam_anchors']:
            obj=bpy.data.objects.new(anchor['node'],None);self.collection.objects.link(obj);obj.parent=self.root;obj.location=anchor['position']
            obj['purpose']='Optional runtime headlight spotlight anchor; +X forward.'
        self.materials=mats

    def animate(self):
        a=self.config['animation'];scene=bpy.context.scene;scene.render.fps=a['fps'];scene.frame_start=a['closed_frame'];scene.frame_end=a['end_frame']
        for p in self.panels:
            obj=self.pivots[p['id']];obj.rotation_mode='XYZ';obj.animation_data_create()
            action=bpy.data.actions.new('Motion_'+p['id']);obj.animation_data.action=action
            axis=Vector(p['axis'])
            for frame,fraction in [(a['closed_frame'],0),(a['open_frame'],1),(a['hold_frame'],1),(a['end_frame'],0)]:
                obj.rotation_euler=axis*math.radians(p['open_degrees'])*fraction
                obj.keyframe_insert('rotation_euler',frame=frame,group=p['id'])
        scene.frame_set(a['closed_frame']);bpy.context.view_layer.update()
        self.report['animation']={'name':a['name'],'frames':[a['closed_frame'],a['open_frame'],a['hold_frame'],a['end_frame']],'fps':a['fps']}
        self.root['operable_panels']=[p['node'] for p in self.panels]
        self.root['light_materials']={k:v['material'] for k,v in self.config['lights']['groups'].items()}

    def finalize(self):
        # Consolidate each panel by material, retaining the single hinge parent.
        for p in self.panels:
            groups={}
            for obj in self.owned[p['id']]:
                material=obj.data.materials[0];groups.setdefault(material.name,[]).append(obj)
            for i,objects in enumerate(groups.values()):
                bpy.ops.object.select_all(action='DESELECT')
                for o in objects:o.select_set(True)
                bpy.context.view_layer.objects.active=objects[0]
                if len(objects)>1:bpy.ops.object.join()
                if objects[0].data.materials[0]!=self.interior.glass:
                    objects[0].name='Panel_'+p['id']+'_'+str(i)
                objects[0]['moving_panel']=p['id']
        self.animate()
        clean={k:v for k,v in self.config.items()}
        clean['panels']=[{k:v for k,v in p.items() if not k.startswith('_')} for p in self.panels]
        (self.output/'vehicle_controls.json').write_text(json.dumps(clean,indent=2))
        (self.output/'source/operations_build_report.json').write_text(json.dumps(self.report,indent=2))

def make_operable(body,interior,collection,root,output,projectors):
    op=Operations(body,interior,collection,root,output,projectors)
    op.build_panels();op.exposed_bays();op.build_lights();op.finalize()
    return op
