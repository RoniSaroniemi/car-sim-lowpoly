from pathlib import Path
import json,math,argparse
parser=argparse.ArgumentParser()
profiles=parser.add_mutually_exclusive_group()
profiles.add_argument('--multiaxis-live',action='store_true',help='Write the promoted material profile to its compatibility alias path')
profiles.add_argument('--baseline-materials',action='store_true',help='Write the original front-bench materials for comparison')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
stations=[(-1.72,1.20,.70,60),(-1.15,1.78,.72,160),(-.40,1.78,.72,290),(.45,1.25,.72,250),(.90,1.10,.70,100),(1.35,1.03,.72,50),(1.80,.97,.80,25)]
nodes=[];links=[];pairs=set()
def node(name,pos,mass,radius=.035,group='body'):
 i=len(nodes);nodes.append(dict(name=name,position=pos,mass_kg=mass,radius_m=radius,group=group));return i
def link(a,b,kind,k,y,cap=.22,tension=.12,damping=800,**extra):
 key=tuple(sorted([a,b]))
 if key in pairs:return
 pairs.add(key);links.append(dict(a=a,b=b,kind=kind,stiffness_n_per_m=k,yield_n=y,max_compression=cap,max_extension=tension,damping_ns_per_m=damping,**extra))
for si,(x,top,w,mass) in enumerate(stations):
 for high in [False,True]:
  for side in [-1,1]:
   # Small symmetrical initial curvature encourages predictable rail folding.
   yy=(top-(.006 if si==2 else 0)) if high else .58+(0.006 if si in [2,5] else 0)
   node(f's{si}_{"roof" if high else "floor"}_{side}',[x,yy,side*w],mass*(.08 if high else .42))
for s in range(7):
 a=s*4
 for i,j in [(0,1),(2,3),(0,2),(1,3),(0,3),(1,2)]:
  link(a+i,a+j,'ring',2.4e6,110000 if s<4 else 70000,.12,.08,1800)
for s in range(6):
 front=s>=3
 for j in range(4):
  kind='front_rail' if front and j<2 else ('upper_front' if front else ('sill' if j<2 else 'roof'))
  y=(95000 if j<2 else 26000) if front else (60000 if j<2 else 35000)
  link(s*4+j,(s+1)*4+j,kind,3e6,y,(.15 if front else .30) if j<2 else .30,.14,1100)
 for i,j in [(0,1),(1,0),(2,3),(3,2),(0,2),(2,0),(1,3),(3,1)]:
  link(s*4+i,(s+1)*4+j,'front_brace' if front else 'cabin_brace',180000 if front else 450000,7000 if front else 14000,.65,.40,300)
for s in range(5):
 for j in range(4):
  link(s*4+j,(s+2)*4+j,'bend',100000,5000 if s>=3 else 12000,.65,.25,200)
roof=[]
for side in [-1,1]:
 r=node('A_pillar_roof_'+str(side),[.12,1.78,side*.67],2.5,group='roof');roof.append(r)
 j=0 if side<0 else 1
 for p in [3*4+j,3*4+j+2,2*4+j+2,2*4+j]:link(r,p,'pillar',1.8e6,30000,.30,.20,1000)
link(roof[0],roof[1],'roof_crossmember',2.4e6,120000,.15,.10,1200)
engine=[]
for i,p in enumerate([[.735,.75,-.22],[.735,.75,.22],[1.305,.75,0],[1.02,1.02,0]]):engine.append(node('engine_'+str(i),p,47.5,.045,'engine'))
for i,a in enumerate(engine):
 for b in engine[i+1:]:link(a,b,'engine_rigid',1e9,1e12,0,0,12000)
for a,targets in zip(engine,[[12,16,20],[13,17,21],[20,21,22,23],[18,19,22,23]]):
 for b in targets:link(a,b,'engine_mount',200000,20000,.60,.60,900)
wheels=[];assemblies=[]
for front,x,s in [(False,-1.10,1),(True,1.10,4)]:
 for side in [-1,1]:
  w=node(('front' if front else 'rear')+'_wheel_'+str(side),[x,.390,side*.795],20,.390,'wheel');wheels.append(w)
  j=0 if side<0 else 1
  # Four hub hardpoints. Hub orientation is separate from freely rotating rim.
  targets=[s*4+j,(s+1)*4+j,s*4+j+2,(s-1)*4+j]
  anchors=[[-.11,-.045,-side*.045],[.11,-.045,-side*.045],[0,.13,-side*.045],[.14,.025,-side*.075]]
  for index,(target,anchor) in enumerate(zip(targets,anchors)):
   link(w,target,'steering_link' if index==3 else 'suspension',90000 if index==3 else 160000,14000 if index==3 else 26000,.38,.35,450,
        wheel_anchor=anchor,break_force_n=48000 if index==3 else 90000,break_delay_s=.035,break_plastic=.90)
  # Upper-arm support closes the otherwise free camber mechanism of a hub
  # represented by only four distance constraints (five non-spin freedoms).
  for target,anchor in [((s+1)*4+j+2,[.10,.18,-side*.07]),((s-1)*4+j+2,[-.10,.18,-side*.07])]:
   link(w,target,'upper_arm',350000,30000,.30,.25,600,wheel_anchor=anchor,break_force_n=110000,break_delay_s=.035,break_plastic=.90)
  # Only nearby load-bearing members; deliberately leave the wheel opening free.
  segments=([[8+j,12+j],[12+j,14+j],[18+j,22+j]] if front else [[j,j+2],[8+j,10+j],[2+j,6+j]])
  # Retain normal ramp landings; only sustained overload or catastrophic
  # permanent mount displacement releases the six supports as one assembly.
  assemblies.append(dict(node=w,radius_m=.390,rim_radius_m=.255,half_width_m=.105,max_tire_compression_m=.045,
                         contact_stiffness_n_per_m=320000,axle_body_nodes=[s*4,s*4+1,s*4+2,s*4+3],
                         knuckle_stiffness_nm_per_rad=24000,knuckle_yield_nm=6500,knuckle_break_nm=18000,
                         rigid_mount_until_yield=True,lateral_yield_n=18000,lateral_break_n=90000,
                         mount_break_delay_s=.035,detach_alignment_deg=65,detach_lateral_offset_m=.20,
                         body_capsules=[dict(a=a,b=b,radius_m=.045)for a,b in segments]))
# Promoted three-axis cabin materials, shared by live simulation and baking.
# The original front-bench profile remains explicitly reproducible for comparison.
if not args.baseline_materials:
 for raw in links:
  a,b=raw['a'],raw['b'];kind=raw['kind']
  if kind=='ring' and a//4<4:
   i,j=a%4,b%4
   if (i,j)==(2,3):values=('roof_ring',300000,12000,.55,.15,450)
   elif (i,j) in [(0,2),(1,3)]:values=('cabin_pillar',300000,8000,.70,.12,400)
   elif (i,j) in [(0,3),(1,2)]:values=('cabin_diagonal',100000,3500,.70,.25,200)
   else:continue
  elif kind=='roof':values=('roof',1400000,18000,.45,.14,750)
  elif kind=='cabin_brace' and (a%4,b%4) in [(0,2),(2,0),(1,3),(3,1)]:values=('cabin_roof_brace',120000,3000,.75,.40,220)
  elif kind=='cabin_brace' and (a%4,b%4) in [(2,3),(3,2)]:values=('cabin_roof_planar',180000,6000,.65,.40,250)
  elif kind=='pillar':values=('pillar',350000,8000,.65,.20,400)
  elif kind=='roof_crossmember':values=('roof_crossmember',500000,18000,.50,.15,450)
  else:continue
  for key,value in zip(('kind','stiffness_n_per_m','yield_n','max_compression','max_extension','damping_ns_per_m'),values):raw[key]=value

cfg=dict(schema_version=2,mass_kg=sum(n['mass_kg']for n in nodes),enforce_symmetry=True,fixed_step_s=1/480,iterations=8,gravity_mps2=9.81,hardening=0.35,nodes=nodes,links=links,station_x=[s[0]for s in stations],station_top_y=[s[1]for s in stations],station_half_width=[s[2]for s in stations],engine_nodes=engine,wheel_nodes=wheels,aux_roof_nodes=roof,description='Controlled static-wall structural bench. Mass-bearing nodes and elastic/plastic XPBD links own all car motion. Godot renders the same graph through native skeletal skinning; no second rigid chassis receives the impact.',limits='Approximate structure and game material parameters, not factory crash certification. Analytic wall/floor contacts, no tearing, glass particles, general world integration or panel self-contact.')
cfg.update(schema_version=3,wheel_assemblies=assemblies,limits='Approximate game structure, not certified crash prediction. Analytic static box/floor and selective wheel/body contacts; no general world integration, panel self-contact or tearing.')
output=root/('structures/niva_front_bench_baseline.json' if args.baseline_materials else ('structures/niva_multiaxis_live.json' if args.multiaxis_live else 'structure.json'))
output.parent.mkdir(parents=True,exist_ok=True)
if not args.baseline_materials:
 cfg['material_profile']='niva_multiaxis_v1'
 cfg['material_profile_version']=1
 cfg['description']='Three-axis game structure with yielding roof/pillar/side cabin members; shared live and baked crash material profile. Mass-bearing nodes and XPBD links own motion, without a duplicate chassis.'
output.write_text(json.dumps(cfg,indent=2)+'\n')
print(len(nodes),'nodes',len(links),'links',cfg['mass_kg'],'kg')
