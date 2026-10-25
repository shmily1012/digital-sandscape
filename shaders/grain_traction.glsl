#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Populations { float f[]; };
layout(set=0,binding=1,std430) readonly buffer Material { uint material[]; };
layout(set=0,binding=2,std430) writeonly buffer Traction { vec2 traction[]; };
layout(set=0,binding=3,std430) readonly buffer BoundaryVelocity { vec2 boundary_velocity[]; };
layout(set=0,binding=4,std430) readonly buffer InterfaceForce { vec2 interface_force[]; };
// mode 0: excess estimator; mode 1: stationary impulse; mode 2: moving-wall impulse.
layout(push_constant,std430) uniform Params { uint side;uint mode;uint pad1;uint pad2; } p;
const ivec2 E[8]=ivec2[8](ivec2(1,0),ivec2(0,1),ivec2(-1,0),ivec2(0,-1),ivec2(1,1),ivec2(-1,1),ivec2(-1,-1),ivec2(1,-1));
const int O[8]=int[8](3,4,1,2,7,8,5,6);
const float W[8]=float[8](1./9.,1./9.,1./9.,1./9.,1./36.,1./36.,1./36.,1./36.);
void main(){
    int i=int(gl_GlobalInvocationID.x);if(i>=int(p.side*p.side))return;
    traction[i]=vec2(0);if(material[i]==0u || (p.mode==0u && material[i]==1u))return;
    ivec2 xy=ivec2(i%int(p.side),i/int(p.side));
    int neighbors[8];float background=0.;int count=0;
    for(int q=0;q<8;q++){
        ivec2 at=xy+E[q];neighbors[q]=-1;
        if(any(lessThan(at,ivec2(0)))||any(greaterThanEqual(at,ivec2(p.side))))continue;
        int j=at.y*int(p.side)+at.x;if(material[j]!=0u)continue;
        neighbors[q]=j;float rho=0.;for(int k=0;k<9;k++)rho+=f[9*j+k];
        background+=rho;count++;
    }
    if(count==0)return;background/=float(count);
    vec2 force=vec2(0);
    for(int q=0;q<8;q++)if(neighbors[q]>=0){
        // Raw impulses retain ambient pressure, including on partially exposed solids.
        // They must be sampled BEFORE the matching fluid streaming/collision step.
        float ambient=p.mode==0u?W[q]*background:0.;
        force-=2.*vec2(E[q])*(f[9*neighbors[q]+O[q]]-ambient);
        if(p.mode==2u){
            float rho=0.;for(int k=0;k<9;k++)rho+=f[9*neighbors[q]+k];
            force-=6.*W[q]*rho*vec2(E[q])*dot(vec2(E[q]),boundary_velocity[i]);
        }
    }
    traction[i]=force+(p.pad1!=0u?interface_force[i]:vec2(0));
}
