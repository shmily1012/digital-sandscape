#[compute]
#version 450
layout(local_size_x=64) in;
struct SourceFace { uint a; uint b; float mobility; float source; };
struct Face { uint a; uint b; float velocity; uint axis; };
layout(set=0,binding=0,std430) readonly restrict buffer Pressure { float p[]; } pressure;
layout(set=0,binding=1,std430) readonly restrict buffer Forcing { SourceFace face[]; } forcing;
layout(set=0,binding=2,std430) restrict buffer Faces { Face face[]; } geometry;
layout(set=0,binding=3,std430) readonly restrict buffer Adjacency { ivec4 face[]; } adjacency;
layout(set=0,binding=4,std430) writeonly restrict buffer Status { float dt_h; uint accepted; float divergence; float outgoing_rate; } status;
layout(set=0,binding=5,std430) readonly restrict buffer PressureStatus { uint word[]; } control;
layout(push_constant,std430) uniform Params { uint cells; uint faces; uint side; uint phase; float requested_dt; float divergence_tolerance; uint pad0; uint pad1; } p;
shared float rates[64];
shared float divergences[64];
void main() {
    uint i=gl_GlobalInvocationID.x;
    if(p.phase==0u) {
        if(i>=p.faces || control.word[1]!=1u || control.word[3]!=0u) return;
        SourceFace f=forcing.face[i];
        geometry.face[i].velocity=f.source-f.mobility*(pressure.p[f.b]-pressure.p[f.a])*float(p.side);
        return;
    }
    uint lane=gl_LocalInvocationID.x;
    float maximum_rate=0.0,maximum_divergence=0.0;
    for(uint cell=lane;cell<p.cells;cell+=64u) {
        float rate=0.0,divergence=0.0;
        ivec4 ids=adjacency.face[cell];
        for(int k=0;k<4;++k) if(ids[k]>=0) {
            Face f=geometry.face[ids[k]];
            float signed_flux=(f.a==cell ? 1.0 : -1.0)*f.velocity*float(p.side);
            if(isnan(signed_flux)||isinf(signed_flux)) {
                rate=uintBitsToFloat(0x7f800000u);
                divergence=rate;
            } else {
                rate+=max(0.0,signed_flux);
                divergence+=signed_flux;
            }
        }
        maximum_rate=max(maximum_rate,rate);
        maximum_divergence=max(maximum_divergence,abs(divergence));
    }
    rates[lane]=maximum_rate;divergences[lane]=maximum_divergence;
    barrier();
    for(uint stride=32u;stride>0u;stride>>=1u) {
        if(lane<stride) {
            rates[lane]=max(rates[lane],rates[lane+stride]);
            divergences[lane]=max(divergences[lane],divergences[lane+stride]);
        }
        barrier();
    }
    if(lane==0u) {
        bool accepted=control.word[1]==1u && control.word[3]==0u && !isinf(rates[0]) && divergences[0]<=p.divergence_tolerance;
        float dt=rates[0]>0.0 ? min(p.requested_dt,0.45/rates[0]) : p.requested_dt;
        status.dt_h=accepted ? dt*float(p.side) : 0.0;
        status.accepted=accepted ? 1u : 0u;
        status.divergence=divergences[0];status.outgoing_rate=rates[0];
    }
}
