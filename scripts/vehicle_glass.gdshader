shader_type spatial;
render_mode blend_mix, cull_disabled, depth_prepass_alpha;
uniform sampler2D cell_mask : filter_nearest, repeat_disable;
uniform sampler2D frame_weight : filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(0.34,0.46,0.49,0.12);
uniform float crack = 0.0;
uniform float seed = 0.0;
uniform vec2 hit_uv = vec2(0.5);
uniform float aspect = 2.0;
uniform float ghost = 0.0;
uniform bool membrane_active = false;
uniform vec3 membrane_offsets[117];
void vertex() {
 if (membrane_active) {
  vec2 q=clamp(UV,vec2(0.0),vec2(1.0))*vec2(12.0,8.0);
  ivec2 a=ivec2(min(floor(q),vec2(11.0,7.0)));
  vec2 t=q-vec2(a);
  int i=a.y*13+a.x;
  VERTEX+=mix(mix(membrane_offsets[i],membrane_offsets[i+1],t.x),mix(membrane_offsets[i+13],membrane_offsets[i+14],t.x),t.y)*textureLod(frame_weight,UV,0.0).r;
 }
}
void fragment() {
 vec2 c=clamp(UV,vec2(0.00001),vec2(0.99999))*vec2(20.0,13.0);
 vec2 cell=floor(c);vec2 f=fract(c);
 float triangle=f.x+f.y<1.0?0.0:1.0;
 float present=texture(cell_mask,vec2((cell.x*2.0+triangle+0.5)/40.0,(cell.y+0.5)/13.0)).r;
 if(present<0.5){discard;}
 vec2 p=(UV-hit_uv)*vec2(aspect,1.0);
 float angle=atan(p.y,p.x);float radius=length(p);
 float rays=1.0-smoothstep(0.015,0.060,abs(sin(angle*7.0+sin(angle*13.0+seed)*0.32)));
 float rings=1.0-smoothstep(0.012,0.045,abs(fract(radius*13.0+sin(angle*8.0+seed)*0.13)-0.5));
 float fractures=max(rays,rings)*crack*(1.0-smoothstep(0.55,1.2,radius));
 ALBEDO=mix(tint.rgb,vec3(0.78,0.89,0.94),fractures);
 ROUGHNESS=0.08+fractures*0.6;
 METALLIC=0.03;
 ALPHA=(tint.a+fractures*0.68)*mix(1.0,0.35,ghost);
}
