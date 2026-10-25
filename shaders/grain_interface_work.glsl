#[compute]
#version 450
// Read-only finite exchange work. This is not a movement acceptance rule.
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Phase { float c[]; };
layout(set=0,binding=1,std430) readonly buffer Material { uint m[]; };
layout(set=0,binding=2,std430) writeonly buffer Work { vec4 work[]; };
layout(set=0,binding=3,std430) writeonly buffer Valid { uint valid[]; };
layout(push_constant,std430) uniform Params { uint side;float sigma;float width;float cosine; } p;
const ivec2 D[4]=ivec2[4](ivec2(1,0),ivec2(0,1),ivec2(-1,0),ivec2(0,-1));
int adjacent(int i,ivec2 d){
    ivec2 v=ivec2(i%int(p.side),i/int(p.side))+d;
    if(any(lessThan(v,ivec2(0)))||any(greaterThanEqual(v,ivec2(p.side))))return -1;
    return v.y*int(p.side)+v.x;
}
float bond(int i,int j){
    if(m[i]!=0u&&m[j]!=0u)return 0.;
    float kappa=1.5*p.sigma*p.width;
    if(m[i]==0u&&m[j]==0u)return .5*kappa*(c[i]-c[j])*(c[i]-c[j]);
    int fluid=m[i]==0u?i:j,solid=m[i]==0u?j:i;
    float cf=c[fluid],preference=m[solid]>=2u?p.cosine:0.;
    float a=2.*preference/p.width;
    float cb=a==0.?cf:2.*cf/(1.+a+sqrt((1.+a)*(1.+a)-4.*a*cf));
    return kappa*(cb-cf)*(cb-cf)+p.sigma*preference*cb*cb*(3.-2.*cb);
}
int mapped(int i,int a,int b){return i==a?b:(i==b?a:i);}
float delta_bond(int i,int j,int a,int b){return bond(mapped(i,a,b),mapped(j,a,b))-bond(i,j);}
void main(){
    int a=int(gl_GlobalInvocationID.x);if(a>=int(p.side*p.side))return;
    vec4 result=vec4(0);uint mask=0u;
    if(m[a]>=2u)for(int direction=0;direction<4;direction++){
        int b=adjacent(a,D[direction]);if(b<0||m[b]!=0u)continue;
        float delta=0.;
        for(int q=0;q<4;q++){
            int j=adjacent(a,D[q]);if(j>=0)delta+=delta_bond(a,j,a,b);
            j=adjacent(b,D[q]);if(j>=0&&j!=a)delta+=delta_bond(b,j,a,b);
        }
        result[direction]=delta;mask|=1u<<direction;
    }
    work[a]=result;valid[a]=mask;
}
