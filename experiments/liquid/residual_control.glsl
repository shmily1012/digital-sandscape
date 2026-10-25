#[compute]
#version 450
layout(local_size_x=64) in;
struct Equation { vec4 weights; vec4 source; };
layout(set=0,binding=0,std430) readonly restrict buffer Pressure { float p[]; } state;
layout(set=0,binding=1,std430) readonly restrict buffer Equations { Equation cell[]; } equations;
layout(set=0,binding=2,std430) restrict buffer Control { uint word[]; } control;
layout(set=0,binding=3,std430) writeonly restrict buffer Mirror { float p[]; } mirror;
layout(push_constant,std430) uniform Parameters { uint size; uint levels; float tolerance; uint final_check; } params;
shared float maximum[64];
shared float source_maximum[64];
void main() {
    // Uniform early return is safe before every workgroup barrier. The first
    // check of each new solve is unconditional, so stale success cannot skip it.
    if((params.final_check&4u)!=0u && (control.word[1]!=0u || control.word[3]!=0u)) return;
    uint lane=gl_LocalInvocationID.x;
    uint n=params.size;
    float peak=0.0,source_peak=0.0;
    for(uint i=lane;i<n*n;i+=64u) {
        vec4 w=equations.cell[i].weights;
        float r=equations.cell[i].source.x;
        float roundoff_scale=abs(r);
        if((params.final_check&8u)!=0u){
            // Absolute stencil evaluation scale, including cancellation in p_i-p_j.
            if(w.x>0.)roundoff_scale+=w.x*(abs(state.p[i])+abs(state.p[i-1u]));
            if(w.y>0.)roundoff_scale+=w.y*(abs(state.p[i])+abs(state.p[i+1u]));
            if(w.z>0.)roundoff_scale+=w.z*(abs(state.p[i])+abs(state.p[i-n]));
            if(w.w>0.)roundoff_scale+=w.w*(abs(state.p[i])+abs(state.p[i+n]));
        }
        source_peak=max(source_peak,roundoff_scale);
        if(w.x>0.0) r-=w.x*(state.p[i]-state.p[i-1u]);
        if(w.y>0.0) r-=w.y*(state.p[i]-state.p[i+1u]);
        if(w.z>0.0) r-=w.z*(state.p[i]-state.p[i-n]);
        if(w.w>0.0) r-=w.w*(state.p[i]-state.p[i+n]);
        peak=max(peak,isnan(r)||isinf(r) ? uintBitsToFloat(0x7f800000u) : abs(r));
    }
    maximum[lane]=peak;source_maximum[lane]=source_peak;
    barrier();
    for(uint stride=32u;stride>0u;stride>>=1u) {
        if(lane<stride) {maximum[lane]=max(maximum[lane],maximum[lane+stride]);source_maximum[lane]=max(source_maximum[lane],source_maximum[lane+stride]);}
        barrier();
    }
    bool invalid=isinf(maximum[0]) || isinf(source_maximum[0]) || isnan(source_maximum[0]);
    // Opt-in mixed tolerance: four float32 epsilons of the RHS scale.
    float threshold=params.tolerance+((params.final_check&2u)!=0u ? 4.76837158203125e-7*source_maximum[0] : 0.0);
    bool done=!invalid && maximum[0]<=threshold;
    if(lane==0u) {
        control.word[0]=floatBitsToUint(maximum[0]);
        control.word[1]=done ? 1u : 0u;
        control.word[3]=invalid ? 1u : 0u;
        if(!done && !invalid && (params.final_check&1u)==0u) control.word[2]+=1u;
        for(uint level=0u;level<params.levels;++level) {
            uint side=n>>level;
            uint offset=4u+4u*level;
            control.word[offset]=done||invalid ? 0u : (side*side+63u)/64u;
            control.word[offset+1u]=1u;
            control.word[offset+2u]=1u;
        }
    }
    // CPU records a bounded command list with known ping-pong parity. Once
    // work is skipped, both fine buffers must represent the accepted state.
    if(done||invalid) {
        for(uint i=lane;i<n*n;i+=64u) mirror.p[i]=state.p[i];
    }
}
