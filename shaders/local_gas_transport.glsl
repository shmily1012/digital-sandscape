#[compute]
#version 450
// Implicit upwind gas-volume candidate on moving fluid capacities.
// No publication to live phase/material buffers; acceptance is explicit.
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Geometry { vec4 geometry[]; };
layout(set=0,binding=1,std430) readonly buffer Flow { vec2 flow[]; };
layout(set=0,binding=2,std430) readonly buffer OldGas { float old_gas[]; };
layout(set=0,binding=3,std430) buffer Fraction { float fraction[]; };
layout(set=0,binding=4,std430) writeonly buffer Next { float next_fraction[]; };
layout(set=0,binding=5,std430) writeonly buffer CandidateGas { float candidate_gas[]; };
layout(set=0,binding=6,std430) buffer Partial { vec4 partial[]; };
layout(set=0,binding=7,std430) buffer Status { uint status[]; };
layout(set=0,binding=8,std430) readonly buffer PressureStatus { uint pressure_status[]; };
layout(set=0,binding=9,std430) buffer ContactStatus { uint contact_status[]; };
layout(push_constant,std430) uniform Params { uint side;uint mode;float dt;float tolerance; } p;
shared vec4 reduction[64];
bool finite1(float x){return !isnan(x)&&!isinf(x);}
vec4 outward(uint i){return vec4(i%p.side>0u?-flow[i-1u].x:0.,i%p.side+1u<p.side?flow[i].x:0.,i>=p.side?-flow[i-p.side].y:0.,i+p.side<p.side*p.side?flow[i].y:0.)*p.dt;}
float upstream(uint i,uint k){return fraction[k==0u?i-1u:(k==1u?i+1u:(k==2u?i-p.side:i+p.side))];}
void main(){
    uint i=gl_GlobalInvocationID.x,lane=gl_LocalInvocationID.x,count=p.side*p.side;
    if(p.mode==4u){if(i==0u)for(uint k=0u;k<6u;k++)status[k]=0u;return;}
    if(p.mode==3u){
        if(i!=0u)return;
        float delta=0.,inventory=0.,residual=0.,transport_error=0.;
        for(uint k=0u;k<(count+63u)/64u;k++){delta+=partial[k].x;inventory+=partial[k].y;residual=max(residual,partial[k].z);transport_error=max(transport_error,partial[k].w);}
        status[0]=floatBitsToUint(residual);status[3]=floatBitsToUint(delta);
        status[4]=floatBitsToUint(transport_error);status[5]=pressure_status[0];
        status[1]=(status[2]==0u&&pressure_status[1]==1u&&contact_status[1]==0u&&transport_error<=p.tolerance&&abs(delta)<=max(1e-7,inventory*1e-6))?1u:0u;
        if(status[1]==0u)atomicOr(contact_status[1],4u);
        return;
    }
    if(p.mode==0u){
        if(i>=count)return;
        float old_volume=geometry[i].x,new_volume=geometry[i].y,g=old_gas[i];
        if(!finite1(g)||!finite1(old_volume)||!finite1(new_volume)||g<0.||old_volume<0.||new_volume<0.||g>old_volume)atomicOr(status[2],1u);
        fraction[i]=old_volume>0.?g/old_volume:0.;return;
    }
    vec4 item=vec4(0);
    if(i<count){
        vec4 q=outward(i);float current=fraction[i],denominator=geometry[i].x;
        // Increment form of the convex mixture avoids rounding a tiny change
        // by first summing several O(1) terms. No fraction clipping is applied.
        precise float increment=fma(-geometry[i].x,current,old_gas[i]);
        for(uint k=0u;k<4u;k++){
            if(q[k]<0.){increment+=(-q[k])*(upstream(i,k)-current);denominator+=-q[k];}
        }
        if(p.mode==1u){next_fraction[i]=denominator>0.?current+increment/denominator:0.;return;}
        float value=fraction[i]*geometry[i].y;
        precise float gas_balance=value-old_gas[i];
        precise float volume_balance=geometry[i].y-geometry[i].x;
        for(uint k=0u;k<4u;k++){
            volume_balance+=q[k];
            if(q[k]!=0.)gas_balance+=q[k]*(q[k]>0.?current:upstream(i,k));
        }
        float residual=max(abs(gas_balance),abs(volume_balance));
        // The convex equation uses the incoming-volume ledger. Account for
        // the measured pressure/capacity defect separately from transport error.
        float transport_error=max(max(0.,abs(gas_balance)-abs(volume_balance)),max(0.,abs(volume_balance)-p.dt*uintBitsToFloat(pressure_status[0])));
        candidate_gas[i]=value;
        if(!finite1(value)||!finite1(residual)||!finite1(transport_error)||value<0.||value>geometry[i].y||any(isnan(q))||any(isinf(q))){atomicOr(status[2],2u);residual=3.4e38;transport_error=3.4e38;}
        item=vec4(value-old_gas[i],old_gas[i],residual,transport_error);
    }else if(p.mode==1u)return;
    reduction[lane]=item;barrier();
    for(uint stride=32u;stride>0u;stride/=2u){
        if(lane<stride){reduction[lane].xy+=reduction[lane+stride].xy;reduction[lane].zw=max(reduction[lane].zw,reduction[lane+stride].zw);}barrier();
    }
    if(lane==0u)partial[gl_WorkGroupID.x]=reduction[0];
}
