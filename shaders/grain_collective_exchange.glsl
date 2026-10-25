#[compute]
#version 450
// Bounded collective move with an explicit adjacent-fluid return loop.
// Four lateral by twelve axial colors separate all read/write footprints.
// This is an effective overdamped model, not a resolved pressure/contact solve.
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,std430) buffer Phase { float c[]; };
layout(set=0,binding=1,std430) buffer Material { uint m[]; };
layout(set=0,binding=2,std430) buffer Populations { float f[]; };
layout(set=0,binding=3,std430) buffer Residual { float residual[]; };
layout(set=0,binding=4,std430) buffer Moved { uint moved[]; };
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
int path_index(int i,int path[18],int count){for(int k=0;k<count;k++)if(path[k]==i)return k;return -1;}
float loop_work(int path[18],int count){
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
void main(){
    if(p.gx==0.&&p.gy==0.)return;
    bool vertical=abs(p.gy)>=abs(p.gx);
    int lateral=4*int(gl_GlobalInvocationID.x)+int(p.color)%4;
    int axial=12*int(gl_GlobalInvocationID.y)+int(p.color)/4;
    ivec2 pos=vertical?ivec2(lateral,axial):ivec2(axial,lateral);
    if(any(greaterThanEqual(pos,ivec2(p.side))))return;
    int a=pos.y*int(p.side)+pos.x;
    if(m[a]<2u||moved[a]==p.tick)return;
    ivec2 down=vertical?ivec2(0,sign(p.gy)):ivec2(sign(p.gx),0);
    int target=adjacent(a,down);if(target<0||m[target]!=0u)return;
    int max_length=0;precise float prefix_resistance[9];prefix_resistance[0]=0.;
    for(int k=0;k<8;k++){
        int j=adjacent(a,-k*down);if(j<0||m[j]<2u||moved[j]==p.tick)break;
        precise float mobility=(m[j]==2u?24.:(m[j]==3u?18.:12.))*p.mobility_scale;
        prefix_resistance[k+1]=prefix_resistance[k]+grain_weight(m[j])*256./mobility;
        max_length++;
    }
    if(max_length<2)return;
    int count=0;int chosen[18];int best=0;float resistance=0.;
    uint rng=hash32(p.seed^(p.tick*747796405u)^(uint(a)*277803737u));
    for(int direction=0;direction<2;direction++){
        ivec2 side=ivec2(down.y,-down.x)*(direction==0?1:-1);
        int length=max_length;
        for(int k=0;k<=max_length;k++){
            int j=adjacent(a,(1-k)*down+side);
            if(j<0||m[j]!=0u){length=k-1;break;}
        }
        if(length<2)continue;
        // An obstructed upper return route does not pin a legal lower subchain.
        int candidate_count=2*length+2;int path[18];
        for(int k=0;k<length;k++)path[k]=adjacent(a,(k-length+1)*down);
        path[length]=target;
        for(int k=0;k<=length;k++)path[length+1+k]=adjacent(a,(1-k)*down+side);
        int score=int(clamp(round(-loop_work(path,candidate_count)*1.e9),0.,1.e7));
        if(score<=0)continue;
        rng=hash32(rng+0x9e3779b9u);
        if(score>best||(score==best&&(rng&1u)==0u)){
            best=score;count=candidate_count;
            resistance=prefix_resistance[length]+float(length+2)*8.;
            for(int k=0;k<count;k++)chosen[k]=path[k];
        }
    }
    if(best==0)return;
    rng=hash32(rng+0x9e3779b9u);
    float rate=clamp(float(best)*1.e-9/(.00002*resistance*float(max(p.drag,1u))),0.,.25);
    if((rng&65535u)>=uint(round(rate*65536.)))return;
    int last=chosen[count-1];uint carry_m=m[last],carry_stamp=moved[last];
    float carry_c=c[last],carry_r=residual[last],carry_f[9];
    for(int q=0;q<9;q++)carry_f[q]=f[9*last+q];
    for(int k=0;k<count;k++){
        int i=chosen[k];uint old_m=m[i],old_stamp=moved[i];float old_c=c[i],old_r=residual[i];
        m[i]=carry_m;c[i]=carry_c;residual[i]=carry_r;moved[i]=carry_m>=2u?p.tick:carry_stamp;
        carry_m=old_m;carry_c=old_c;carry_r=old_r;carry_stamp=old_stamp;
        for(int q=0;q<9;q++){float old=f[9*i+q];f[9*i+q]=carry_f[q];carry_f[q]=old;}
    }
}
