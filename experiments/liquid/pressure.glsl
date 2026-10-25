#[compute]
#version 450
layout(local_size_x=64) in;
struct Equation { vec4 weights; vec4 source; };
layout(set=0,binding=0,std430) readonly restrict buffer Previous { float p[]; } previous;
layout(set=0,binding=1,std430) writeonly restrict buffer Next { float p[]; } next_state;
layout(set=0,binding=2,std430) readonly restrict buffer Equations { Equation cell[]; } equations;
layout(push_constant,std430) uniform Parameters { uint size; float relaxation; uint pad0; uint pad1; } params;
void main() {
    uint i=gl_GlobalInvocationID.x;
    uint n=params.size;
    if(i>=n*n) return;
    vec4 w=equations.cell[i].weights; // left, right, up, down; zero at walls.
    float diagonal=dot(w,vec4(1.0));
    if(diagonal==0.0) { next_state.p[i]=0.0; return; }
    float sum=equations.cell[i].source.x;
    if(w.x>0.0) sum+=w.x*previous.p[i-1u];
    if(w.y>0.0) sum+=w.y*previous.p[i+1u];
    if(w.z>0.0) sum+=w.z*previous.p[i-n];
    if(w.w>0.0) sum+=w.w*previous.p[i+n];
    next_state.p[i]=mix(previous.p[i],sum/diagonal,params.relaxation);
}
