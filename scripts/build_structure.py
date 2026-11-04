from pathlib import Path
import json,math
root=Path(__file__).resolve().parents[1]
stations=[(-1.72,1.20,.70,60),(-1.15,1.78,.72,160),(-.40,1.78,.72,290),(.45,1.25,.72,250),(.90,1.10,.70,100),(1.35,1.03,.72,50),(1.80,.97,.80,25)]
nodes=[];links=[];pairs=set()
def node(name,pos,mass,radius=.035,group='body'):
 i=len(nodes);nodes.append(dict(name=name,position=pos,mass_kg=mass,radius_m=radius,group=group));return i
def link(a,b,kind,k,y,cap=.22,tension=.12,damping=800):
 key=tuple(sorted([a,b]))
 if key in pairs:return
 pairs.add(key);links.append(dict(a=a,b=b,kind=kind,stiffness_n_per_m=k,yield_n=y,max_compression=cap,max_extension=tension,damping_ns_per_m=damping))
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
wheels=[]
for front,x,s in [(False,-1.10,1),(True,1.10,4)]:
 for side in [-1,1]:
  w=node(('front' if front else 'rear')+'_wheel_'+str(side),[x,.390,side*.795],20,.390,'wheel');wheels.append(w)
  j=0 if side<0 else 1
  for target in [s*4+j,s*4+j+2,(s+1)*4+j]:link(w,target,'suspension',130000,36000,.45,.45,1400)
cfg=dict(schema_version=2,mass_kg=sum(n['mass_kg']for n in nodes),enforce_symmetry=True,fixed_step_s=1/480,iterations=8,gravity_mps2=9.81,hardening=0.35,nodes=nodes,links=links,station_x=[s[0]for s in stations],station_top_y=[s[1]for s in stations],station_half_width=[s[2]for s in stations],engine_nodes=engine,wheel_nodes=wheels,aux_roof_nodes=roof,description='Controlled static-wall structural bench. Mass-bearing nodes and elastic/plastic XPBD links own all car motion. Godot renders the same graph through native skeletal skinning; no second rigid chassis receives the impact.',limits='Approximate structure and game material parameters, not factory crash certification. Analytic wall/floor contacts, no tearing, glass particles, general world integration or panel self-contact.')
(root/'structure.json').write_text(json.dumps(cfg,indent=2)+'\n')
print(len(nodes),'nodes',len(links),'links',cfg['mass_kg'],'kg')
