#[compute]
#version 450
// Serial reference for one small contact island, not a scalable solver.
layout(local_size_x=1) in;
struct Grain { vec4 geom; vec4 props; };
struct Contact { vec4 geometry; ivec4 ids; vec4 reaction; };
layout(set=0,binding=0,std430) readonly buffer Input { Grain g[]; } src;
layout(set=0,binding=1,std430) writeonly buffer Output { Grain g[]; } dst;
layout(set=0,binding=2,std430) readonly buffer Walls { vec4 plane[]; } walls;
layout(set=0,binding=3,std430) buffer Scratch { Contact c[]; } scratch;
layout(set=0,binding=4,std430) writeonly buffer Status { uvec4 state; } status;
#ifdef FULL_MOBILITY
layout(set=0,binding=5,std430) readonly buffer Mobility {float m[];} mobility;
float lower[1024];
#endif
layout(push_constant,std430) uniform Params { uint grains; uint planes; uint budget; uint pad; vec2 gravity; float dt; float friction; } p;
const float TOL=1e-7;
const float GEOMETRY_TOL=2e-7;
vec2 velocity[16];
vec2 position[16];
#ifdef FULL_MOBILITY
float matrix_at(uint row,uint column) {return mobility.m[row*(2u*p.grains)+column];}
float projected_mobility(Contact c,vec2 direction) {
    float result=0.0;
    for(uint a=0u;a<2u;++a)for(uint b=0u;b<2u;++b) {
        float value=matrix_at(2u*uint(c.ids.x)+a,2u*uint(c.ids.x)+b);
        if(c.ids.y>=0) {
            value+=matrix_at(2u*uint(c.ids.y)+a,2u*uint(c.ids.y)+b);
            value-=matrix_at(2u*uint(c.ids.x)+a,2u*uint(c.ids.y)+b);
            value-=matrix_at(2u*uint(c.ids.y)+a,2u*uint(c.ids.x)+b);
        }
        result+=direction[a]*value*direction[b];
    }
    return result;
}
bool valid_mobility() {
    uint size=2u*p.grains;
    for(uint i=0u;i<size;++i)for(uint j=0u;j<=i;++j) {
        float a=matrix_at(i,j),b=matrix_at(j,i);
        if(isnan(a)||isinf(a)||isnan(b)||isinf(b)||abs(a-b)>1e-5)return false;
        float value=(a+b)*0.5;
        for(uint k=0u;k<j;++k)value-=lower[i*32u+k]*lower[j*32u+k];
        if(i==j){if(value<=1e-7)return false;lower[i*32u+j]=sqrt(value);}
        else lower[i*32u+j]=value/lower[j*32u+j];
    }
    return true;
}
void rebuild_velocity(uint count) {
    vec2 net[16];
    for(uint i=0u;i<p.grains;++i){Grain g=src.g[i];precise float area=3.141592653589793*(g.geom.z*g.geom.z);precise float weight=(g.props.x-1.0)*area;net[i]=weight*p.gravity;}
    for(uint k=0u;k<count;++k){Contact c=scratch.c[k];vec2 n=c.geometry.xy;vec2 f=n*c.reaction.x+vec2(-n.y,n.x)*c.reaction.y;net[c.ids.x]+=f;if(c.ids.y>=0)net[c.ids.y]-=f;}
    for(uint i=0u;i<p.grains;++i)for(uint a=0u;a<2u;++a){
        precise float value=0.0;
        for(uint j=0u;j<p.grains;++j)for(uint b=0u;b<2u;++b)value+=matrix_at(2u*i+a,2u*j+b)*net[j][b];
        velocity[i][a]=value;
    }
}
#endif
float tangent_mobility(uint c) {
#ifdef FULL_MOBILITY
    return scratch.c[c].reaction.z;
#else
    return scratch.c[c].geometry.w;
#endif
}
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
#ifdef FULL_MOBILITY
    for(uint i=0u;i<p.grains;++i)for(uint a=0u;a<2u;++a) {
        float delta=matrix_at(2u*i+a,2u*uint(c.ids.x))*f.x+matrix_at(2u*i+a,2u*uint(c.ids.x)+1u)*f.y;
        if(c.ids.y>=0)delta-=matrix_at(2u*i+a,2u*uint(c.ids.y))*f.x+matrix_at(2u*i+a,2u*uint(c.ids.y)+1u)*f.y;
        velocity[i][a]+=delta;
    }
#else
    velocity[c.ids.x]+=f/src.g[c.ids.x].geom.w;
    if(c.ids.y>=0) velocity[c.ids.y]-=f/src.g[c.ids.y].geom.w;
#endif
}
void main() {
    status.state=uvec4(0,0,0,2);
    if(p.grains==0u||p.grains>16u||p.planes>64u||p.budget==0u||p.budget>2000u) return;
    for(uint i=0u;i<p.grains;++i) dst.g[i]=src.g[i];
    if(p.dt<=0.0||p.friction<0.0||isnan(p.dt)||isinf(p.dt)||isnan(p.friction)||isinf(p.friction)||any(isnan(p.gravity))||any(isinf(p.gravity))) return;
    uint count=0u;
    for(uint i=0u;i<p.grains;++i) {
        Grain g=src.g[i];
        if(any(isnan(g.geom))||any(isinf(g.geom))||g.geom.z<=0.0||g.geom.w<=0.0||isnan(g.props.x)||isinf(g.props.x)||g.props.x<=0.0) return;
        velocity[i]=(g.props.x-1.0)*3.141592653589793*g.geom.z*g.geom.z*p.gravity/g.geom.w;
        for(uint j=0u;j<i;++j) {
            vec2 d=g.geom.xy-src.g[j].geom.xy;float distance=length(d);
            float gap=distance-g.geom.z-src.g[j].geom.z;
            if(distance<=0.0||gap < -GEOMETRY_TOL) return;
            scratch.c[count].geometry=vec4(d/distance,gap,1.0/g.geom.w+1.0/src.g[j].geom.w);
            scratch.c[count].ids=ivec4(int(i),int(j),0,0);
            scratch.c[count++].reaction=vec4(0);
        }
        for(uint j=0u;j<p.planes;++j) {
            vec4 wall=walls.plane[j];
            if(any(isnan(wall))||any(isinf(wall))||abs(length(wall.xy)-1.0)>GEOMETRY_TOL) return;
            float gap=dot(wall.xy,g.geom.xy)-wall.z-g.geom.z;
            if(gap < -GEOMETRY_TOL) return;
            scratch.c[count].geometry=vec4(wall.xy,gap,1.0/g.geom.w);
            scratch.c[count].ids=ivec4(int(i),-1,0,0);
            scratch.c[count++].reaction=vec4(0);
        }
    }
#ifdef FULL_MOBILITY
    if(!valid_mobility())return;
    for(uint c=0u;c<count;++c) {
        vec2 n=scratch.c[c].geometry.xy;
        scratch.c[c].geometry.w=projected_mobility(scratch.c[c],n);
        scratch.c[c].reaction.z=projected_mobility(scratch.c[c],vec2(-n.y,n.x));
        if(scratch.c[c].geometry.w<=0.0||scratch.c[c].reaction.z<=0.0)return;
    }
    rebuild_velocity(count);
#endif
    bool converged=false;float residual=0.0;uint iterations=0u;
    for(uint iteration=0u;iteration<p.budget;++iteration) {
        for(uint c=0u;c<count;++c) {
            vec4 geometry=scratch.c[c].geometry;
            vec2 old=scratch.c[c].reaction.xy;
            float normal=max(0.0,old.x-(relative(c).x+geometry.z/p.dt)/geometry.w);
            apply_force(c,vec2(normal-old.x,0));
            float tangent=clamp(old.y-relative(c).y/tangent_mobility(c),-p.friction*normal,p.friction*normal);
            apply_force(c,vec2(0,tangent-old.y));
            scratch.c[c].reaction.xy=vec2(normal,tangent);
        }
#ifdef FULL_MOBILITY
        rebuild_velocity(count);
#endif
        residual=0.0;
        for(uint c=0u;c<count;++c) {
            vec4 geometry=scratch.c[c].geometry;vec2 old=scratch.c[c].reaction.xy;vec2 speed=relative(c);
            vec2 projected=vec2(max(0.0,old.x-(speed.x+geometry.z/p.dt)/geometry.w),clamp(old.y-speed.y/tangent_mobility(c),-p.friction*old.x,p.friction*old.x));
            residual=max(residual,max(geometry.w*abs(projected.x-old.x),tangent_mobility(c)*abs(projected.y-old.y)));
        }
        iterations=iteration+1u;
        if(residual<=TOL) {converged=true;break;}
    }
    status.state=uvec4(0,iterations,floatBitsToUint(residual),1);
    if(!converged||isnan(residual)||isinf(residual)) return;
    for(uint i=0u;i<p.grains;++i) {
        position[i]=src.g[i].geom.xy+p.dt*velocity[i];
        if(any(isnan(position[i]))||any(isinf(position[i]))) return;
        for(uint j=0u;j<i;++j) if(length(position[i]-position[j])+GEOMETRY_TOL<src.g[i].geom.z+src.g[j].geom.z) return;
        for(uint j=0u;j<p.planes;++j) if(dot(walls.plane[j].xy,position[i])+GEOMETRY_TOL<walls.plane[j].z+src.g[i].geom.z) return;
    }
    for(uint i=0u;i<p.grains;++i) {Grain g=src.g[i];g.geom.xy=position[i];dst.g[i]=g;}
    status.state=uvec4(1,iterations,floatBitsToUint(residual),0);
}
