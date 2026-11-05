shader_type spatial;
render_mode cull_disabled;
uniform int kind=1;
uniform vec4 base_color: source_color=vec4(.55,.45,.30,1);
varying vec3 world_position;
varying vec3 rest_position;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;rest_position=VERTEX;}
void fragment(){
 vec2 p=world_position.xz;
 float broad=noise(p*.27);
 float fine=noise(p*32.);
 float footprint=max(length(dFdx(p)),length(dFdy(p)));
 float fine_filter=1.-smoothstep(.012,.06,footprint);
 float grain_filter=1.-smoothstep(.002,.014,footprint);
 float grime=clamp(COLOR.r,0.,1.);
 float height=0.;vec3 color=base_color.rgb;
 float rough=.88;
 if(kind==0){
  float grain=noise(p*115.);
  color*=.91+.13*broad+.04*(fine-.5)*fine_filter;
  height=(fine-.5)*.0016*fine_filter+(grain-.5)*.0007*grain_filter;
  rough=.90+.07*grain;
 }else if(kind==3){
  float board=floor(p.x/.28);float seam=smoothstep(.475,.5,abs(fract(p.x/.28)-.5));
  float grain=sin(p.y*57.+noise(vec2(p.y*.8,board))*6.+p.x*5.);
  color*=.78+.18*hash(vec2(board,2.))+.10*grain+.10*broad;
  color=mix(color,vec3(.12,.085,.045),seam*.75);
  height=grain*.0009*fine_filter-seam*.002*fine_filter;
  grime=max(grime,seam*.22);rough=.77+.12*fine;
 }else{
  float pores=smoothstep(.73,.95,fine);
  vec2 q=vec2(p.x+world_position.y*.35,p.y+world_position.y*.65);
  color*=.90+.16*broad-.06*pores;
  if(kind==1){
   float joint=max(smoothstep(.475,.5,abs(fract(world_position.y/.65)-.5)),smoothstep(.48,.5,abs(fract((q.x+floor(world_position.y/.65)*.7)/1.8)-.5)));
   color=mix(color,color*.62,joint*.55);height-=joint*.0015;grime=max(grime,joint*.13);
  }
  height+=((fine-.5)*.0017-pores*.0013)*fine_filter;rough=.83+.10*fine*fine_filter;
 }
 // Geometry-authored sheltered creases/bases carry grime; broad pigment is clean.
 float dirt=grime*(.65+.35*noise(p*4.+world_position.y));
 color=mix(color,color*vec3(.46,.40,.29),dirt*.55);
 ALBEDO=color;ROUGHNESS=clamp(rough+dirt*.07,0.,1.);METALLIC=0.;
 AO=clamp(COLOR.g,0.45,1.0);AO_LIGHT_AFFECT=.20;
 vec3 sx=dFdx(VERTEX),sy=dFdy(VERTEX);vec3 r1=cross(sy,NORMAL),r2=cross(NORMAL,sx);
 float determinant=dot(sx,r1);
 if(abs(determinant)>0.0000001){vec3 gradient=(r1*dFdx(height)+r2*dFdy(height))/determinant;NORMAL=normalize(NORMAL-gradient);}
}
