"""Render the saved final asset, plus cockpit and roof-removed inspection views."""
from pathlib import Path
import bpy,json,bmesh,sys
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'Niva_2121.blend'))
scene=bpy.context.scene;cam=scene.camera;ground=bpy.data.objects.get('Studio_Ground')
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
def render(name,loc,target=(0,0,.9),scale=5.8,size=(1440,1040),perspective=False):
    cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='PERSP' if perspective else 'ORTHO';cam.data.ortho_scale=scale;cam.data.lens=23
    scene.render.resolution_x,scene.render.resolution_y=size;scene.render.resolution_percentage=100
    scene.render.filepath=str(ROOT/'previews'/name);bpy.ops.render.render(write_still=True)
if '--detail-only' not in sys.argv:
    render('front_three_quarter.png',(5,-7,3.1))
    render('rear_three_quarter.png',(-5,-7,3.1))
    render('through_side_windows.png',(.15,-6,2.2),(-.35,0,1.05),4.0)
inspection_data=bpy.data.lights.new('Temporary cabin inspection fill','POINT');inspection_data.energy=12;inspection_data.shadow_soft_size=.25
inspection=bpy.data.objects.new('Temporary cabin inspection fill',inspection_data);bpy.context.collection.objects.link(inspection);inspection.location=(-.25,0,1.43)
render('driver_cockpit.png',(-.28,-.39,1.43),(1.5,-.33,1.33),perspective=True)
render('inside_roof_and_pillars.png',(.16,-.12,1.31),(-1.25,.04,1.52),perspective=True)
bpy.data.objects.remove(inspection,do_unlink=True)
if '--detail-only' in sys.argv:
    print('INTERIOR_DETAIL_RENDERS_COMPLETE');raise SystemExit(0)
# A clearly labelled cutaway is inspection evidence, never the exported model.
body=bpy.data.objects['Niva_Body_Static'];interior=bpy.data.objects['Niva_Interior_Static']
body.hide_render=True
glass=[o for o in bpy.data.collections['NIVA_LOD0'].objects if o.name.startswith('Glass_')]
for obj in glass:obj.hide_render=True
temporary=interior.copy();temporary.data=interior.data.copy();bpy.context.collection.objects.link(temporary)
bm=bmesh.new();bm.from_mesh(temporary.data);role=bm.faces.layers.int.get('interior_role')
if role:bmesh.ops.delete(bm,geom=[f for f in bm.faces if f[role]==1],context='FACES')
bm.to_mesh(temporary.data);bm.free();interior.hide_render=True
render('interior_cutaway.png',(-3,-4,4),(-.40,0,1.0),4.15)
bpy.data.objects.remove(temporary,do_unlink=True);interior.hide_render=False;body.hide_render=False
for obj in glass:obj.hide_render=False
# Actual transparent-glass views, plus separate opaque occupancy masks used for
# silhouette comparisons so transparency is not confused with missing geometry.
scene.render.film_transparent=True;ground.hide_render=True
mask=bpy.data.materials.new('Inspection silhouette occupancy');mask.use_nodes=True
bs=mask.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(1,1,1,1)
views=[('side',(0,-8,.91),4.25,(1536,768),(0,0,.91)),('front',(8,0,.91),2.30,(900,900),(0,0,.91)),
       ('rear',(-8,0,.91),2.30,(900,900),(0,0,.91)),('top',(0,0,8),4.25,(1536,900),(0,0,0))]
for name,loc,scale,size,target in views:
    render(name+'_ortho.png',loc,target,scale,size)
    scene.view_layers[0].material_override=mask;scene.cycles.samples=1
    render(name+'_occupancy.png',loc,target,scale,size)
    scene.view_layers[0].material_override=None;scene.cycles.samples=24
ground.hide_render=False;scene.render.film_transparent=False
print('INTERIOR_RENDERS_COMPLETE')
