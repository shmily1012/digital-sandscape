#[compute]
#version 450
layout(local_size_x=64) in;
struct Equation { vec4 weights; vec4 source; };
layout(set=0,binding=0,std430) readonly restrict buffer Pressure { float p[]; } fine;
layout(set=0,binding=1,std430) readonly restrict buffer FineEquations { Equation cell[]; } equations;
layout(set=0,binding=2,std430) restrict buffer CoarseEquations { Equation cell[]; } coarse;
layout(set=0,binding=3,std430) writeonly restrict buffer CoarsePressure { float p[]; } initial;
layout(push_constant,std430) uniform Parameters { uint size; float unused; uint pad0; uint pad1; } params;
float residual(uint i) {
    vec4 w=equations.cell[i].weights;
    float r=equations.cell[i].source.x;
    if(w.x>0.0) r-=w.x*(fine.p[i]-fine.p[i-1u]);
    if(w.y>0.0) r-=w.y*(fine.p[i]-fine.p[i+1u]);
    if(w.z>0.0) r-=w.z*(fine.p[i]-fine.p[i-params.size]);
    if(w.w>0.0) r-=w.w*(fine.p[i]-fine.p[i+params.size]);
    return r;
}
void main() {
    uint i=gl_GlobalInvocationID.x;
    uint n=params.size/2u;
    if(i>=n*n) return;
    uint a=(i/n)*2u*params.size+(i%n)*2u;
    coarse.cell[i].source.x=residual(a)+residual(a+1u)+residual(a+params.size)+residual(a+params.size+1u);
    initial.p[i]=0.0;
}
