#[compute]
#version 450
layout(local_size_x=64) in;
struct Face { uint a; uint b; float mobility; float source; };
struct Equation { vec4 weights; vec4 source; };
layout(set=0,binding=0,std430) readonly restrict buffer Fraction { float c[]; } gas;
layout(set=0,binding=1,std430) restrict buffer Faces { Face f[]; } faces;
layout(set=0,binding=2,std430) readonly restrict buffer Adjacency { ivec4 f[]; } adjacency;
layout(set=0,binding=3,std430) restrict buffer Equations { Equation cell[]; } equations;
layout(set=0,binding=4,std430) readonly restrict buffer Curvature { vec2 value[]; } curvature;
layout(push_constant,std430) uniform Params { uint side; uint count; uint phase; float strength; vec2 gravity; float tension; float reference; } p;
void main() {
    uint i=gl_GlobalInvocationID.x;
    if(p.phase==0u) {
        if(i>=p.count) return;
        Face f=faces.f[i];
        float g=f.b-f.a==1u ? p.gravity.x : p.gravity.y;
        // Hydrostatic liquid reference removed; lighter gas drives opposite gravity.
        faces.f[i].source=-f.mobility*p.strength*g*0.5*(gas.c[f.a]+gas.c[f.b]);
        float delta=gas.c[f.b]-gas.c[f.a];
        if(p.tension>0.0 && abs(delta)>=1e-14) {
            vec2 a=curvature.value[f.a],b=curvature.value[f.b];
            float count=a.y+b.y;
            bool pure=max(gas.c[f.a],gas.c[f.b])<=1e-6 || min(gas.c[f.a],gas.c[f.b])>=1.0-1e-6;
            if(count>0.0) {
                float kappa=(a.x*a.y+b.x*b.y)/count-p.reference;
                faces.f[i].source+=f.mobility*p.tension*kappa*delta*float(p.side);
            } else if(!pure) {
                faces.f[i].source=uintBitsToFloat(0x7fc00000u);
            }
        }
    } else {
        if(i>=p.side*p.side) return;
        float divergence=0.0;
        for(int k=0;k<4;++k) {
            int id=adjacency.f[i][k];
            if(id>=0) {
                Face f=faces.f[id];
                divergence+=(f.a==i ? 1.0 : -1.0)*f.source*float(p.side);
            }
        }
        equations.cell[i].source.x=-divergence;
    }
}
