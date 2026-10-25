#[compute]
#version 450
// Disjoint tournament pairs share velocities within one bounded contact island.
layout(local_size_x=16) in;
struct Grain { vec4 geom; vec4 props; };
struct Contact { vec4 geometry; ivec4 ids; vec4 reaction; };
layout(set=0,binding=0,std430) readonly buffer Input { Grain g[]; } src;
layout(set=0,binding=1,std430) writeonly buffer Output { Grain g[]; } dst;
layout(set=0,binding=2,std430) readonly buffer Walls { vec4 plane[]; } walls;
layout(set=0,binding=3,std430) buffer Scratch { Contact c[]; } scratch;
layout(set=0,binding=4,std430) writeonly buffer Status { uvec4 state; } status;
layout(push_constant,std430) uniform Params { uint grains; uint planes; uint budget; uint pad; vec2 gravity; float dt; float friction; } p;
const float TOL=1e-7;
const float GEOMETRY_TOL=2e-7;
shared vec2 velocity[16];
shared vec2 position[16];
shared uint invalid;
shared float errors[16];
shared float residual;
vec2 relative(uint index) {
    Contact c=scratch.c[index];
    vec2 v=velocity[c.ids.x];
    if(c.ids.y>=0) v-=velocity[c.ids.y];
    vec2 n=c.geometry.xy;
    return vec2(dot(v,n),dot(v,vec2(-n.y,n.x)));
}
void apply_force(uint index,vec2 delta) {
    Contact c=scratch.c[index];vec2 n=c.geometry.xy;
    vec2 f=n*delta.x+vec2(-n.y,n.x)*delta.y;
    velocity[c.ids.x]+=f/src.g[c.ids.x].geom.w;
    if(c.ids.y>=0) velocity[c.ids.y]-=f/src.g[c.ids.y].geom.w;
}
void solve_contact(uint c) {
    scratch.c[c].ids.z+=1;
    vec4 g=scratch.c[c].geometry;vec2 old=scratch.c[c].reaction.xy;
    float normal=max(0.0,old.x-(relative(c).x+g.z/p.dt)/g.w);
    apply_force(c,vec2(normal-old.x,0));
    float tangent=clamp(old.y-relative(c).y/g.w,-p.friction*normal,p.friction*normal);
    apply_force(c,vec2(0,tangent-old.y));
    scratch.c[c].reaction.xy=vec2(normal,tangent);
}
uint player(uint slot,uint round) { return slot==0u ? 0u : 1u+(slot-1u+15u-round)%15u; }
void sync_work() { memoryBarrierBuffer();barrier(); }
void main() {
    uint i=gl_LocalInvocationID.x;
    if(i==0u) {status.state=uvec4(0,0,0,2);invalid=0u;residual=0.0;}
    barrier();
    if(p.grains==0u||p.grains>16u||p.planes>64u||p.budget==0u||p.budget>2000u) return;
    if(i<p.grains) dst.g[i]=src.g[i];
    if(p.dt<=0.0||p.friction<0.0||isnan(p.dt)||isinf(p.dt)||isnan(p.friction)||isinf(p.friction)||any(isnan(p.gravity))||any(isinf(p.gravity))) return;
    if(i<p.grains) {
        Grain g=src.g[i];
        if(any(isnan(g.geom))||any(isinf(g.geom))||g.geom.z<=0.0||g.geom.w<=0.0||isnan(g.props.x)||isinf(g.props.x)||g.props.x<=0.0) atomicOr(invalid,1u);
        velocity[i]=(g.props.x-1.0)*3.141592653589793*g.geom.z*g.geom.z*p.gravity/g.geom.w;
        uint count=i*(i-1u)/2u+i*p.planes;
        for(uint j=0u;j<i;++j) {
            vec2 d=g.geom.xy-src.g[j].geom.xy;float distance=length(d);
            float gap=distance-g.geom.z-src.g[j].geom.z;
            if(distance<=0.0||gap < -GEOMETRY_TOL) atomicOr(invalid,1u);
            scratch.c[count].geometry=vec4(d/distance,gap,1.0/g.geom.w+1.0/src.g[j].geom.w);
            scratch.c[count].ids=ivec4(int(i),int(j),0,0);
            scratch.c[count++].reaction=vec4(0);
        }
        for(uint j=0u;j<p.planes;++j) {
            vec4 wall=walls.plane[j];
            if(any(isnan(wall))||any(isinf(wall))||abs(length(wall.xy)-1.0)>GEOMETRY_TOL) atomicOr(invalid,1u);
            float gap=dot(wall.xy,g.geom.xy)-wall.z-g.geom.z;
            if(gap < -GEOMETRY_TOL) atomicOr(invalid,1u);
            scratch.c[count].geometry=vec4(wall.xy,gap,1.0/g.geom.w);
            scratch.c[count].ids=ivec4(int(i),-1,0,0);
            scratch.c[count++].reaction=vec4(0);
        }
    }
    sync_work();
    if(invalid!=0u) return;
    uint total=p.grains*(p.grains-1u)/2u+p.grains*p.planes;
    bool converged=false;uint iterations=0u;
    for(uint iteration=0u;iteration<p.budget;++iteration) {
        // Every round is a matching: each particle has at most one writer.
        for(uint round=0u;round<15u;++round) {
            if(i<8u) {
                uint a=player(i,round),b=player(15u-i,round);
                uint hi=max(a,b),lo=min(a,b);
                if(hi<p.grains) solve_contact(hi*(hi-1u)/2u+hi*p.planes+lo);
            }
            sync_work();
        }
        if(i<p.grains) {
            uint start=i*(i-1u)/2u+i*p.planes+i;
            for(uint wall=0u;wall<p.planes;++wall) solve_contact(start+wall);
        }
        sync_work();
        float error=0.0;
        for(uint c=i;c<total;c+=16u) {
            vec4 g=scratch.c[c].geometry;vec2 old=scratch.c[c].reaction.xy;vec2 v=relative(c);
            vec2 projected=vec2(max(0.0,old.x-(v.x+g.z/p.dt)/g.w),clamp(old.y-v.y/g.w,-p.friction*old.x,p.friction*old.x));
            float e=g.w*max(abs(projected.x-old.x),abs(projected.y-old.y));
            if(isnan(e)||isinf(e)) atomicOr(invalid,1u);
            error=max(error,e);
        }
        errors[i]=error;
        barrier();
        if(i==0u) {residual=0.0;for(uint j=0u;j<16u;++j) residual=max(residual,errors[j]);}
        barrier();
        iterations=iteration+1u;
        if(invalid!=0u) return;
        if(residual<=TOL) {converged=true;break;}
    }
    if(i==0u) status.state=uvec4(0,iterations,floatBitsToUint(residual),1);
    if(!converged) return;
    if(i<p.grains) position[i]=src.g[i].geom.xy+p.dt*velocity[i];
    barrier();
    if(i<p.grains) {
        if(any(isnan(position[i]))||any(isinf(position[i]))) atomicOr(invalid,1u);
        for(uint j=0u;j<i;++j) if(length(position[i]-position[j])+GEOMETRY_TOL<src.g[i].geom.z+src.g[j].geom.z) atomicOr(invalid,1u);
        for(uint j=0u;j<p.planes;++j) if(dot(walls.plane[j].xy,position[i])+GEOMETRY_TOL<walls.plane[j].z+src.g[i].geom.z) atomicOr(invalid,1u);
    }
    barrier();
    if(invalid!=0u) return;
    if(i<p.grains) {Grain g=src.g[i];g.geom.xy=position[i];dst.g[i]=g;}
    if(i==0u) status.state=uvec4(1,iterations,floatBitsToUint(residual),0);
}
