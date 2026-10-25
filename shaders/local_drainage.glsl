#[compute]
#version 450
// Bounded Jacobi-preconditioned CG for face-aperture-weighted local drainage.
// Pressure and flux remain candidates; this does not advance fluid or grains.
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Geometry { vec4 geometry[]; };
layout(set=0,binding=1,std430) readonly buffer Aperture { vec2 aperture[]; };
layout(set=0,binding=2,std430) buffer State { vec4 state[]; }; // p,r,z,d
layout(set=0,binding=3,std430) buffer Applied { float applied[]; };
layout(set=0,binding=4,std430) buffer Partial { vec2 partial[]; };
layout(set=0,binding=5,std430) buffer Control { vec4 control; }; // rho,alpha,beta,mode
layout(set=0,binding=6,std430) writeonly buffer Flux { vec2 flux[]; };
layout(set=0,binding=7,std430) buffer Status { uint status[]; };
layout(set=0,binding=8,std430) buffer ContactStatus { uint contact_status[]; };
layout(push_constant,std430) uniform Params { uint side;uint mode;float tolerance;uint groups; } p;
shared float sums[64];shared float maxima[64];
vec4 weights(uint i){return vec4(i%p.side>0u?aperture[i-1u].x:0.,i%p.side+1u<p.side?aperture[i].x:0.,i>=p.side?aperture[i-p.side].y:0.,i+p.side<p.side*p.side?aperture[i].y:0.);}
float rhs(uint i){return -(geometry[i].z+geometry[i].w-(i%p.side>0u?geometry[i-1u].z:0.)-(i>=p.side?geometry[i-p.side].w:0.));}
float laplacian(uint i,int channel){
    vec4 w=weights(i);float x=state[i][channel],sum=0.;
    if(w.x>0.)sum+=w.x*(x-state[i-1u][channel]);
    if(w.y>0.)sum+=w.y*(x-state[i+1u][channel]);
    if(w.z>0.)sum+=w.z*(x-state[i-p.side][channel]);
    if(w.w>0.)sum+=w.w*(x-state[i+p.side][channel]);
    return sum;
}
bool finite1(float x){return !isnan(x)&&!isinf(x);}
void main(){
    uint i=gl_GlobalInvocationID.x,lane=gl_LocalInvocationID.x;
    if(p.mode==9u){if(i==0u){control=vec4(0);for(uint k=0u;k<4u;k++)status[k]=0u;}return;}
    if(p.mode==1u||p.mode==3u||p.mode==5u||p.mode==8u||p.mode==13u){
        if(i!=0u)return;
        float sum=0.,maximum=0.;
        for(uint k=0u;k<p.groups;k++){sum+=partial[k].x;maximum=p.mode==13u?maximum+partial[k].y:max(maximum,partial[k].y);}
        if(p.mode==13u){control.y=maximum>0.?sum/maximum:0.;return;}
        if(p.mode==1u){control.x=sum;control.w=maximum<=p.tolerance?1.:0.;if(status[3]!=0u)control.w=2.;}
        if(p.mode==3u){
            if(control.w==0.){if(sum<=0.||!finite1(sum))control.w=2.;else control.y=control.x/sum;}
            else if(control.w==1.&&maximum>p.tolerance){control.x=sum;control.z=0.;control.w=3.;}
        }
        if(p.mode==5u&&control.w==3.)control.w=0.;
        else if(p.mode==5u&&control.w==0.){
            status[2]++;
            if(!finite1(sum)||!finite1(maximum))control.w=2.;
            else if(maximum<=p.tolerance)control.w=1.;
            else{control.z=sum/control.x;control.x=sum;}
        }
        if(p.mode==8u){
            status[0]=floatBitsToUint(maximum);
            status[1]=(maximum<=p.tolerance&&control.w!=2.&&status[3]==0u&&contact_status[1]==0u)?1u:0u;
            if(status[1]==0u)atomicOr(contact_status[1],2u);
        }
        return;
    }
    if(p.mode==6u){if(i<p.side*p.side&&control.w==0.)state[i].w=state[i].z+control.z*state[i].w;return;}
    if(p.mode==14u){if(i<p.side*p.side&&dot(weights(i),vec4(1))>0.)state[i].x-=control.y;return;}
    float sum=0.,maximum=0.;
    if(i<p.side*p.side){
        if(p.mode==12u&&dot(weights(i),vec4(1))>0.){sum=state[i].x;maximum=1.;}
        if(p.mode==0u){
            float r=rhs(i),diagonal=dot(weights(i),vec4(1));float z=diagonal>0.?r/diagonal:0.;
            state[i]=vec4(0,r,z,z);sum=r*z;maximum=abs(r);
            if(!finite1(r)||!finite1(z)||(diagonal==0.&&abs(r)>p.tolerance))atomicOr(status[3],1u);
        }
        if(p.mode==2u&&control.w==0.){float value=laplacian(i,3);applied[i]=value;sum=state[i].w*value;}
        if(p.mode==2u&&control.w==1.){
            // Recurrence residual can drift in float32. Verify against A*p,
            // and restart within the original iteration budget when necessary.
            float r=rhs(i)-laplacian(i,0),diagonal=dot(weights(i),vec4(1));
            float z=diagonal>0.?r/diagonal:0.;state[i].y=r;state[i].z=z;state[i].w=z;
            sum=r*z;maximum=abs(r);
        }
        if(p.mode==4u&&control.w==0.){
            state[i].x+=control.y*state[i].w;state[i].y-=control.y*applied[i];
            float diagonal=dot(weights(i),vec4(1));state[i].z=diagonal>0.?state[i].y/diagonal:0.;
            sum=state[i].y*state[i].z;maximum=abs(state[i].y);
        }
        if(p.mode==7u){
            vec2 q=vec2(0);float pressure=state[i].x;
            if(i%p.side+1u<p.side)q.x=aperture[i].x*(pressure-state[i+1u].x);
            if(i+p.side<p.side*p.side)q.y=aperture[i].y*(pressure-state[i+p.side].x);
            flux[i]=q;maximum=abs(laplacian(i,0)-rhs(i));
            if(!finite1(maximum)||any(isnan(q))||any(isinf(q))){atomicOr(status[3],2u);maximum=3.4e38;}
        }
    }
    sums[lane]=sum;maxima[lane]=maximum;barrier();
    for(uint stride=32u;stride>0u;stride/=2u){if(lane<stride){sums[lane]+=sums[lane+stride];maxima[lane]=p.mode==12u?maxima[lane]+maxima[lane+stride]:max(maxima[lane],maxima[lane+stride]);}barrier();}
    if(lane==0u)partial[gl_WorkGroupID.x]=vec2(sums[0],maxima[0]);
}
