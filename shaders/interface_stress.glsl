#[compute]
#version 450
// Finite-volume capillary stress. Each invocation owns one force entry.
// Cubic surface energy on grains; fixed container walls remain neutral.
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Phase { float c[]; };
layout(set=0,binding=1,std430) readonly buffer Materials { uint m[]; };
layout(set=0,binding=2,std430) writeonly buffer Forces { vec2 force[]; };
layout(push_constant,std430) uniform Params { uint side;float sigma;float width;float wetting_cosine; } p;
const ivec2 D[4]=ivec2[4](ivec2(1,0),ivec2(0,1),ivec2(-1,0),ivec2(0,-1));
int adjacent(int i,ivec2 d){
    ivec2 xy=ivec2(i%int(p.side),i/int(p.side))+d;
    if(any(lessThan(xy,ivec2(0)))||any(greaterThanEqual(xy,ivec2(p.side))))return -1;
    return xy.y*int(p.side)+xy.x;
}
float boundary_phase(float cf,uint solid){
    float a=solid>=2u?2.*p.wetting_cosine/p.width:0.;
    return a==0.?cf:2.*cf/(1.+a+sqrt((1.+a)*(1.+a)-4.*a*cf));
}
float sample_c(int i,ivec2 d){
    int j=adjacent(i,d);if(j<0)return c[i];
    return m[j]!=0u?2.*boundary_phase(c[i],m[j])-c[i]:c[j];
}
vec2 gradient(int i){return .5*vec2(sample_c(i,D[0])-sample_c(i,D[2]),sample_c(i,D[1])-sample_c(i,D[3]));}
mat2 stress(float phase,vec2 g){
    float kappa=1.5*p.sigma*p.width;
    float bulk=12.*p.sigma/p.width*phase*phase*(1.-phase)*(1.-phase);
    return mat2(bulk+.5*kappa*dot(g,g))-kappa*outerProduct(g,g);
}
void main(){
    int i=int(gl_GlobalInvocationID.x);if(i>=int(p.side*p.side))return;
    vec2 result=vec2(0);
    for(int q=0;q<4;q++){
        int j=adjacent(i,D[q]);if(j<0||(m[i]!=0u&&m[j]!=0u))continue;
        mat2 face;
        if(m[i]==0u&&m[j]==0u)face=.5*(stress(c[i],gradient(i))+stress(c[j],gradient(j)));
        else{
            int fluid=m[i]==0u?i:j;int solid=m[i]==0u?j:i;
            vec2 normal=m[i]==0u?vec2(D[q]):-vec2(D[q]);
            float cb=boundary_phase(c[fluid],m[solid]);
            vec2 g=gradient(fluid);g-=normal*dot(g,normal);
            g+=normal*(2.*(cb-c[fluid]));
            face=stress(cb,g);
        }
        result+=face*vec2(D[q]);
    }
    force[i]=result;
}
