#[compute]
#version 450
layout(local_size_x=64) in;
struct Face { uint a; uint b; float mobility; float prescribed; };
layout(set=0,binding=0,std430) readonly restrict buffer Pressure { float p[]; } state;
layout(set=0,binding=1,std430) readonly restrict buffer Faces { Face face[]; } geometry;
layout(set=0,binding=2,std430) writeonly restrict buffer Fluxes { vec2 flux[]; } result;
layout(push_constant,std430) uniform Parameters { uint count; float h; uint pad0; uint pad1; } params;
void main() {
    uint i=gl_GlobalInvocationID.x;
    if(i>=params.count) return;
    Face f=geometry.face[i];
    float liquid=-f.mobility*(state.p[f.b]-state.p[f.a])/params.h;
    result.flux[i]=vec2(liquid,liquid+f.prescribed);
}
