#[compute]
#version 450
// Inelastic face contact for voxel grains. Each colored edge has two unique owners.
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) buffer Velocities { vec2 velocity[]; };
layout(set=0,binding=1,std430) readonly buffer Materials { uint material[]; };
layout(set=0,binding=2,std430) buffer Reactions { vec2 reaction[]; };
layout(set=0,binding=3,std430) buffer LiveVelocities { vec2 live_velocity[]; };
// max positive closing-speed bits, invalid flag, accepted flag, reserved.
layout(set=0,binding=4,std430) buffer Status { uint status[]; };
layout(set=0,binding=5,std430) writeonly buffer PublishedReactions { vec2 published_reaction[]; };
layout(set=0,binding=6,std430) readonly buffer Offsets { vec2 offset[]; };
layout(set=0,binding=7,std430) readonly buffer FluidImpulse { vec2 fluid_impulse[]; };
layout(set=0,binding=8,std430) buffer EdgeImpulses { vec2 edge_impulse[]; };
layout(set=0,binding=9,std430) buffer EdgeRemainders { vec2 edge_remainder[]; };
layout(set=0,binding=10,std430) buffer DiagonalAxes { uint diagonal_axis[]; };
layout(push_constant,std430) uniform Params { uint side; uint mode; uint parity; float friction; float dt; float gx; float gy; uint use_fluid_impulse; float relaxation; uint diagonals; uint pad1; uint pad2; } p;
float inverse_mass(uint m){
    // Unit displaced fluid mass plus the existing effective buoyant mass.
    return m==2u?1./3.:(m==3u?1./2.7:(m==4u?1./2.4:0.));
}
// Two-float accumulation keeps increments below the pressure impulse's ULP.
vec2 add_increment(vec2 value,float increment){
    precise float sum=value.x+increment;
    precise float b=sum-value.x;
    precise float error=(value.x-(sum-b))+(increment-b);
    precise float tail=value.y+error;
    precise float high=sum+tail;
    precise float low=tail-(high-sum);
    return vec2(high,low);
}
vec2 scaled_pair(vec2 value,float scale){
    precise float high=value.x*scale;
    precise float low=fma(value.x,scale,-high)+value.y*scale;
    return add_increment(vec2(high,0),low);
}
bool greater_pair(vec2 a,vec2 b){return a.x>b.x||(a.x==b.x&&a.y>b.y);}
float pair_change(vec2 a,vec2 b){
    precise float high=a.x-b.x;
    precise float low=a.y-b.y;
    return high+low;
}
const ivec2 DIRECTIONS[4]=ivec2[4](ivec2(1,0),ivec2(0,1),ivec2(1,1),ivec2(-1,1));
bool contact(uint a,uint direction,out uint b,out vec2 n,out float gap){
    ivec2 at=ivec2(a%p.side,a/p.side)+DIRECTIONS[direction];
    if(any(lessThan(at,ivec2(0)))||any(greaterThanEqual(at,ivec2(p.side))))return false;
    b=uint(at.y)*p.side+uint(at.x);
    if(material[a]==0u||material[b]==0u||(material[a]==1u&&material[b]==1u))return false;
    if(direction<2u)n=vec2(DIRECTIONS[direction]);
    else {
        uint axis=diagonal_axis[(direction-2u)*p.side*p.side+a];
        if(axis>=2u)return false;
        n=axis==0u?vec2(DIRECTIONS[direction].x,0):vec2(0,1);
    }
    // Sub-tolerance overlap is contact, not a velocity-level position repair.
    // The independent swept-box gate still rejects excess penetration.
    gap=max(0.,dot(offset[b]-offset[a],n));
    return true;
}
void main(){
    uint a=gl_GlobalInvocationID.x;if(a>=p.side*p.side)return;
    if(p.mode==0u){
        velocity[a]=live_velocity[a];reaction[a]=vec2(0);
        diagonal_axis[a]=2u;diagonal_axis[p.side*p.side+a]=2u;
        for(uint d=0u;d<4u;d++){
            edge_impulse[d*p.side*p.side+a]=vec2(0);
            edge_remainder[d*p.side*p.side+a]=vec2(0);
        }
        if(material[a]>=2u&&material[a]<=4u){
            float im=inverse_mass(material[a]);
            // Boussinesq reference liquid has unit density: only excess weight
            // remains after hydrostatic pressure is removed from the fluid model.
            velocity[a]+=(1.-im)*vec2(p.gx,p.gy)*p.dt;
            if(p.use_fluid_impulse!=0u)velocity[a]+=im*fluid_impulse[a];
        }
        if(a==0u){status[0]=0u;status[1]=0u;status[2]=0u;status[3]=0u;}
        return;
    }
    if(p.mode==5u){
        // Freeze a separating axis for each box-corner pair for this solve.
        // On exact corner ties choose the axis with more free predicted space.
        for(uint d=2u;d<4u;d++){
            ivec2 at=ivec2(a%p.side,a/p.side)+DIRECTIONS[d];
            if(any(lessThan(at,ivec2(0)))||any(greaterThanEqual(at,ivec2(p.side))))continue;
            uint b=uint(at.y)*p.side+uint(at.x);
            vec2 sign_axis=vec2(DIRECTIONS[d]);
            vec2 gap=(offset[b]-offset[a])*sign_axis;
            vec2 relative=(velocity[b]-velocity[a])*sign_axis*p.dt;
            float enter=0.,leave=1.;
            for(int k=0;k<2;k++){
                if(abs(relative[k])<1e-12){if(gap[k]>=-1e-6)leave=-1.;}
                else {
                    float crossing=(-1e-6-gap[k])/relative[k];
                    if(relative[k]<0.)enter=max(enter,crossing);else leave=min(leave,crossing);
                }
            }
            if(leave<=enter)continue;
            vec2 predicted=gap+relative;
            uint axis=gap.x>gap.y?0u:(gap.y>gap.x?1u:(predicted.x>=predicted.y?0u:1u));
            diagonal_axis[(d-2u)*p.side*p.side+a]=axis;atomicOr(status[3],1u);
        }
        return;
    }
    if(p.mode==3u){
        if(any(isnan(offset[a]))||any(isinf(offset[a]))){atomicOr(status[1],1u);return;}
        if(any(isnan(velocity[a]))||any(isinf(velocity[a]))||any(isnan(reaction[a]))||any(isinf(reaction[a]))||material[a]>4u){atomicOr(status[1],1u);return;}
        for(uint axis=0u;axis<(p.diagonals!=0u?4u:2u);axis++){
            uint b;vec2 n;float gap;
            if(!contact(a,axis,b,n,gap))continue;
            vec2 relative=velocity[a]-velocity[b];
            float closing=dot(relative,n)-gap/p.dt;
            if(isnan(closing)||isinf(closing))atomicOr(status[1],1u);
            else {
                float residual=max(0.,closing);
                if(p.relaxation>0.){
                    float inv=inverse_mass(material[a])+inverse_mass(material[b]);
                    vec2 old=edge_impulse[axis*p.side*p.side+a];
                    vec2 low=edge_remainder[axis*p.side*p.side+a];
                    float tangent=dot(relative,vec2(-n.y,n.x));
                    if(any(isnan(old))||any(isinf(old))||any(isnan(low))||any(isinf(low))){atomicOr(status[1],1u);continue;}
                    // Algebraic projected residual without subtracting rounded
                    // O(pressure) impulses to recover an O(1e-7) correction.
                    float nr=closing>=0.?closing:min(-closing,(old.x+low.x)*inv);
                    vec2 limit=scaled_pair(vec2(old.x,low.x),p.friction);
                    vec2 accumulated=vec2(old.y,low.y);
                    float tr=tangent>=0.?min(tangent,max(0.,pair_change(limit,accumulated))*inv):min(-tangent,max(0.,pair_change(limit,-accumulated))*inv);
                    residual=max(residual,max(nr,tr));
                }
                if(residual>0.)atomicMax(status[0],floatBitsToUint(residual));
            }
        }
        return;
    }
    if(p.mode==4u){
        bool accepted=status[1]==0u&&uintBitsToFloat(status[0])<=1e-7;
        published_reaction[a]=accepted?reaction[a]:vec2(0);
        if(accepted&&material[a]>=2u)live_velocity[a]=velocity[a];
        if(a==0u)status[2]=accepted?1u:0u;
        return;
    }
    if(p.pad1!=0u&&status[3]==0u)return;
    uint direction=p.mode<=2u?p.mode-1u:p.mode-4u;
    uint coordinate=direction==1u?a/p.side:a%p.side;
    if((coordinate&1u)!=p.parity)return;
    uint b;vec2 n;float gap;
    if(!contact(a,direction,b,n,gap))return;
    uint ma=material[a],mb=material[b];
    float ia=inverse_mass(ma),ib=inverse_mass(mb),inverse_sum=ia+ib;
    vec2 t=vec2(-n.y,n.x),relative=velocity[a]-velocity[b];
    float closing=dot(relative,n)-gap/p.dt;
    if(p.relaxation==0.&&closing<=0.)return;
    float normal=closing/inverse_sum;
    float tangent=clamp(dot(relative,t)/inverse_sum,-p.friction*normal,p.friction*normal);
    if(p.relaxation>0.){
        uint edge=direction*p.side*p.side+a;
        vec2 old=edge_impulse[edge];
        vec2 low=edge_remainder[edge];
        vec2 old_n=vec2(old.x,low.x),old_t=vec2(old.y,low.y);
        vec2 next_n=add_increment(old_n,p.relaxation*closing/inverse_sum);
        if(greater_pair(vec2(0),next_n))next_n=vec2(0);
        vec2 bound=scaled_pair(next_n,p.friction);
        vec2 next_t=add_increment(old_t,p.relaxation*dot(relative,t)/inverse_sum);
        if(greater_pair(next_t,bound))next_t=bound;
        if(greater_pair(-bound,next_t))next_t=-bound;
        edge_impulse[edge]=vec2(next_n.x,next_t.x);
        edge_remainder[edge]=vec2(next_n.y,next_t.y);
        normal=pair_change(next_n,old_n);tangent=pair_change(next_t,old_t);
    }
    vec2 impulse=normal*n+tangent*t;
    if(ma>=2u)velocity[a]-=ia*impulse;
    if(mb>=2u)velocity[b]+=ib*impulse;
    reaction[a]-=impulse;reaction[b]+=impulse;
}
