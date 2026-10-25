#[compute]
#version 450
layout(local_size_x=1) in;
struct Grain {vec4 geom;vec4 props;};
struct Contact {vec4 geometry;ivec4 ids;vec4 reaction;};
layout(set=0,binding=0,std430) readonly buffer Grains {Grain g[];} src;
layout(set=0,binding=1,std430) readonly buffer Contacts {Contact c[];} contacts;
layout(set=0,binding=2,std430) writeonly buffer Output {Grain g[];} dst;
layout(set=0,binding=3,std430) writeonly buffer Status {uvec4 state;} status;
layout(set=0,binding=4,std430) readonly buffer AssemblyGate {uvec4 state;} gate;
layout(push_constant,std430) uniform Params {uint grains;uint contacts;float dt;float friction;vec2 gravity;float tolerance;uint pad;} p;
vec2 velocity[16];vec2 compensation[16];vec2 position[16];
void add(uint i,vec2 f){vec2 y=f-compensation[i];vec2 next=velocity[i]+y;compensation[i]=(next-velocity[i])-y;velocity[i]=next;}
void main(){
    status.state=uvec4(0);
    if(p.grains==0u||p.grains>16u||p.contacts>1144u)return;
    for(uint i=0u;i<p.grains;++i){Grain g=src.g[i];dst.g[i]=g;velocity[i]=(g.props.x-1.0)*3.141592653589793*g.geom.z*g.geom.z*p.gravity;compensation[i]=vec2(0);}
    if(gate.state.x!=1u)return;
    for(uint k=0u;k<p.contacts;++k){
        Contact c=contacts.c[k];vec2 lambda=c.reaction.xy;
        if(any(isnan(lambda))||any(isinf(lambda))||lambda.x < -1e-10||abs(lambda.y)>p.friction*max(0.0,lambda.x)+1e-10)return;
        vec2 f=c.geometry.xy*lambda.x+vec2(-c.geometry.y,c.geometry.x)*lambda.y;
        add(uint(c.ids.x),f);if(c.ids.y>=0)add(uint(c.ids.y),-f);
    }
    for(uint i=0u;i<p.grains;++i){velocity[i]/=src.g[i].geom.w;position[i]=src.g[i].geom.xy+p.dt*velocity[i];if(any(isnan(position[i]))||any(isinf(position[i])))return;}
    float maximum=0.0;
    for(uint k=0u;k<p.contacts;++k){
        Contact c=contacts.c[k];vec2 v=velocity[c.ids.x];if(c.ids.y>=0)v-=velocity[c.ids.y];vec2 lambda=c.reaction.xy;
        vec2 speed=vec2(dot(v,c.geometry.xy)+c.geometry.z/p.dt,dot(v,vec2(-c.geometry.y,c.geometry.x)));
        vec2 projected=vec2(max(0.0,lambda.x-speed.x/c.geometry.w),clamp(lambda.y-speed.y/c.geometry.w,-p.friction*max(0.0,lambda.x),p.friction*max(0.0,lambda.x)));
        vec2 residual=(lambda-projected)*c.geometry.w;
        maximum=max(maximum,max(abs(residual.x),abs(residual.y)));
        if(c.ids.y>=0){if(length(position[c.ids.x]-position[c.ids.y])+2e-7<src.g[c.ids.x].geom.z+src.g[c.ids.y].geom.z)return;}
        else if(c.geometry.z+dot(c.geometry.xy,position[c.ids.x]-src.g[c.ids.x].geom.xy)<-2e-7)return;
    }
    status.state=uvec4(0,floatBitsToUint(maximum),0,0);
    if(maximum>p.tolerance||isnan(maximum)||isinf(maximum))return;
    for(uint i=0u;i<p.grains;++i){Grain g=src.g[i];g.geom.xy=position[i];dst.g[i]=g;}
    status.state=uvec4(1,floatBitsToUint(maximum),floatBitsToUint(p.dt),0);
}
