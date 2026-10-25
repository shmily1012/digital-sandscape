#[compute]
#version 450
layout(local_size_x=64) in;
struct Spring { ivec2 ids; float xi; float k; };
struct InputData { ivec2 ids; vec2 motion; vec4 config; };
struct Metrics { vec4 a; vec4 b; };
layout(set=0,binding=0,std430) buffer State { Spring state[]; };
layout(set=0,binding=1,std430) readonly buffer Inputs { InputData input_data[]; };
layout(set=0,binding=2,std430) buffer Candidates { Spring candidate[]; };
layout(set=0,binding=3,std430) buffer CandidateMetrics { Metrics candidate_metrics[]; };
layout(set=0,binding=4,std430) buffer PublishedMetrics { Metrics published_metrics[]; };
layout(set=0,binding=5,std430) buffer Flags { uint valid[]; };
layout(set=0,binding=6,std430) buffer Status { uint accepted; };
layout(push_constant,std430) uniform Params { uint count; uint phase; uint pad0; uint pad1; } pc;
bool finite4(vec4 v) {return !any(isnan(v)) && !any(isinf(v));}
void main() {
    uint i=gl_GlobalInvocationID.x;
    if(pc.phase==1u) {
        if(i!=0u)return;
        uint ok=1u;
        for(uint j=0u;j<pc.count;j++)ok &= valid[j];
        accepted=ok;return;
    }
    if(i>=pc.count)return;
    if(pc.phase==2u) {
        if(accepted==1u){state[i]=candidate[i];published_metrics[i]=candidate_metrics[i];}
        return;
    }
    valid[i]=0u;
    Spring old=state[i]; InputData data=input_data[i];
    float slip=data.motion.x, normal=data.motion.y, k=data.config.x, mu=data.config.y;
    if(any(notEqual(old.ids,data.ids)) || old.ids.x>=old.ids.y || k!=old.k || k<=0. || normal<0. || mu<0.)return;
    if(!finite4(vec4(old.xi,old.k,slip,normal)) || !finite4(data.config))return;
    if(data.config.z!=0. && data.config.z!=1.)return;
    float xi=0.,force=0.,energy=0.,plastic=0.,implicit_loss=0.,work=0.,release=0.;
    if(data.config.z==0.)release=.5*k*old.xi*old.xi;
    else {
        float trial=old.xi+slip;
        float limit=mu*normal/k;
        xi=clamp(trial,-limit,limit);
        force=-k*xi;energy=.5*k*xi*xi;
        plastic=k*xi*(trial-xi);
        implicit_loss=.5*k*(xi-old.xi)*(xi-old.xi);
        work=-force*slip;
    }
    vec4 a=vec4(force,energy,plastic,implicit_loss),b=vec4(work,release,0.,0.);
    if(!finite4(a) || !finite4(b) || isnan(xi) || isinf(xi))return;
    candidate[i]=Spring(old.ids,xi,k);
    candidate_metrics[i]=Metrics(a,b);valid[i]=1u;
}
