shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, depth_draw_opaque;
uniform sampler2D painted_flowers : source_color, filter_linear_mipmap;
varying vec3 tint;
void vertex(){
 tint=COLOR.rgb;
 float tip=1.0-UV.y;
 float breeze=sin(TIME*0.62+INSTANCE_ID*1.31)*0.07;
 VERTEX.x+=breeze*tip*tip;
}
void fragment(){
 vec4 tex=texture(painted_flowers,UV);
 ALBEDO=mix(tex.rgb,tex.rgb*tint,0.22);
 ALPHA=tex.a;
 ALPHA_SCISSOR_THRESHOLD=0.35;
 ROUGHNESS=1.0;
}
