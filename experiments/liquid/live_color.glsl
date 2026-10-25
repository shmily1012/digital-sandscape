#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,std430) readonly restrict buffer Fraction { float c[]; } gas;
layout(rgba8,set=0,binding=1) uniform writeonly image2D output_image;
void main() {
    ivec2 q=ivec2(gl_GlobalInvocationID.xy);
    if(any(greaterThanEqual(q,ivec2(32)))) return;
    float radius=length((vec2(q)+0.5)/32.0-0.5);
    float c=gas.c[q.y*32+q.x];
    vec3 color=mix(vec3(0.20,0.23,0.25),vec3(0.85,0.87,0.86),clamp(c,0.0,1.0));
    imageStore(output_image,q,vec4(color,radius<0.46 ? 1.0 : 0.0));
}
