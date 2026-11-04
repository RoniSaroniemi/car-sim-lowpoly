shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_map : hint_default_white, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool has_albedo = false;
uniform bool has_normal = false;
uniform bool has_roughness = false;
uniform bool vertex_tint = false;
uniform bool damage_enabled = true;
uniform int view_mode = 2;
uniform float roughness_value = 0.75;
uniform float metallic_value = 0.0;
uniform float plastic_sections[7];
uniform float contact_sections[7];
varying float local_damage;
varying float local_contact;
varying float fold_mask;
varying vec2 rest_coordinates;
float section_x(int i) {
 if(i==0)return -1.72;
 if(i==1)return -1.15;
 if(i==2)return -0.40;
 if(i==3)return 0.45;
 if(i==4)return 0.90;
 if(i==5)return 1.35;
 return 1.80;
}
void vertex() {
 float x=UV2.x;
 int s=0;
 for(int i=0;i<6;i++){if(x>=section_x(i))s=i;}
 float t=clamp((x-section_x(s))/(section_x(s+1)-section_x(s)),0.0,1.0);
 local_damage=mix(plastic_sections[s],plastic_sections[s+1],t);
 local_contact=mix(contact_sections[s],contact_sections[s+1],t);
 fold_mask=COLOR.a;
 rest_coordinates=UV2;
 if(damage_enabled){
  float amplitude=0.022*local_damage*fold_mask;
  // Coherent panel folds; fixed rest coordinates keep creases attached to metal.
  float phase=x*18.0+UV2.y*1.8;
  float envelope=sin(clamp((x+1.8)/3.65,0.0,1.0)*3.14159);
  float ridge=sin(phase)*sin(phase);
  VERTEX.y+=amplitude*ridge*envelope;
  NORMAL=normalize(NORMAL+vec3(-amplitude*18.0*sin(phase*2.0)*envelope,0.0,-amplitude*1.8*sin(phase*2.0)*envelope));
 }
}
void fragment() {
 vec3 base=tint.rgb;
 if(has_albedo)base*=texture(albedo_map,UV).rgb;
 if(vertex_tint)base*=COLOR.rgb;
 if(view_mode==1)base=vec3(0.56,0.59,0.60);
 ALBEDO=base;
 ROUGHNESS=roughness_value;
 if(has_roughness)ROUGHNESS*=texture(roughness_map,UV).g;
 METALLIC=metallic_value;
 vec3 normal=has_normal?texture(normal_map,UV).rgb:vec3(0.5,0.5,1.0);
 if(damage_enabled){
  float d=clamp(local_damage,0.0,1.0)*fold_mask;
  float phase=rest_coordinates.x*18.0+rest_coordinates.y*1.8;
  float crease=pow(abs(cos(phase*2.0)),18.0)*smoothstep(0.20,0.85,d);
  float scrape=local_contact*pow(abs(sin(rest_coordinates.y*38.0+rest_coordinates.x*19.0)),12.0)*0.52;
  float wear=clamp(crease*0.10+scrape*0.20,0.0,0.28);
  if(view_mode==2){ALBEDO=mix(ALBEDO,vec3(0.23,0.25,0.25),wear);METALLIC=mix(METALLIC,0.65,wear);}
  ROUGHNESS=clamp(ROUGHNESS+d*0.18,0.0,1.0);
  // Fine wrinkles affect highlights; structural folds remain real geometry.
  float micro=sin(rest_coordinates.x*154.0+sin(rest_coordinates.y*61.0))*0.035*d;
  normal.xy+=vec2(micro,micro*0.35);
 }
 if(view_mode==1){normal=vec3(0.5,0.5,1.0);}
 NORMAL_MAP=normal;
 NORMAL_MAP_DEPTH=1.0;
 // GHOST_ALPHA
}
