#[compute]
#version 450
// Experimental overdamped exchange model, not a resolved momentum integrator.
// Sources are four cells apart. Radius-two reads cannot overlap another
// invocation's radius-one writes. Sixteen color dispatches require barriers.
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
int mapped(int i,int a,int b){return i==a?b:(i==b?a:i);}
float delta_bond(int i,int j,int a,int b){return bond(mapped(i,a,b),mapped(j,a,b))-bond(i,j);}

uint hash32(uint x){x^=x<<13;x^=x>>17;x^=x<<5;return x;}
const ivec2 H[8]=ivec2[8](ivec2(1,0),ivec2(0,1),ivec2(-1,0),ivec2(0,-1),ivec2(1,1),ivec2(-1,1),ivec2(-1,-1),ivec2(1,-1));
void main(){
    ivec2 pos=4*ivec2(gl_GlobalInvocationID.xy)+ivec2(int(p.color)%4,int(p.color)/4);
    if(any(greaterThanEqual(pos,ivec2(p.side))))return;
    int a=pos.y*int(p.side)+pos.x;
    if(m[a]<2u||moved[a]==p.tick)return;
    // Every legal hop needs a cardinal fluid neighbor: diagonal hops below
    // also require an open side. Re-evaluate each color, never cache a frozen
    // bed mask, because an earlier dispatch may have exposed this grain.
    bool exposed=false;
    for(int q=0;q<4;q++){
        int j=adjacent(a,D[q]);
        if(j>=0&&m[j]==0u&&c[j]<=.05){exposed=true;break;}
    }
    if(!exposed)return;
    float reference_weight=m[a]==2u?2.:(m[a]==3u?1.7:1.4);
    precise float weight=reference_weight*p.weight_scale;
    ivec2 down=abs(p.gx)>abs(p.gy)?ivec2(sign(p.gx),0):ivec2(0,sign(p.gy));
    int below=adjacent(a,down);
    bool supported=below<0||(below!=a&&(m[below]!=0u||c[below]>.05));
    uint rng=hash32(p.seed^(p.tick*747796405u)^(uint(a)*277803737u));
    int chosen=-1,best=0,ties=0;
    for(int h=0;h<8;h++){
        ivec2 d=H[h];int b=adjacent(a,d);
        if(b<0||m[b]!=0u||c[b]>.05)continue;
        bool diagonal=d.x!=0&&d.y!=0;
        if(diagonal){
            int x=adjacent(a,ivec2(d.x,0)),y=adjacent(a,ivec2(0,d.y));
            if(!supported||((x<0||m[x]!=0u)&&(y<0||m[y]!=0u)))continue;
        }
        precise float change=0.;
        for(int q=0;q<4;q++){
            int j=adjacent(a,D[q]);if(j>=0)change+=delta_bond(a,j,a,b);
            j=adjacent(b,D[q]);if(j>=0&&j!=a)change+=delta_bond(b,j,a,b);
        }
        // The displaced gas packet has negative effective buoyant mass.
        change-=(weight+c[b])*dot(vec2(p.gx,p.gy),vec2(d));
        int score=int(clamp(round(-change*1.e9/float(diagonal?2:1)),0.,1.e7));
        if(score<=0)continue;
        rng=hash32(rng+0x9e3779b9u);
        if(score>best){best=score;chosen=b;ties=1;}
        else if(score==best){ties++;if(rng%uint(ties)==0u)chosen=b;}
    }
    if(chosen<0)return;
    rng=hash32(rng+0x9e3779b9u);
    precise float mobility=(m[a]==2u?24.:(m[a]==3u?18.:12.))*p.mobility_scale;
    uint threshold=uint(round(mobility*clamp(float(best)/(reference_weight*20000.),0.,4.)*256./float(max(p.drag,1u))));
    if((rng&65535u)>=threshold)return;
    int b=chosen;uint material=m[a];m[a]=0u;m[b]=material;
    float gas=c[a];c[a]=c[b];c[b]=gas;
    float carry=residual[a];residual[a]=residual[b];residual[b]=carry;
    for(int q=0;q<9;q++){float value=f[9*a+q];f[9*a+q]=f[9*b+q];f[9*b+q]=value;}
    moved[a]=moved[b];moved[b]=p.tick;
}
