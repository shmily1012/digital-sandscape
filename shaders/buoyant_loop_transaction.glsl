#[compute]
#version 450
// GPU transaction for one bounded mixed gas/grain loop.
// Exactly one invocation owns the proposal; concurrent proposals are unsupported.
// This is an effective overdamped model, not a resolved pressure/contact solve.
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Phase { float c[]; };
layout(set=0,binding=1,std430) buffer Material { uint m[]; };
layout(set=0,binding=2,std430) buffer Populations { float f[]; };
layout(set=0,binding=3,std430) buffer Residual { float residual[]; };
layout(set=0,binding=4,std430) buffer Moved { uint moved[]; };
layout(set=0,binding=5,std430) readonly buffer Candidate { uint indices[]; };
layout(set=0,binding=6,std430) buffer Result { float delta_work; uint accepted; uint reason; uint accepted_total; };
layout(push_constant,std430) uniform Params {
    uint side;float sigma;float width;float cosine;
    uint tick;uint seed;uint color;uint drag;
    float gx;float gy;float weight_scale;float mobility_scale;
} p;
const ivec2 D[4]=ivec2[4](ivec2(1,0),ivec2(0,1),ivec2(-1,0),ivec2(0,-1));
int adjacent(int i,ivec2 d){
    ivec2 v=ivec2(i%int(p.side),i/int(p.side))+d;
    if(any(lessThan(v,ivec2(0)))||any(greaterThanEqual(v,ivec2(p.side))))return -1;
    return v.y*int(p.side)+v.x;
}
float bond(int i,int j){
    if(m[i]!=0u&&m[j]!=0u)return 0.;
    precise float kappa=1.5*p.sigma*p.width;
    if(m[i]==0u&&m[j]==0u){precise float value=.5*kappa*(c[i]-c[j])*(c[i]-c[j]);return value;}
    int fluid=m[i]==0u?i:j,solid=m[i]==0u?j:i;
    precise float cf=c[fluid],preference=m[solid]>=2u?p.cosine:0.;
    precise float a=2.*preference/p.width;
    precise float cb=a==0.?cf:2.*cf/(1.+a+sqrt((1.+a)*(1.+a)-4.*a*cf));
    precise float value=kappa*(cb-cf)*(cb-cf)+p.sigma*preference*cb*cb*(3.-2.*cb);return value;
}

uint hash32(uint x){x^=x<<13;x^=x>>17;x^=x<<5;return x;}
float grain_weight(uint material){return material==2u?2.:(material==3u?1.7:1.4);}
int path_index(int i,int path[192],int count){for(int k=0;k<count;k++)if(path[k]==i)return k;return -1;}
float loop_work(int path[192],int count){
    precise float change=0.;
    for(int k=0;k<count;k++){
        int i=path[k],old_i=path[(k+count-1)%count];
        for(int q=0;q<4;q++){
            int j=adjacent(i,D[q]);if(j<0)continue;
            int slot=path_index(j,path,count);
            if(slot>=0&&j<i)continue;
            int old_j=slot<0?j:path[(slot+count-1)%count];
            change+=bond(old_i,old_j)-bond(i,j);
        }
        int next=path[(k+1)%count];
        ivec2 displacement=ivec2(next%int(p.side)-i%int(p.side),next/int(p.side)-i/int(p.side));
        float effective_mass=m[i]>=2u?grain_weight(m[i])*p.weight_scale:-c[i];
        change-=effective_mass*dot(vec2(p.gx,p.gy),vec2(displacement));
    }
    return change;
}
// One validated proposal per dispatch. Candidate selection and rates are external.
void main(){
    accepted=0u;reason=0u;delta_work=0.;
    int count=int(p.color);int path[192];bool sand=false,gas=false;
    if(count<4||count>192){reason=1u;return;}
    for(int k=0;k<count;k++){
        uint value=indices[k];if(value>=p.side*p.side){reason=2u;return;}
        path[k]=int(value);
        if(m[value]==1u||m[value]>4u){reason=2u;return;}
        if(m[value]>=2u){sand=true;if(moved[value]==p.tick){reason=16u;return;}}
        else if(c[value]>.05)gas=true;
        for(int j=0;j<k;j++)if(path[j]==path[k]){reason=4u;return;}
    }
    if(!sand||!gas){reason=4u;return;}
    for(int k=0;k<count;k++){
        int a=path[k],b=path[(k+1)%count];
        if(abs(a%int(p.side)-b%int(p.side))+abs(a/int(p.side)-b/int(p.side))!=1){reason=4u;return;}
    }
    float change=loop_work(path,count);delta_work=change;
    if(isnan(change)||isinf(change)){reason=32u;return;}
    if(change>=-1.e-8){reason=8u;return;}
    int last=path[count-1];uint carry_m=m[last],carry_stamp=moved[last];
    float carry_c=c[last],carry_r=residual[last],carry_f[9];
    for(int q=0;q<9;q++)carry_f[q]=f[9*last+q];
    for(int k=0;k<count;k++){
        int i=path[k];uint old_m=m[i],old_stamp=moved[i];float old_c=c[i],old_r=residual[i];
        m[i]=carry_m;c[i]=carry_c;residual[i]=carry_r;moved[i]=carry_m>=2u?p.tick:carry_stamp;
        carry_m=old_m;carry_c=old_c;carry_r=old_r;carry_stamp=old_stamp;
        for(int q=0;q<9;q++){float old=f[9*i+q];f[9*i+q]=carry_f[q];carry_f[q]=old;}
    }
    accepted=1u;accepted_total+=1u;
}
