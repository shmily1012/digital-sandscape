#[compute]
#version 450
#ifndef CONTACT_CAPACITY
#define CONTACT_CAPACITY 16
#endif
#define MATRIX_SIZE (2 * CONTACT_CAPACITY)
layout(local_size_x=1) in;
struct Grain {vec4 geom;vec4 props;};
struct Contact {vec4 geometry;ivec4 ids;vec4 reaction;};
layout(set=0,binding=0,std430) readonly buffer Grains {Grain g[];} grains;
layout(set=0,binding=1,std430) readonly buffer Contacts {Contact c[];} contacts;
layout(set=0,binding=2,std430) readonly buffer Selection {uint ids[];} selection;
layout(set=0,binding=3,std430) readonly buffer Assembly {uvec4 state;} assembly;
layout(set=0,binding=4,std430) readonly buffer Direction {float x[];} direction;
layout(set=0,binding=5,std430) readonly buffer SVD {uvec4 state;} svd;
layout(set=0,binding=6,std430) readonly buffer NullVector {float x[];} null_vector;
layout(set=0,binding=7,std430) writeonly buffer Output {Contact c[];} output_contacts;
layout(set=0,binding=8,std430) writeonly buffer Report {uvec4 state;vec4 metrics;} report;
layout(push_constant,std430) uniform Params {uint grains;uint contacts;float dt;float friction;vec2 gravity;float tolerance;uint pad;} p;
bool project_trial=false;
vec2 change[CONTACT_CAPACITY];vec2 velocity[16];vec2 correction[16];
vec2 force_at(uint k,float alpha) {
    precise vec2 lambda=contacts.c[k].reaction.xy;
    for(uint a=0u;a<assembly.state.y;++a)if(selection.ids[a]==k)lambda+=alpha*change[a];
    if(project_trial){lambda.x=max(0.0,lambda.x);lambda.y=clamp(lambda.y,-p.friction*lambda.x,p.friction*lambda.x);}
    return lambda;
}
void accumulate(uint i,vec2 f) {vec2 y=f-correction[i];vec2 next=velocity[i]+y;correction[i]=(next-velocity[i])-y;velocity[i]=next;}
vec2 evaluate(float alpha,bool cone) {
    for(uint i=0u;i<p.grains;++i) {Grain g=grains.g[i];velocity[i]=(g.props.x-1.0)*3.141592653589793*g.geom.z*g.geom.z*p.gravity;correction[i]=vec2(0);}
    for(uint k=0u;k<p.contacts;++k) {
        Contact c=contacts.c[k];vec2 lambda=force_at(k,alpha);
        if(cone && (lambda.x < -1e-10 || abs(lambda.y)>p.friction*lambda.x+1e-10))return vec2(1e30);
        vec2 f=c.geometry.xy*lambda.x+vec2(-c.geometry.y,c.geometry.x)*lambda.y;
        accumulate(uint(c.ids.x),f);if(c.ids.y>=0)accumulate(uint(c.ids.y),-f);
    }
    for(uint i=0u;i<p.grains;++i)velocity[i]/=grains.g[i].geom.w;
    float merit=0.0,maximum=0.0;
    for(uint k=0u;k<p.contacts;++k) {
        Contact c=contacts.c[k];vec2 lambda=force_at(k,alpha);vec2 v=velocity[c.ids.x];if(c.ids.y>=0)v-=velocity[c.ids.y];
        vec2 speed=vec2(dot(v,c.geometry.xy)+c.geometry.z/p.dt,dot(v,vec2(-c.geometry.y,c.geometry.x)));
        float bound=p.friction*max(0.0,lambda.x);
        vec2 projected=vec2(max(0.0,lambda.x-speed.x/c.geometry.w),clamp(lambda.y-speed.y/c.geometry.w,-bound,bound));
        vec2 f=(lambda-projected)*c.geometry.w;
        if(any(isnan(f))||any(isinf(f)))return vec2(1e30);
        merit+=dot(f,f);maximum=max(maximum,max(abs(f.x),abs(f.y)));
    }
    return vec2(merit,maximum);
}
void publish(uint mode,uint attempts,float alpha,vec2 before,vec2 after) {
    for(uint k=0u;k<p.contacts;++k){Contact c=contacts.c[k];c.reaction.xy=force_at(k,alpha);output_contacts.c[k]=c;}
    report.state=uvec4(mode,attempts,floatBitsToUint(before.y),floatBitsToUint(after.y));
    report.metrics=vec4(before.x,after.x,alpha,0);
}
void main() {
    report.state=uvec4(0);report.metrics=vec4(0);
    for(uint k=0u;k<p.contacts;++k)output_contacts.c[k]=contacts.c[k];
    if(assembly.state.x!=1u||svd.state.w!=0u||assembly.state.y>uint(CONTACT_CAPACITY)||p.grains>16u)return;
    for(uint a=0u;a<assembly.state.y;++a)change[a]=vec2(direction.x[2u*a],direction.x[2u*a+1u]);
    vec2 before=evaluate(0.0,false);
    // Project every candidate onto the friction cone, then re-evaluate.
    // A small residual alone does not guarantee admissible stored forces.
    project_trial=true;
    vec2 feasible=evaluate(0.0,true);
    if(feasible.y<=p.tolerance){publish(3u,0u,0.0,before,feasible);return;}
    float alpha=1.0;
    for(uint attempt=0u;attempt<20u;++attempt) {
        vec2 after=evaluate(alpha,false);
        if(after.x<before.x*(1.0-1e-4*alpha)){publish(1u,attempt+1u,alpha,before,after);return;}
        alpha*=0.5;
    }
    // Current bounded fallback supports a single null direction only.
    if(svd.state.x!=uint(MATRIX_SIZE-1)){report.state=uvec4(0,20,floatBitsToUint(before.y),floatBitsToUint(before.y));return;}
    project_trial=true;
    float best_merit=1e30;
    for(uint sign=0u;sign<2u;++sign) {
        float distance=1e30;
        for(uint a=0u;a<assembly.state.y;++a) {
            vec2 delta=vec2(null_vector.x[2u*a],null_vector.x[2u*a+1u])*(sign==0u ? -1.0 : 1.0);
            change[a]=delta;
            vec2 lambda=contacts.c[selection.ids[a]].reaction.xy;
            vec3 margins=vec3(lambda.x,p.friction*lambda.x-lambda.y,p.friction*lambda.x+lambda.y);
            vec3 slopes=vec3(delta.x,p.friction*delta.x-delta.y,p.friction*delta.x+delta.y);
            for(int j=0;j<3;++j)if(slopes[j]<-1e-8 && margins[j]>1e-12)distance=min(distance,margins[j]/-slopes[j]);
        }
        if(distance>=1e29)continue;
        vec2 after=evaluate(distance,true);
        best_merit=min(best_merit,after.x);
        if(after.x<=before.x*(1.0+1e-5)){publish(2u,21u+sign,distance,before,after);return;}
    }
    report.state=uvec4(0,22,floatBitsToUint(before.y),floatBitsToUint(before.y));
    report.metrics=vec4(before.x,best_merit,0,0);
}
