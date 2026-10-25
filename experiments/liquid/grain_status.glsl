#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly restrict buffer Controls { uint word[]; } controls;
layout(set=0,binding=1,std430) readonly restrict buffer Certificate { uint valid; } certificate;
layout(set=0,binding=2,std430) readonly restrict buffer Candidates { uint valid[]; } candidates;
layout(set=0,binding=3,std430) writeonly restrict buffer Summary { uvec4 state; } summary;
layout(push_constant,std430) uniform Params { uint grains; uint systems; uint pad0; uint pad1; uint pad2; uint pad3; uint pad4; uint pad5; } p;
void main() {
    uint waiting=0u;
    float residual=0.0;
    for(uint s=0u;s<p.systems;++s) {
        float r=uintBitsToFloat(controls.word[4u*s]);
        if(controls.word[4u*s+3u]!=0u || isnan(r)||isinf(r)) { summary.state=uvec4(0,2,0,0);return; }
        residual=max(residual,r);
        if(controls.word[4u*s+1u]!=1u) waiting++;
    }
    // Reason: 0 accepted; 1 more iterations; 2 invalid; 3 mobility; 4 candidate.
    uint reason=waiting>0u ? 1u : (certificate.valid==0u ? 3u : 0u);
    if(reason==0u) for(uint g=0u;g<p.grains;++g) if(candidates.valid[g]!=1u) reason=4u;
    summary.state=uvec4(reason==0u ? 1u : 0u,reason,waiting,floatBitsToUint(residual));
}
