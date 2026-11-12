shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
varying vec3 crown_tint;
varying vec3 p_world;
varying float upward;
float hh(vec3 p){return fract(sin(dot(p,vec3(31.13,72.11,43.77)))*27451.141);}
void vertex(){
 crown_tint=COLOR.rgb;
 p_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 upward=NORMAL.y;
 float r=sin(VERTEX.x*2.8+VERTEX.y*3.4)*sin(VERTEX.z*2.5+VERTEX.y*2.4);
 VERTEX+=NORMAL*(0.14*r);
}
void fragment(){
 float n=hh(floor(p_world*2.7));
 float lightness=mix(0.80,1.11,n);
 lightness*=mix(0.70,1.13,smoothstep(-0.7,0.8,upward));
 ALBEDO=crown_tint*vec3(0.86,1.03,0.83)*lightness;
 ROUGHNESS=1.0;
}
