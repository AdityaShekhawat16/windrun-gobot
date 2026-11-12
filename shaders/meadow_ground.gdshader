shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
uniform sampler2D meadow_brush : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 p_world;
varying float slope;
float rand21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float nois(vec2 p){vec2 i=floor(p), f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(rand21(i),rand21(i+vec2(1.,0.)),f.x),mix(rand21(i+vec2(0.,1.)),rand21(i+vec2(1.,1.)),f.x),f.y);}
void vertex(){
 p_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 slope=clamp(1.0-NORMAL.y,0.0,1.0);
}
void fragment(){
 vec2 xy=p_world.xz;
 float big=nois(xy*0.006+vec2(1.2,7.1));
 float med=nois(xy*0.024+vec2(13.2,29.1));
 float small=nois(xy*0.095+vec2(5.1,37.2));
 float shade=smoothstep(0.19,0.83,big*0.63+med*0.37);
 vec3 valley=vec3(0.125,0.285,0.149);
 vec3 meadow=vec3(0.245,0.427,0.193);
 vec3 ridge=vec3(0.385,0.526,0.231);
 vec3 albedo=mix(valley,meadow,shade);
 albedo=mix(albedo,ridge,smoothstep(7.0,34.0,p_world.y)*0.20);
 float brush=texture(meadow_brush,xy*0.095).r;
 albedo*=0.92+0.12*brush+0.060*(small-0.5);
 // Broad undulating meadow bands, no sharp stripes.
 albedo*=1.0+0.042*sin(xy.x*0.019+xy.y*0.027+med*2.0);
 albedo=mix(albedo,vec3(0.25,0.33,0.21),clamp(slope*0.30,0.0,0.25));
 ALBEDO=albedo;
 ROUGHNESS=1.0;
}
