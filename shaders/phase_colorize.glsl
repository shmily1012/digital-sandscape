#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,std430) readonly buffer Phase { float c[]; };
layout(set=0,binding=1,rgba8) uniform writeonly image2D output_image;
layout(set=0,binding=2,std430) readonly buffer Materials { uint material[]; };
float sample_c(ivec2 p,int side){p=clamp(p,ivec2(0),ivec2(side-1));return c[p.y*side+p.x];}
void main(){
    ivec2 p=ivec2(gl_GlobalInvocationID.xy),size=imageSize(output_image);
    if(any(greaterThanEqual(p,size)))return;
    int side=size.x;float gas=sample_c(p,side);
    vec2 grad=.5*vec2(sample_c(p+ivec2(1,0),side)-sample_c(p-ivec2(1,0),side),sample_c(p+ivec2(0,1),side)-sample_c(p-ivec2(0,1),side));
    float rim=4.*gas*(1.-gas);
    vec3 base=mix(vec3(.57,.58,.57),vec3(.88,.89,.86),gas);
    base+=vec3(.16)*dot(grad,vec2(-.7,-.7))-vec3(.12)*rim;
    uint m=material[p.y*side+p.x];
    if(m>=2u)base=m==2u?vec3(.08,.08,.075):(m==3u?vec3(.40,.40,.38):vec3(.85,.84,.79));
    imageStore(output_image,p,vec4(base,1.));
}
