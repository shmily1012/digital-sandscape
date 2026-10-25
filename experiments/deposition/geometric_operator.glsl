#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Grains { vec4 grain[]; };
layout(set=0,binding=1,std430) readonly buffer Velocities { vec2 velocity[]; };
layout(set=0,binding=2,std430) readonly buffer Faces { uvec4 face[]; };
layout(set=0,binding=3,std430) readonly buffer Mask { uint cell_mask[]; };
layout(set=0,binding=4,std430) readonly buffer Liquid { float q[]; };
layout(set=0,binding=5,std430) readonly buffer Mobility { float mobility[]; };
layout(set=0,binding=6,std430) buffer Source { float source[]; };
layout(set=0,binding=7,std430) buffer Adjoint { vec2 adjoint[]; };
layout(set=0,binding=8,std430) buffer Flags { uint valid[]; };
layout(set=0,binding=9,std430) buffer Status { uint accepted; };
layout(set=0,binding=10,std430) buffer CandidateSource { float candidate_source[]; };
layout(set=0,binding=11,std430) buffer CandidateAdjoint { vec2 candidate_adjoint[]; };
layout(push_constant,std430) uniform Params { uint count; uint faces; uint side; uint phase; } pc;
bool finite1(float a){return !isnan(a)&&!isinf(a);}
float aperture(uint f,vec4 g){
    uvec4 e=face[f];float h=1./float(pc.side);
    float normal,low;
    if(e.z==0u){normal=float(e.x%pc.side+1u)*h-g.x;low=float(e.x/pc.side)*h-g.y;}
    else{normal=float(e.x/pc.side+1u)*h-g.y;low=float(e.x%pc.side)*h-g.x;}
    float d=abs(normal);
    float half_width=d<g.z?sqrt(max(0.,(g.z-d)*(g.z+d))):0.;
    return max(0.,min(low+h,half_width)-max(low,-half_width))/h;
}
void main(){
    uint i=gl_GlobalInvocationID.x;uint total=max(pc.count,pc.faces);float h=1./float(pc.side);
    if(pc.phase==1u || pc.phase==3u){
        if(i!=0u)return;
        uint ok=1u;for(uint j=0u;j<total;j++)ok &= valid[j];accepted=ok;return;
    }
    if(i>=total)return;
    if(pc.phase==4u){
        if(accepted==1u){
            if(i<pc.faces)source[i]=candidate_source[i];
            if(i<pc.count)adjoint[i]=candidate_adjoint[i];
        }
        return;
    }
    if(pc.phase==0u){
        bool ok=true;
        if(i<pc.count){
            vec4 g=grain[i];vec2 v=velocity[i];
            ok=finite1(g.x)&&finite1(g.y)&&finite1(g.z)&&g.z>0.&&finite1(v.x)&&finite1(v.y);
            ok=ok&&g.x-g.z>=0.&&g.y-g.z>=0.&&g.x+g.z<=1.&&g.y+g.z<=1.;
            if(ok){
                for(uint j=0u;j<pc.count;j++)if(j!=i){
                    float r=g.z+grain[j].z;
                    if(distance(g.xy,grain[j].xy)<r-1e-7)ok=false;
                }
                ivec2 lo=clamp(ivec2(floor((g.xy-g.z)/h)),ivec2(0),ivec2(pc.side-1u));
                ivec2 hi=clamp(ivec2(floor((g.xy+g.z)/h)),ivec2(0),ivec2(pc.side-1u));
                for(int y=lo.y;y<=hi.y;y++)for(int x=lo.x;x<=hi.x;x++){
                    if(cell_mask[y*int(pc.side)+x]!=0u)continue;
                    vec2 nearest=clamp(g.xy,vec2(x,y)*h,vec2(x+1,y+1)*h);
                    if(distance(g.xy,nearest)<g.z-1e-7)ok=false;
                }
            }
        }
        if(i<pc.faces){
            uvec4 e=face[i];
            ok=ok&&finite1(q[i])&&finite1(mobility[i])&&mobility[i]>0.;
            ok=ok&&e.x<pc.side*pc.side&&e.y<pc.side*pc.side&&e.z<=1u;
        }
        valid[i]=ok?1u:0u;return;
    }
    if(accepted!=1u)return;
    valid[i]=1u;
    if(i<pc.faces){
        precise float value=0.;uint axis=face[i].z;
        for(uint j=0u;j<pc.count;j++)value+=aperture(i,grain[j])*velocity[j][axis];
        candidate_source[i]=value;
        if(!finite1(value))valid[i]=0u;
    }
    if(i<pc.count){
        precise vec2 force=vec2(0.);
        for(uint f=0u;f<pc.faces;f++)force[face[f].z]-=aperture(f,grain[i])*h*h*q[f]/mobility[f];
        candidate_adjoint[i]=force;
        if(!finite1(force.x)||!finite1(force.y))valid[i]=0u;
    }
}
