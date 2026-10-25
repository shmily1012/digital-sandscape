#[compute]
#version 450
layout(local_size_x=64) in;
struct Grain { vec4 geom; vec4 props; }; // x,y,radius,drag; density,material,reserved,reserved
struct Face { uint a; uint b; float mobility; float source; };
struct Equation { vec4 weights; vec4 source; };
layout(set=0,binding=0,std430) readonly restrict buffer Input { Grain g[]; } src;
layout(set=0,binding=1,std430) restrict buffer Candidate { Grain g[]; } candidate;
layout(set=0,binding=2,std430) writeonly restrict buffer Output { Grain g[]; } dst;
layout(set=0,binding=3,std430) restrict buffer Normalization { vec2 w[]; } norm;
layout(set=0,binding=4,std430) restrict buffer Faces { Face f[]; } faces;
layout(set=0,binding=5,std430) restrict buffer Equations { Equation cell[]; } equations;
layout(set=0,binding=6,std430) readonly restrict buffer Pressure { float p[]; } pressure;
layout(set=0,binding=7,std430) readonly restrict buffer Control { uint word[]; } control;
layout(set=0,binding=8,std430) restrict buffer Validity { uint ok[]; } validity;
layout(set=0,binding=9,std430) readonly restrict buffer Adjacency { ivec4 ids[]; } adjacency;
layout(set=0,binding=10,std430) readonly restrict buffer SelfResponse { vec4 k[]; } self_response;
layout(push_constant,std430) uniform Params { uint grains; uint faces; uint side; uint phase; vec2 gravity; float dt; uint pad; } p;
float component(vec2 v,uint axis) { return axis==0u ? v.x : v.y; }
uint axis_of(Face f) { return f.b-f.a==1u ? 0u : 1u; }
float weight(Face f,vec2 position) {
    vec2 a=vec2(f.a%p.side,f.a/p.side),b=vec2(f.b%p.side,f.b/p.side);
    vec2 center=((a+b)*0.5+0.5)/float(p.side);
    vec2 w=max(vec2(0.0),1.0-abs(center-position)*float(p.side)*0.5);
    return w.x*w.y;
}
vec2 external_force(Grain g) { return (g.props.x-1.0)*3.141592653589793*g.geom.z*g.geom.z*p.gravity; }
void main() {
    uint i=gl_GlobalInvocationID.x;
    if(p.phase==0u) {
        if(i>=p.grains) return;
        vec2 total=vec2(0.0);
        for(uint f=0u;f<p.faces;++f) total+=(axis_of(faces.f[f])==0u ? vec2(1,0) : vec2(0,1))*weight(faces.f[f],src.g[i].geom.xy);
        norm.w[i]=total;
    } else if(p.phase==1u) {
        if(i>=p.faces) return;
        Face f=faces.f[i];uint axis=axis_of(f);
        float force=0.0;
        for(uint g=0u;g<p.grains;++g) force+=weight(f,src.g[g].geom.xy)/component(norm.w[g],axis)*component(external_force(src.g[g]),axis);
        faces.f[i].source=f.mobility*force*float(p.side*p.side);
    } else if(p.phase==2u) {
        if(i>=p.side*p.side) return;
        float divergence=0.0;
        for(int k=0;k<4;++k) {
            int id=adjacency.ids[i][k];
            if(id>=0) { Face f=faces.f[id];divergence+=(f.a==i ? 1.0 : -1.0)*f.source*float(p.side); }
        }
        equations.cell[i].source.x=-divergence;
    } else if(p.phase==3u) {
        if(i>=p.grains) return;
        Grain g=src.g[i];vec2 fluid=vec2(0.0);
        for(uint id=0u;id<p.faces;++id) {
            Face f=faces.f[id];uint axis=axis_of(f);
            float u=f.source-f.mobility*(pressure.p[f.b]-pressure.p[f.a])*float(p.side);
            fluid+=(axis==0u ? vec2(1,0) : vec2(0,1))*weight(f,g.geom.xy)/component(norm.w[i],axis)*u;
        }
        vec2 f=external_force(g);
        vec4 k=self_response.k[i];
        vec2 own=vec2(dot(k.xy,f),dot(k.zw,f));
        g.geom.xy+=p.dt*(fluid-own+f/g.geom.w);
        bool finite=!(any(isnan(g.geom.xy))||any(isinf(g.geom.xy)));
        validity.ok[i]=finite && length(g.geom.xy-0.5)+g.geom.z<=0.46 && control.word[1]==1u && control.word[3]==0u ? 1u : 0u;
        candidate.g[i]=g;
    } else {
        if(i>=p.grains) return;
        bool accepted=true;
        for(uint g=0u;g<p.grains;++g) accepted=accepted && validity.ok[g]==1u;
        dst.g[i]=accepted ? candidate.g[i] : src.g[i];
    }
}

