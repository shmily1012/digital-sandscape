#[compute]
#version 450
layout(local_size_x=64) in;
struct Grain { vec4 geom; vec4 props; };
layout(set=0,binding=0,std430) readonly buffer Original { Grain g[]; } src;
layout(set=0,binding=1,std430) readonly buffer Candidate { Grain g[]; } candidate;
layout(set=0,binding=2,std430) buffer Validity { uint ok[]; } validity;
layout(set=0,binding=3,std430) readonly buffer KernelValidity { uint ok[]; } kernel;
layout(set=0,binding=4,std430) writeonly buffer Certificate { uint valid; } certificate;
layout(push_constant,std430) uniform Params { uint grains; uint faces; uint side; uint phase; vec2 gravity; float dt; uint pad; } p;
void main() {
    uint i=gl_GlobalInvocationID.x;
    if(i>=p.grains) return;
    if(i==0u) {
        bool all_valid=true;
        for(uint j=0u;j<p.grains;++j) all_valid=all_valid && kernel.ok[j]==1u;
        certificate.valid=all_valid ? 1u : 0u;
    }
    vec4 a=candidate.g[i].geom;
    bool ok=validity.ok[i]==1u && kernel.ok[i]==1u;
    ok=ok && length(a.xy-0.5)+max(a.z,4.0/float(p.side))<0.46;
    for(uint j=0u;j<p.grains;++j) {
        if(i==j) continue;
        vec2 d=src.g[i].geom.xy-src.g[j].geom.xy;
        vec2 v=a.xy-candidate.g[j].geom.xy-d;
        float t=dot(v,v)>0.0 ? clamp(-dot(d,v)/dot(v,v),0.0,1.0) : 0.0;
        ok=ok && length(d+t*v)>a.z+candidate.g[j].geom.z;
    }
    validity.ok[i]=ok ? 1u : 0u;
}
