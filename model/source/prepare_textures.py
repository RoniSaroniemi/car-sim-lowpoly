"""Prepare the model's UV atlas and PBR maps from the supplied reference.

This is texture authoring for a 3D asset; no generated reference views are used.
Run with regular Python (Pillow and numpy), before build_niva.py in Blender.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
N = 2048
source = Image.open(ROOT/'source/reference.png').convert('RGB')
atlas = Image.new('RGB', (N,N), (62,66,49))
atlas.paste(source, (0,0))
rough = Image.new('L',(N,N),145)
metal = Image.new('L',(N,N),16)
height = Image.new('L',(N,N),128)
rd, md, hd = ImageDraw.Draw(rough), ImageDraw.Draw(metal), ImageDraw.Draw(height)

# Opaque exterior glass keeps a coherent dark cabin in a game without a full
# interior. Original seat silhouettes and glazing detail remain in the atlas.
glass = Image.new('L',(N,N),0)
gd = ImageDraw.Draw(glass)
for poly in [
    [(232,617),(373,617),(374,692),(207,692)],
    [(412,617),(516,619),(526,627),(577,693),(412,693)],
    [(1118,98),(1351,98),(1378,176),(1089,176)],
    [(1119,614),(1350,614),(1366,685),(1105,685)],
    [(558,143),(600,127),(620,146),(620,390),(599,413),(558,395)],
    [(147,155),(171,162),(171,379),(148,389)],
]:
    gd.polygon(poly,fill=255)
glass = glass.filter(ImageFilter.GaussianBlur(.65))
a = np.asarray(atlas).astype(float)
g = np.asarray(glass).astype(float)[:,:,None]/255
dark = a*.39 + np.array([10,16,20])
atlas = Image.fromarray(np.uint8(a*(1-g)+dark*g))
rough.paste(58,(0,0),glass)
metal.paste(2,(0,0),glass)

# UV padding: extend neighboring foreground colors into the sheet's white
# background. Small cross-view silhouette disagreements must not put white
# triangles on pillars / arch returns. The source reference remains untouched.
for box in [(45,50,910,490),(40,565,930,1000),(980,45,1490,495),(980,565,1490,1000)]:
    tile=np.asarray(atlas.crop(box)).astype(float)
    white=(tile.min(axis=2)>205)&((tile.max(axis=2)-tile.min(axis=2))<26)
    external=Image.fromarray(np.where(white,0,255).astype('uint8')).copy()
    ImageDraw.floodfill(external,(0,0),128)
    known=np.asarray(external)!=128
    for _ in range(30):
        total=np.zeros_like(tile); count=np.zeros(tile.shape[:2],dtype=float)
        for axis,shift in [(0,1),(0,-1),(1,1),(1,-1)]:
            valid=np.roll(known,shift,axis=axis)
            if axis==0: valid[0 if shift==1 else -1,:]=False
            else: valid[:,0 if shift==1 else -1]=False
            total+=np.roll(tile,shift,axis=axis)*valid[:,:,None]; count+=valid
        new=(~known)&(count>0)
        tile[new]=total[new]/count[new,None]; known[new]=True
    atlas.paste(Image.fromarray(np.uint8(tile)),box[:2])

# A photographed arch can show the white studio through its far side. The game
# mesh has dark wheel-well returns, so those tiny background glimpses are dark.
arr=np.asarray(atlas).copy(); yy,xx=np.indices(arr.shape[:2])
for cx in (250,751):
    radius2=(xx-cx)**2+(yy-902)**2
    arch_region=(radius2<130**2)&(radius2>90**2)&(yy<902)&(yy>775)
    white=(arr.min(axis=2)>200)&((arr.max(axis=2)-arr.min(axis=2))<28)
    arr[arch_region&white]=(27,29,26)
atlas=Image.fromarray(arr)

# Front grille / rubber surrounds, chrome strips, and metal wheels.
rd.rectangle((1041,258,1425,325),fill=190)
rd.rectangle((1020,335,1448,363),fill=100)
md.rectangle((1045,337,1419,360),fill=185)
rd.rectangle((1025,831,1444,863),fill=108)
md.rectangle((1058,832,1410,858),fill=170)
for cx in (250,751):
    rd.ellipse((cx-89,813,cx+89,991),fill=210)
    rd.ellipse((cx-58,844,cx+58,960),fill=125)
    md.ellipse((cx-58,844,cx+58,960),fill=155)
for cx in (1080,1387):
    rd.ellipse((cx-25,267,cx+25,317),fill=65)
    md.ellipse((cx-25,267,cx+25,317),fill=30)

# Very restrained reference-derived surface relief. Most lighting is deliberately
# excluded from normal maps; small high frequency features receive the relief.
gray = source.convert('L')
gray_a = np.asarray(gray,dtype=float)
detail = gray_a - np.asarray(gray.filter(ImageFilter.GaussianBlur(1.5)),dtype=float)
harr = np.asarray(height).copy()
harr[:1024,:1536] = np.clip(128+detail*.24,112,144).astype('uint8')
height = Image.fromarray(harr)
hd = ImageDraw.Draw(height)

# Dedicated tyre tread strip: tangential coordinate left to right, cross-section
# down the strip. Raised chevrons are carried by the tangent-space normal map.
ad = ImageDraw.Draw(atlas)
ad.rectangle((0,1100,1535,1387),fill=(30,31,30))
rd.rectangle((0,1100,1535,1387),fill=221)
md.rectangle((0,1100,1535,1387),fill=0)
hd.rectangle((0,1100,1535,1387),fill=74)
for i in range(48):
    x=i*32
    for j in range(4):
        y=1104+j*70
        skew=12 if j<2 else -12
        poly=[(x+4,y+3),(x+25,y+3+skew),(x+29,y+53+skew),(x+8,y+53)]
        ad.polygon(poly,fill=(49+j%2*4,50+j%2*4,48+j%2*4))
        hd.polygon(poly,fill=175)

# Constant swatches, all inside the same atlas/material.
swatches = {
    'rubber': ((32,34,32),215,0),
    'undercarriage': ((31,32,30),195,75),
    'steel': ((141,145,140),99,225),
    'cream': ((174,166,132),128,140),
    'paint': ((111,124,61),116,22),
    'mirror': ((146,161,166),45,230),
    'black': ((9,12,12),177,0),
}
swatch_uv = {}
for i,(name,(color,r,m)) in enumerate(swatches.items()):
    box=(i*200+8,1460,i*200+191,1630)
    ad.rectangle(box,fill=color); rd.rectangle(box,fill=r); md.rectangle(box,fill=m)
    hd.rectangle(box,fill=128)
    swatch_uv[name]=[(box[0]+box[2])/2,(box[1]+box[3])/2]

# A rounded number plate patch is already in each photograph; no retyped badge
# or fictional registration is substituted.
atlas.save(ROOT/'textures/Niva_BaseColor.png')
rough.convert('RGB').save(ROOT/'textures/Niva_Roughness.png')
metal.convert('RGB').save(ROOT/'textures/Niva_Metallic.png')
orm = Image.merge('RGB',(Image.new('L',(N,N),255),rough,metal))
orm.save(ROOT/'textures/Niva_ORM.png')
h=np.asarray(height.filter(ImageFilter.GaussianBlur(.55)),dtype=float)/255
dy,dx=np.gradient(h)
normal=np.dstack((-dx*2.3,dy*2.3,np.ones_like(h)))
normal/=np.linalg.norm(normal,axis=2,keepdims=True)
Image.fromarray(np.uint8(np.clip((normal*.5+.5)*255,0,255))).save(ROOT/'textures/Niva_Normal.png')
(ROOT/'source/swatch_coordinates.json').write_text(json.dumps(swatch_uv,indent=2))

# Normalize all drawings into one pixel-per-unit coordinate system. Side view
# is the scale authority. Front sets width; rear matches height independently;
# top requires separate longitudinal and transverse scale factors.
S=2.2/501
transforms={
    'metres_per_master_pixel':S,
    'side': {'x_origin_px':500.5,'ground_y_px':991,'scale_x':1,'scale_y':1},
    'front': {'centre_x_px':1233.5,'ground_y_px':479,'scale_x':1,'scale_y':1},
    'rear': {'centre_x_px':1233,'ground_y_px':990,'scale_x':419/418,'scale_y':411/408},
    'top': {'bumper_rear_x_px':86,'bumper_rear_master_x_px':59,'centre_y_px':269.5,
            'scale_length':851/788,'scale_width':419/361,
            'extra_width_over_uniform_scale':(419/361)/(851/788)},
    'reason':'Side length/height and front width are authoritative; top is expanded independently on each axis. These reconcile artwork, not survey measurements.',
}
(ROOT/'source/reference_transforms.json').write_text(json.dumps(transforms,indent=2))

font_path='/System/Library/Fonts/Supplemental/Arial.ttf'
try:
    font=ImageFont.truetype(font_path,23); small=ImageFont.truetype(font_path,16)
except OSError:
    font=ImageFont.load_default(size=23); small=ImageFont.load_default(size=16)
sheet=Image.new('RGB',(1500,1120),(243,244,238)); d=ImageDraw.Draw(sheet)
d.text((35,24),'NIVA 2121 / NORMALIZED REFERENCE',font=font,fill=(26,35,28))
d.text((35,58),'Shared scale: side length + height; front width. Top axes corrected independently.',font=small,fill=(80,86,76))
boxes={'top':(45,50,910,490),'side':(40,565,930,1000),'front':(980,45,1490,495),'rear':(980,565,1490,1000)}
for name,origin in [('top',(30,120)),('side',(30,640)),('front',(980,120)),('rear',(980,640))]:
    im=source.crop(boxes[name]); sx=sy=1
    if name=='top': sx=851/788; sy=419/361
    if name=='rear': sx=419/418; sy=411/408
    im=im.resize((round(im.width*sx),round(im.height*sy)),Image.Resampling.LANCZOS)
    factor=min(920/im.width,440/im.height) if name in ('top','side') else min(480/im.width,440/im.height)
    im=im.resize((round(im.width*factor),round(im.height*factor)),Image.Resampling.LANCZOS)
    sheet.paste(im,origin)
    d.text((origin[0],origin[1]-30),name.upper()+ ('  x1.080 length / x1.161 width' if name=='top' else ''),font=small,fill=(36,50,36))
sheet.save(ROOT/'previews/normalized_reference.png')
print('Prepared 2048px base color, ORM, normal and standalone roughness / metallic maps.')
