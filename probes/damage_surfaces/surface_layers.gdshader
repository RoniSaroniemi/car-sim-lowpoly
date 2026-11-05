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
  float phase=rest_position.x*18.+rest_position.z*1.8;
  float envelope=sin(clamp((rest_position.x+1.8)/3.65,0.,1.)*PI);
  // Keep the original section-driven fold envelope, along post-skin surface N.
  VERTEX+=NORMAL*(.022*section_damage*panel_mask*pow(sin(phase),2.)*envelope);
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
  // Probe-only ID reconstruction for this olive atlas; production uses a paint ID.
  float paint_id=smoothstep(.008,.038,base.g-base.r)*smoothstep(.012,.07,base.g-base.b);
  float material_mask=panel_mask*paint_id;
  float plastic=clamp(damage_field.x,0.,1.)*material_mask;
  float crush=smoothstep(.025,.32,damage_field.z)*material_mask;
  float severe=max(smoothstep(.16,.43,damage_field.z),smoothstep(.24,.55,section_damage))*plastic;
  float facing=smoothstep(.05,.6,dot(normalize(rest_normal),normalize(collision_direction)));
  float touched=smoothstep(.04,.65,damage_field.y)*facing*material_mask;
  float grain=noise3(rest_position*75.+vec3(19.1,7.3,11.));
  float patch=noise3(rest_position*12.+vec3(3,17,7));
  float wear=touched*(.24+.76*plastic);
  // Two thresholds on one physical mask create chipped paint -> primer -> metal.
  float primer=smoothstep(.25,.60,wear+(.5-patch)*.42)*touched;
  float metal=smoothstep(.45,.78,wear+(.5-patch)*.38)*touched;
  // A small amount of coating flake on a severe buckle, distinct from scraping.
  float crease_noise=noise3(rest_position*vec3(13,6,8)+vec3(17,2,11));
  float coating_strain=smoothstep(.14,.38,damage_field.z)*smoothstep(.35,.75,plastic);
  float flake=smoothstep(.78,.93,grain)*smoothstep(.5,.8,patch)*coating_strain;
  primer=max(primer,flake*.6);metal=max(metal,flake*.35);
  // Larger jagged coating failure follows section folds; geometry owns the buckle.
  float fold_phase=rest_position.x*18.+rest_position.z*1.8;
  float phase_warp=(noise3(rest_position*vec3(5,8,11)+vec3(4,19,3))-.5)*3.5;
  float edge_field=pow(abs(cos(fold_phase*2.+phase_warp)),4.);
  float breakup=smoothstep(.27,.62,noise3(rest_position*vec3(6,7,11)+vec3(11,5,8)));
  float peeled=severe*clamp(edge_field*1.18*breakup+(.65-patch)*.60,0.,1.);
  float contact_strip=touched*plastic*(.7+.3*patch);
  float failure=max(peeled,contact_strip);
  primer=max(primer,smoothstep(.18,.42,failure));
  metal=max(metal,smoothstep(.34,.62,failure));
  float scrape_wave=abs(sin(dot(rest_position,vec3(3,89,67))+patch*4.));
  float filtered_width=max(.025,fwidth(scrape_wave));
  float scratches=(1.-smoothstep(.025,.025+filtered_width,scrape_wave))*touched*(.2+.8*plastic)*smoothstep(.35,.7,patch);
  metal=max(metal,scratches*.8);
  if(paint_layer&&view_mode==2){
   ALBEDO=mix(ALBEDO,mix(base,vec3(.43,.44,.40),.13),touched*.5);
   ALBEDO=mix(ALBEDO,vec3(.30,.32,.30),primer*.92);
   ALBEDO=mix(ALBEDO,vec3(.56,.58,.61)*( .88+.24*grain),metal);
   METALLIC=mix(METALLIC,.72,metal);
  }
  if(roughness_layer){
   ROUGHNESS=mix(ROUGHNESS,max(ROUGHNESS,.62),touched*.7);
   ROUGHNESS=mix(ROUGHNESS,.48+.10*grain,metal);
   ROUGHNESS=clamp(ROUGHNESS+crush*.08,0.,1.);
  }
  if(normal_layer){
   // Millimetre detail; no repeating corrugation or globally inflated body.
   float h=(crease_noise-.5)*.002*crush;
   h+=(noise3(rest_position*vec3(23,15,17))-.5)*.0004*crush;
   h+=(noise3(rest_position*9.)-.5)*.00025*plastic;
   h+=pow(abs(cos(fold_phase*2.)),8.)*.0035*severe;
   // Surface-gradient bump mapping, Mikkelsen2010. Differentiates AFTER skinning.
   vec3 sigma_s=dFdx(VERTEX),sigma_t=dFdy(VERTEX);
   vec3 r1=cross(sigma_t,NORMAL),r2=cross(NORMAL,sigma_s);
   float det=dot(sigma_s,r1);
   vec3 gradient=sign(det)*(dFdx(h)*r1+dFdy(h)*r2);
   vec3 perturbed=NORMAL;
   if(abs(det)>1e-10)perturbed=normalize(abs(det)*NORMAL-gradient);
   vec3 detail=normalize(vec3(dot(perturbed,TANGENT),dot(perturbed,BINORMAL),dot(perturbed,NORMAL)));
   // Reoriented normal mapping, Barre-Brisebois/Hill2012. Flat detail is identity.
   vec3 t=n+vec3(0,0,1);vec3 u=detail*vec3(-1,-1,1);
   n=normalize(t*dot(t,u)/max(t.z,.001)-u);
  }
  if(masks_debug){ALBEDO=vec3(plastic,touched,crush);ROUGHNESS=.85;METALLIC=0.;n=vec3(0,0,1);}
 }
 NORMAL_MAP=n*.5+.5;NORMAL_MAP_DEPTH=1.;
}
