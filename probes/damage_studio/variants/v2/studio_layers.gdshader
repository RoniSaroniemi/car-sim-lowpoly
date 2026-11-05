shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_map : hint_default_white, filter_linear_mipmap;
uniform vec4 tint : source_color=vec4(1.0);
uniform bool has_albedo=false;
uniform bool has_normal=false;
uniform bool has_roughness=false;
uniform bool vertex_tint=false;
uniform bool damage_enabled=true;
uniform bool normal_layer=true;
uniform bool paint_layer=true;
uniform bool roughness_layer=true;
uniform bool section_folds=true;
uniform bool masks_debug=false;
uniform float paint_loss=1.;
uniform float loss_threshold=0.;
uniform float pattern_scale=1.;
uniform float crease_strength=1.;
uniform float crease_scale=1.;
uniform float fold_strength=1.;
uniform float metal_roughness=.53;
uniform float metal_shine=.72;
uniform float scuff_strength=.65;
uniform float peel_strength=1.;
uniform float grime_amount=.28;
uniform float grime_trail=.10;
uniform float trail_direction=-1.;
uniform vec4 primer_color : source_color=vec4(.30,.32,.30,1.);
uniform vec4 metal_color : source_color=vec4(.56,.58,.61,1.);
uniform int view_mode=2;
uniform float roughness_value=.75;
uniform float metallic_value=0.;
uniform float node_damage[38];
uniform float node_contact[38];
uniform float node_compression[38];
uniform float section_height[7];
uniform float section_width[7];
uniform float plastic_sections[7];
uniform float contact_sections[7];
uniform vec3 collision_direction=vec3(1,0,0);
varying vec3 rest_position;
varying vec3 rest_normal;
varying vec3 damage_field;
varying float panel_mask;
varying float section_damage;
float station_x(int i){
 if(i==0)return -1.72;if(i==1)return -1.15;if(i==2)return -.40;
 if(i==3)return .45;if(i==4)return .90;if(i==5)return 1.35;return 1.80;
}
float hash31(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float noise3(vec3 p){
 vec3 i=floor(p);vec3 f=fract(p);f=f*f*(3.-2.*f);
 return mix(mix(mix(hash31(i),hash31(i+vec3(1,0,0)),f.x),mix(hash31(i+vec3(0,1,0)),hash31(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash31(i+vec3(0,0,1)),hash31(i+vec3(1,0,1)),f.x),mix(hash31(i+vec3(0,1,1)),hash31(i+vec3(1,1,1)),f.x),f.y),f.z);
}
// A jittered cell network: intersecting straight folds with unequal face sizes.
// Rest-space projection keeps both sides independent and the creases attached.
vec2 panel_uv(vec3 p,vec3 n){
 vec3 a=abs(n);
 if(a.y>=a.x && a.y>=a.z)return p.xz;
 if(a.z>=a.x)return p.xy;
 return p.zy;
}
vec3 cell_field(vec2 q){
 vec2 grid=floor(q),f=fract(q);
 float first=100.,second=100.,seed=0.;
 for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){
  vec2 cell=grid+vec2(float(x),float(y));
  vec2 jitter=vec2(hash31(vec3(cell,1.7)),hash31(vec3(cell,8.3)));
  vec2 delta=vec2(float(x),float(y))+.12+.76*jitter-f;
  float d=dot(delta,delta);
  if(d<first){second=first;first=d;seed=hash31(vec3(cell,31.));}
  else if(d<second)second=d;
 }
 return vec3(second-first,first,seed);
}
vec3 folds(vec3 p,vec3 n){
 vec2 q=panel_uv(p,n)*(2.6*sqrt(crease_scale));
 q+=vec2(noise3(p*1.7),noise3(p*1.7+vec3(17.)))*.30;
 return cell_field(q);
}
float relief(vec3 f){
 // Faceted planes meet at vertices; no sinusoidal parallel corrugation.
 float gap=min(f.x,.62);
 return gap*(.35+f.z*.65)*(f.z>.47?1.:-1.);
}
void vertex(){
 rest_position=CUSTOM0.xyz;rest_normal=CUSTOM1.xyz;
 panel_mask=COLOR.a;
 int s=0;for(int i=0;i<6;i++){if(rest_position.x>=station_x(i))s=i;}
 float tx=clamp((rest_position.x-station_x(s))/(station_x(s+1)-station_x(s)),0.,1.);
 section_damage=mix(plastic_sections[s],plastic_sections[s+1],tx);
 damage_field=vec3(0);
 for(int q=0;q<2;q++){
  int station=s+q;
  float ty=clamp((rest_position.y-.58)/(section_height[station]-.58),0.,1.);
  float tz=clamp((rest_position.z+section_width[station])/(2.*section_width[station]),0.,1.);
  for(int j=0;j<4;j++){
   float w=(q==1?tx:1.-tx)*(j>=2?ty:1.-ty)*(j%2==1?tz:1.-tz);
   int id=station*4+j;
   damage_field+=vec3(node_damage[id],node_contact[id],node_compression[id])*w;
  }
 }
 if(damage_enabled&&section_folds){
  vec3 facet=folds(rest_position,rest_normal);
  float envelope=smoothstep(.01,.23,max(section_damage,damage_field.z))*panel_mask;
  // Keep the cosmetic skin outside the inner liner; do not create fake ruptures.
  float h=clamp(.028*fold_strength*(relief(facet)+.62)*envelope,0.,.032);
  VERTEX+=NORMAL*h;
 }
}
void fragment(){
 vec3 base=tint.rgb;
 if(has_albedo)base*=texture(albedo_map,UV).rgb;
 if(vertex_tint)base*=COLOR.rgb;
 ALBEDO=view_mode==1?vec3(.56,.59,.60):base;
 ROUGHNESS=roughness_value*(has_roughness?texture(roughness_map,UV).g:1.);
 METALLIC=metallic_value;
 vec3 n=has_normal?normalize(texture(normal_map,UV).xyz*2.-1.):vec3(0,0,1);
 if(view_mode==1)n=vec3(0,0,1);
 if(damage_enabled&&max(damage_field.x,damage_field.y)>.0001){
  float paint_id=smoothstep(.008,.038,base.g-base.r)*smoothstep(.012,.07,base.g-base.b);
  float eligible=panel_mask*paint_id;
  float plastic=clamp(damage_field.x,0.,1.);
  float crush=smoothstep(.025,.32,damage_field.z);
  float severe=max(smoothstep(.12,.40,damage_field.z),smoothstep(.22,.55,section_damage))*plastic;
  float facing=smoothstep(.05,.6,dot(normalize(rest_normal),normalize(collision_direction)));
  float touched=smoothstep(.025,.65,damage_field.y)*facing;
  float grain=noise3(rest_position*95.+vec3(19.1,7.3,11.));
  float patch=noise3(rest_position*pattern_scale*9.+vec3(3,17,7));
  vec3 facet=folds(rest_position,rest_normal);
  vec2 q=panel_uv(rest_position,rest_normal);
  // Shallow rubbed paint stays body-coloured, lighter and much less glossy.
  float rubbed=touched*(.38+.62*plastic)*(.55+.45*patch);
  float scuff=clamp(rubbed*scuff_strength,0.,1.)*eligible;
  // Narrow directional gouges, broken into short uneven segments.
  float streak=abs(noise3(vec3(q.x*5.,q.y*85.,rest_position.z*3.)*pattern_scale)-.5);
  float broken=smoothstep(.42,.67,noise3(rest_position*vec3(5,8,6)+vec3(5,1,7)));
  float severity=max(touched*(.22+.78*plastic),severe*.85)*paint_loss;
  float activation=smoothstep(.22+loss_threshold,.65+loss_threshold,severity);
  float width=.006+.023*activation;
  float fold_cut=(facet.x-(.014+.026*activation))/.65;
  float scratch_cut=(streak-width);
  // Select only sparse contact gouges or highly strained fold edges.
  float selected_fold=smoothstep(.18,.65,severe)*smoothstep(.44,.64,patch);
  float cut=min(mix(.3,scratch_cut,touched*broken),mix(.3,fold_cut,selected_fold));
  float aa=max(fwidth(cut),.0015);
  float metal=(1.-smoothstep(-aa,aa,cut))*activation*eligible;
  // A thin primer fringe and lifted paint lip; not a large grey halo.
  float primer=(1.-smoothstep(.014-aa,.014+aa,cut))*activation*eligible;
  float lip=(1.-smoothstep(.010,.038,abs(cut-.012)))*activation*eligible;
  // Directional residue: thin at the leading edge, smeared behind the gouge.
  vec3 surface_n=normalize(rest_normal);
  vec3 trail_tangent=vec3(trail_direction,0,0);
  trail_tangent-=surface_n*dot(surface_n,trail_tangent);
  if(length(trail_tangent)<.15)trail_tangent=vec3(0,-1,0);
  vec3 trail_point=rest_position-normalize(trail_tangent)*grime_trail;
  vec2 tq=panel_uv(trail_point,rest_normal);
  float trail_streak=abs(noise3(vec3(tq.x*5.,tq.y*85.,trail_point.z*3.)*pattern_scale)-.5);
  float trail_mask=(1.-smoothstep(.025,.12,trail_streak))*touched;
  float residue=grime_amount*eligible*clamp(trail_mask*(.4+.6*patch)+rubbed*.32,0.,1.)*(1.-metal*.85);
  if(paint_layer&&view_mode==2){
   vec3 scuffed_paint=clamp(base*1.32+vec3(.025,.029,.018),vec3(0),vec3(1));
   ALBEDO=mix(ALBEDO,scuffed_paint,scuff);
   ALBEDO=mix(ALBEDO,primer_color.rgb,primer*.92);
   ALBEDO=mix(ALBEDO,metal_color.rgb*(.92+.16*grain),metal);
   ALBEDO=mix(ALBEDO,base*1.4+vec3(.035),lip*.28*peel_strength);
   ALBEDO=mix(ALBEDO,vec3(.095,.079,.056),residue);
   METALLIC=mix(METALLIC,metal_shine,metal);
  }
  if(roughness_layer){
   ROUGHNESS=mix(ROUGHNESS,max(ROUGHNESS,.82),scuff);
   ROUGHNESS=mix(ROUGHNESS,metal_roughness+.10*(grain-.5),metal);
   ROUGHNESS=mix(ROUGHNESS,.92,residue);
  }
  if(normal_layer){
   float h=relief(facet)*.010*crease_strength*crush*eligible;
   h+=(grain-.5)*.00025*crush;
   h+=lip*.0012*peel_strength;
   h-=metal*.00045;
   // Surface gradients are evaluated after native skinning.
   vec3 sigma_s=dFdx(VERTEX),sigma_t=dFdy(VERTEX);
   vec3 r1=cross(sigma_t,NORMAL),r2=cross(NORMAL,sigma_s);
   float det=dot(sigma_s,r1);
   vec3 gradient=sign(det)*(dFdx(h)*r1+dFdy(h)*r2);
   vec3 perturbed=NORMAL;
   if(abs(det)>1e-10)perturbed=normalize(abs(det)*NORMAL-gradient);
   vec3 detail=normalize(vec3(dot(perturbed,TANGENT),dot(perturbed,BINORMAL),dot(perturbed,NORMAL)));
   vec3 t=n+vec3(0,0,1);vec3 u=detail*vec3(-1,-1,1);
   n=normalize(t*dot(t,u)/max(t.z,.001)-u);
  }
  if(masks_debug){ALBEDO=vec3(metal,scuff,residue);ROUGHNESS=.85;METALLIC=0.;n=vec3(0,0,1);}
 }
 NORMAL_MAP=n*.5+.5;NORMAL_MAP_DEPTH=1.;
}
