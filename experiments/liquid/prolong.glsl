#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly restrict buffer Fine { float p[]; } fine;
layout(set=0,binding=1,std430) readonly restrict buffer Coarse { float p[]; } coarse;
layout(set=0,binding=2,std430) writeonly restrict buffer Output { float p[]; } result;
layout(push_constant,std430) uniform Parameters { uint size; float unused; uint pad0; uint pad1; } params;
void main() {
    uint i=gl_GlobalInvocationID.x;
    uint n=params.size;
    if(i>=n*n) return;
    uint parent=(i/n/2u)*(n/2u)+(i%n/2u);
    result.p[i]=fine.p[i]+coarse.p[parent];
}
