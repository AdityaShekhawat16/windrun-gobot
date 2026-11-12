shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, depth_draw_opaque;
uniform sampler2D painted_grass : source_color, filter_linear_mipmap;
varying vec3 tuft_tint;
varying vec3 world_p;
void vertex(){
 world_p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 tuft_tint=COLOR.rgb;
 float t=1.0-UV.y;
 float breeze=sin(TIME*0.73+world_p.x*0.047+world_p.z*0.032)*0.12
             +sin(TIME*0.46-world_p.x*0.023+world_p.z*0.041)*0.075;
 VERTEX.x+=breeze*t*t;
 VERTEX.z+=breeze*0.62*t*t;
}
void fragment(){
 vec4 tex=texture(painted_grass,UV);
 ALBEDO=tex.rgb * tuft_tint * vec3(0.91,1.02,0.88);
 ALPHA=tex.a;
 ALPHA_SCISSOR_THRESHOLD=0.32;
 ROUGHNESS=1.0;
}
