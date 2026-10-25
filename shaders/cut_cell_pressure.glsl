#[compute]
#version 450
// Bounded CG vector/reduction stages. Acceptance uses a fresh A*x evaluation.
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) buffer Candidate { float x[]; };
layout(set=0,binding=1,std430) buffer Direction { float d[]; };
layout(set=0,binding=2,std430) buffer Residual { float r[]; };
layout(set=0,binding=3,std430) readonly buffer Applied { vec2 applied[]; }; // A*v, rhs
layout(set=0,binding=4,std430) buffer Partial { vec2 partial[]; };
layout(set=0,binding=5,std430) buffer Control { vec4 control; }; // rho,alpha,beta,mode
// Modes: 0 active, 1 recurrence converged, 2 rejected, 3 restart, 4 verified.
// Flags: 1 invalid arithmetic/breakdown, 2 incompatible source, 4 generation overflow.
layout(set=0,binding=6,std430) buffer Status { uint status[]; }; // accepted,flags,updates,residual,restarts,verifications,reserved[2]
layout(set=0,binding=7,std430) buffer Published { float solution[]; };
layout(set=0,binding=8,std430) readonly buffer ComponentRows { uint component_rows[]; };
layout(set=0,binding=9,std430) readonly buffer ComponentIds { uint component_ids[]; };
layout(set=0,binding=10,std430) readonly buffer CandidateForce { vec2 candidate_force[]; };
layout(set=0,binding=11,std430) buffer PublishedForce { vec2 solution_force[]; };
layout(set=0,binding=12,std430) buffer Generation { uint generation[]; };
layout(set=0,binding=13,std430) buffer CandidateLow { float x_low[]; };
layout(set=0,binding=14,std430) buffer PublishedLow { float solution_low[]; };
layout(set=0,binding=15,std430) readonly buffer AppliedLow { vec2 applied_low[]; };
layout(set=0,binding=16,std430) readonly buffer CandidateForceLow { vec2 candidate_force_low[]; };
layout(set=0,binding=17,std430) buffer PublishedForceLow { vec2 solution_force_low[]; };
layout(push_constant,std430) uniform Params { uint nodes;uint mode;uint groups;float tolerance;uint components;uint grains;uint pad1;uint pad2; } p;
shared float sums[64];shared float maxima[64];
bool finite1(float v){return !isnan(v)&&!isinf(v);}
vec2 two_sum(float a,float b){precise float s=a+b;precise float v=s-a;precise float e=(a-(s-v))+(b-v);return vec2(s,e);}
vec2 ds_add(vec2 a,vec2 b){vec2 s=two_sum(a.x,b.x);precise float e=(s.y+a.y)+b.y;return two_sum(s.x,e);}
vec2 ds_mul(vec2 a,float b){precise float h=a.x*b;precise float l=fma(a.x,b,-h)+a.y*b;return two_sum(h,l);}
float true_residual(uint i){vec2 r=ds_add(vec2(applied[i].y,applied_low[i].y),-vec2(applied[i].x,applied_low[i].x));return r.x+r.y;}
void main(){
    uint i=gl_GlobalInvocationID.x,lane=gl_LocalInvocationID.x;
    if(p.mode==12u){if(i==0u&&status[0]==1u)generation[0]++;return;}
    if(p.mode==13u){
        if(i<p.grains&&(any(isnan(candidate_force[i]))||any(isinf(candidate_force[i]))||any(isnan(candidate_force_low[i]))||any(isinf(candidate_force_low[i]))))atomicOr(status[1],1u);
        return;
    }
    if(p.mode==11u){
        uint component=gl_WorkGroupID.x;
        if(component>=p.components)return;
        uint begin=component_rows[component],end=component_rows[component+1u];
        precise float sum=0.,carry=0.;float magnitude=0.;
        for(uint k=begin+lane;k<end;k+=64u){
            float value=applied[component_ids[k]].y;
            precise float term=value-carry;precise float next=sum+term;
            carry=(next-sum)-term;sum=next;magnitude+=abs(value);
        }
        sums[lane]=sum;maxima[lane]=magnitude;barrier();
        for(uint stride=32u;stride>0u;stride/=2u){if(lane<stride){sums[lane]+=sums[lane+stride];maxima[lane]+=maxima[lane+stride];}barrier();}
        // Necessary compatibility at the requested per-node residual tolerance.
        // Do not subtract a source mean or alter the physical equation.
        if(lane==0u){
            if(!finite1(sums[0])||!finite1(maxima[0]))atomicOr(status[1],1u);
            else if(abs(sums[0])>float(end-begin)*p.tolerance+8.*1.1920929e-7*maxima[0])atomicOr(status[1],2u);
        }
        return;
    }
    if(p.mode==0u){
        if(i<p.nodes){x[i]=0.;x_low[i]=0.;d[i]=0.;r[i]=0.;}
        if(i==0u){control=vec4(0);for(uint k=0u;k<8u;k++)status[k]=0u;}
        return;
    }
    if(p.mode==2u||p.mode==4u||p.mode==6u||p.mode==9u){
        if(i!=0u)return;
        float sum=0.,maximum=0.;
        for(uint k=0u;k<p.groups;k++){sum+=partial[k].x;maximum=max(maximum,partial[k].y);}
        if(p.mode==2u){control.x=sum;control.w=status[1]!=0u?2.:(maximum<=p.tolerance?1.:0.);}
        if(p.mode==4u&&control.w==0.){
            if(sum<=0.||!finite1(sum)){control.w=2.;status[1]|=1u;}
            else control.y=control.x/sum;
        }
        else if(p.mode==4u&&control.w==1.){
            status[5]++;
            if(status[1]!=0u||!finite1(sum)||!finite1(maximum)){control.w=2.;status[1]|=1u;}
            else if(maximum<=p.tolerance)control.w=4.;
            else{control.x=sum;control.z=0.;control.w=3.;status[4]++;}
        }
        if(p.mode==6u&&control.w==3.)control.w=0.;
        else if(p.mode==6u&&control.w==0.){
            status[2]++;
            if(!finite1(sum)||!finite1(maximum)){control.w=2.;status[1]|=1u;}
            else if(maximum<=p.tolerance)control.w=1.;
            else{control.z=sum/control.x;control.x=sum;}
        }
        if(p.mode==9u){
            if(generation[0]==0xffffffffu)status[1]|=4u;
            status[3]=floatBitsToUint(maximum);status[0]=(maximum<=p.tolerance&&status[1]==0u)?1u:0u;
            control.w=status[0]==1u?4.:2.;
        }
        return;
    }
    if(p.mode==7u){if(i<p.nodes&&control.w==0.)d[i]=r[i]+control.z*d[i];return;}
    if(p.mode==10u){
        if(status[0]==1u){if(i<p.nodes){solution[i]=x[i];solution_low[i]=x_low[i];}if(i<p.grains){solution_force[i]=candidate_force[i];solution_force_low[i]=candidate_force_low[i];}}
        return;
    }
    float sum=0.,maximum=0.;
    if(i<p.nodes){
        if(p.mode==1u){r[i]=applied[i].y+applied_low[i].y;d[i]=r[i];sum=r[i]*r[i];maximum=abs(r[i]);}
        if(p.mode==3u&&control.w==0.)sum=d[i]*(applied[i].x+applied_low[i].x);
        if(p.mode==3u&&control.w==1.){
            // Refresh from the original equation; keep x and restart only the
            // Krylov recurrence within the caller's existing slot budget.
            r[i]=true_residual(i);d[i]=r[i];sum=r[i]*r[i];maximum=abs(r[i]);
        }
        if(p.mode==5u&&control.w==0.){vec2 next=ds_add(vec2(x[i],x_low[i]),ds_mul(vec2(d[i],0),control.y));x[i]=next.x;x_low[i]=next.y;r[i]-=control.y*(applied[i].x+applied_low[i].x);sum=r[i]*r[i];maximum=abs(r[i]);}
        if(p.mode==8u)maximum=abs(true_residual(i));
        if(!finite1(sum)||!finite1(maximum)){atomicOr(status[1],1u);sum=0.;maximum=3.4e38;}
    }
    sums[lane]=sum;maxima[lane]=maximum;barrier();
    for(uint stride=32u;stride>0u;stride/=2u){if(lane<stride){sums[lane]+=sums[lane+stride];maxima[lane]=max(maxima[lane],maxima[lane+stride]);}barrier();}
    if(lane==0u)partial[gl_WorkGroupID.x]=vec2(sums[0],maxima[0]);
}
