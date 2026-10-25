#[compute]
#version 450
// Conservative kinematic remap. No force law or fluid time advancement here.
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) buffer Phase { uint c[]; };
layout(set=0,binding=1,std430) buffer Populations { uint f[]; };
layout(set=0,binding=2,std430) buffer Materials { uint m[]; };
layout(set=0,binding=3,std430) buffer Residual { uint r[]; };
layout(set=0,binding=4,std430) buffer Velocity { vec2 v[]; };
layout(set=0,binding=5,std430) buffer Offset { vec2 offset[]; };
layout(set=0,binding=6,std430) buffer Claims { uint claim[]; };
layout(set=0,binding=7,std430) buffer Targets { uint target[]; };
layout(set=0,binding=8,std430) buffer Scratch { uint packet[]; };
layout(set=0,binding=9,std430) buffer Status { uint status[]; };
layout(set=0,binding=10,std430) readonly buffer CandidateVelocity { vec2 candidate[]; };
layout(set=0,binding=11,std430) readonly buffer ContactStatus { uint contact_status[]; };
layout(set=0,binding=12,std430) readonly buffer CandidateReaction { vec2 candidate_reaction[]; };
layout(set=0,binding=13,std430) writeonly buffer PublishedReaction { vec2 published_reaction[]; };
layout(set=0,binding=14,std430) readonly buffer FluidPhase { uint fluid_c[]; };
layout(set=0,binding=15,std430) readonly buffer FluidPopulations { uint fluid_f[]; };
layout(set=0,binding=16,std430) buffer FluidResidual { uint fluid_r[]; };
layout(set=0,binding=17,std430) buffer Clock { uint accepted_ticks[]; };
layout(push_constant,std430) uniform Params { uint side; uint mode; float dt; uint reserved; } p;
vec2 speed(uint a){return p.reserved!=0u?candidate[a]:v[a];}
bool finite2(vec2 x){return !any(isnan(x))&&!any(isinf(x));}
void fail(){atomicOr(status[0],1u);}
void fail(uint reason){atomicOr(status[0],reason);}
void main(){
    uint a=gl_GlobalInvocationID.x,count=p.side*p.side;if(a>=count)return;
    ivec2 xy=ivec2(a%p.side,a/p.side);
    if(p.mode==4u){fluid_r[a]=r[a];return;}
    if(p.mode==0u){claim[a]=count;target[a]=a;if(a==0u){status[0]=0u;status[1]=0u;}return;}
    if(p.mode==1u){
        if(p.reserved==2u){
            float fraction=uintBitsToFloat(fluid_c[a]),carry=uintBitsToFloat(fluid_r[a]);
            if(isnan(fraction)||isinf(fraction)||fraction<0.||fraction>1.||isnan(carry)||isinf(carry)||accepted_ticks[0]==0xffffffffu)fail();
            for(uint q=0u;q<9u;q++){
                float value=uintBitsToFloat(fluid_f[a*9u+q]);
                if(isnan(value)||isinf(value)||value<0.)fail();
            }
        }
        if(p.reserved!=0u && (contact_status[1]!=0u || uintBitsToFloat(contact_status[0])>1e-7))fail(2u);
        if(m[a]>4u||!finite2(speed(a))||!finite2(offset[a])){fail();return;}
        if(m[a]<2u){if(any(notEqual(offset[a],vec2(0)))||any(notEqual(speed(a),vec2(0))))fail();return;}
        vec2 d=speed(a)*p.dt;
        if(any(greaterThan(abs(d),vec2(.25)))||any(greaterThanEqual(offset[a],vec2(.5)))||any(lessThan(offset[a],vec2(-.5)))){fail();return;}
        ivec2 dest=xy+ivec2(floor(offset[a]+d+.5));
        if(any(lessThan(dest,ivec2(0)))||any(greaterThanEqual(dest,ivec2(p.side)))){fail();return;}
        uint b=uint(dest.y)*p.side+uint(dest.x);target[a]=b;
        if(m[b]==1u){fail(16u);return;}
        if(m[b]==0u&&uintBitsToFloat(p.reserved==2u?fluid_c[b]:c[b])>.05){fail(32u);return;}
        if(atomicCompSwap(claim[b],count,a)!=count)fail(64u);
        // Swept unit boxes, including diagonal and two-cell neighbors. Reject
        // unsupported contacts rather than passing through corners between ticks.
        for(int dy=-2;dy<=2;dy++)for(int dx=-2;dx<=2;dx++){
            if(dx==0&&dy==0)continue;
            ivec2 q=xy+ivec2(dx,dy);
            if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,ivec2(p.side))))continue;
            uint j=uint(q.y)*p.side+uint(q.x);if(m[j]==0u)continue;
            // Cancel integer cell spacing before adding tiny offsets/tolerance.
            // Forming (1 + offset_j) - offset_a first loses near-contact bits.
            precise vec2 local_gap=offset[j]-offset[a];
            precise vec2 lower=vec2(-1-dx,-1-dy)+vec2(1e-6)-local_gap;
            precise vec2 upper=vec2(1-dx,1-dy)-vec2(1e-6)-local_gap;
            vec2 rel=(speed(j)-speed(a))*p.dt;
            float enter=0.,leave=1.;
            for(int axis=0;axis<2;axis++){
                if(abs(rel[axis])<1e-12){if(lower[axis]>=0.||upper[axis]<=0.)leave=-1.;}
                else{
                    float t0=lower[axis]/rel[axis];
                    float t1=upper[axis]/rel[axis];
                    enter=max(enter,min(t0,t1));leave=min(leave,max(t0,t1));
                }
            }
            if(leave>enter)fail(128u);
        }
        return;
    }
    if(p.mode==2u){
        uint source=claim[a];
        bool incoming=source<count;
        if(!incoming){
            source=a;
            // A vacated chain head receives the terminal fluid packet. A chain
            // longer than the bounded traversal is rejected without mutation.
            for(uint k=0u;k<32u&&m[source]>=2u;k++)source=target[source];
            if(m[a]>=2u&&m[source]!=0u){fail(256u);return;}
        }
        uint base=16u*a;
        packet[base]=p.reserved==2u?fluid_c[source]:c[source];
        for(uint q=0u;q<9u;q++)packet[base+1u+q]=p.reserved==2u?fluid_f[9u*source+q]:f[9u*source+q];
        packet[base+10u]=m[source];packet[base+11u]=p.reserved==2u?fluid_r[source]:r[source];
        vec2 nv=incoming?speed(source):vec2(0),no=vec2(0);
        if(incoming){vec2 local=offset[source]+nv*p.dt;no=local-floor(local+.5);}
        packet[base+12u]=floatBitsToUint(nv.x);packet[base+13u]=floatBitsToUint(nv.y);
        packet[base+14u]=floatBitsToUint(no.x);packet[base+15u]=floatBitsToUint(no.y);
        return;
    }
    if(p.mode==3u){
        if(p.reserved!=0u)published_reaction[a]=status[0]==0u?candidate_reaction[a]:vec2(0);
        if(status[0]!=0u)return;
        uint base=16u*a;
        c[a]=packet[base];for(uint q=0u;q<9u;q++)f[9u*a+q]=packet[base+1u+q];
        m[a]=packet[base+10u];r[a]=packet[base+11u];
        v[a]=vec2(uintBitsToFloat(packet[base+12u]),uintBitsToFloat(packet[base+13u]));
        offset[a]=vec2(uintBitsToFloat(packet[base+14u]),uintBitsToFloat(packet[base+15u]));
        if(a==0u){status[1]=1u;if(p.reserved==2u)accepted_ticks[0]+=1u;}
    }
}
