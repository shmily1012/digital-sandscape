#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,std430) buffer Gas { float c[]; };
layout(set=0,binding=1,std430) buffer Fluid { float f[]; };
// 0 fluid, 1 permanent wall, 2/3/4 mineral classes.
layout(set=0,binding=2,std430) buffer Material { uint material[]; };
layout(set=0,binding=3,std430) buffer Traction { vec2 traction[]; };
layout(set=0,binding=4,std430) buffer MassResidual { float mass_residual[]; };
layout(push_constant,std430) uniform Params {
    uint side;uint seed;uint tick;uint phase;int gx;int gy;float gravity_scale;uint drag_divisor;
} p;
const ivec2 O[4]=ivec2[4](ivec2(0,0),ivec2(1,0),ivec2(0,1),ivec2(1,1));
uint hash32(uint x){x^=x<<13;x^=x>>17;x^=x<<5;return x;}
void main(){
    ivec2 block=ivec2(gl_GlobalInvocationID.xy),base=2*block-ivec2(p.phase);
    if(any(greaterThanEqual(base,ivec2(p.side))))return;
    uint m[4];int index[4];ivec2 drive[4];
    for(int a=0;a<4;a++){
        ivec2 q=base+O[a];index[a]=-1;m[a]=1u;
        if(all(greaterThanEqual(q,ivec2(0)))&&all(lessThan(q,ivec2(p.side)))){
            index[a]=q.y*int(p.side)+q.x;m[a]=material[index[a]];
        }
    }
    uint rng=hash32(p.seed^(p.tick*747796405u)^(p.phase*2891336453u)^(uint(block.x)*277803737u)^(uint(block.y)*1597334677u));
    uint total=0u;int source=-1,target=-1;
    ivec2 down=abs(p.gx)>abs(p.gy)?ivec2(sign(p.gx),0):ivec2(0,sign(p.gy));
    // Effective mobility is referenced to the same lattice acceleration as the fluid.
    // Do not erase force magnitude by normalizing gravity before the hop rate.
    float strength=clamp(p.gravity_scale/0.00002,0.,4.);
    for(int a=0;a<4;a++){
        if(m[a]<2u)continue;
        float relative_weight=m[a]==2u?2.0:(m[a]==3u?1.7:1.4);
        vec2 response=traction[index[a]]/(relative_weight*0.00002);
        drive[a]=ivec2(round(vec2(p.gx,p.gy)*strength))+ivec2(round(clamp(response,vec2(-4),vec2(4))*32767.));
        bool supported=false;
        // A gas-blocked downward move can release into adjacent liquid, just as
        // a solid-blocked move can. This is geometric mobility, not a contact force.
        for(int s=0;s<4;s++)if(O[s]==O[a]+down){
            if(m[s]!=0u)supported=true;
            else if(c[index[s]]>0.05)supported=true;
        }
        for(int b=0;b<4;b++){
            if(m[b]!=0u||c[index[b]]>0.05)continue;
            ivec2 d=O[b]-O[a];int length1=abs(d.x)+abs(d.y),projection=d.x*drive[a].x+d.y*drive[a].y;
            // A diagonal endpoint is not a passage through two blocked corners.
            // Require a liquid cardinal route within this exclusively owned block.
            if(length1==2){
                bool route=false;
                for(int s=0;s<4;s++)if(O[s]==O[a]+ivec2(d.x,0)||O[s]==O[a]+ivec2(0,d.y)){
                    if(m[s]==0u && c[index[s]]<=0.05)route=true;
                }
                if(!route)continue;
            }
            if(projection<=0 || (length1==2 && (!supported||float(projection)<=6000.*float(length1)*strength)))continue;
            uint weight=uint(projection);total+=weight;rng=hash32(rng+0x9e3779b9u);
            if(rng%total<weight){source=a;target=b;}
        }
    }
    if(source<0)return;
    rng=hash32(rng+0x9e3779b9u);
    uint mobility=m[source]==2u?12u:(m[source]==3u?9u:6u);
    mobility=uint(round(float(mobility)*clamp(length(vec2(drive[source]))/32767.,0.,4.)));
    // Swap the byte order so divisor=1 preserves the original acceptance exactly.
    // A 16-bit threshold represents slow motion without rounding it to a full stop.
    uint divisor=max(p.drag_divisor,1u);
    uint threshold=(mobility*256u+divisor/2u)/divisor;
    uint sample16=((rng&255u)<<8u)|((rng>>8u)&255u);
    if(sample16>=threshold)return;
    int a=index[source],b=index[target];
    // Moving a resolved voxel transports displaced fluid into the vacated cell.
    // All values are exchanged; neither gas nor LBM populations are recreated.
    material[b]=m[source];material[a]=0u;
    // The force was sampled before streaming, on the old grain geometry.
    // Do not replace it with the destination liquid's force in partition two.
    vec2 force=traction[a];traction[a]=traction[b];traction[b]=force;
    float gas=c[a];c[a]=c[b];c[b]=gas;
    float residual=mass_residual[a];mass_residual[a]=mass_residual[b];mass_residual[b]=residual;
    for(int q=0;q<9;q++){float value=f[9*a+q];f[9*a+q]=f[9*b+q];f[9*b+q]=value;}
}
