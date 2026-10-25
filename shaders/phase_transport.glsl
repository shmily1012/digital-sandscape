#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Input { float c[]; };
layout(set=0,binding=1,std430) writeonly buffer Output { float next_c[]; };
layout(set=0,binding=2,std430) buffer Flux { vec2 flux[]; };
layout(set=0,binding=3,std430) buffer Capacity { vec2 capacity[]; };
layout(set=0,binding=4,std430) readonly buffer Walls { uint wall[]; };
layout(set=0,binding=5,std430) readonly buffer Velocity { vec2 velocity[]; };
layout(push_constant,std430) uniform Params {
    uint side; uint mode; float dt; float mobility;
    float width; float vx; float vy; float wetting_cosine;
} p;
int neighbor(int i, ivec2 d) {
    ivec2 q=ivec2(i%int(p.side),i/int(p.side))+d;
    if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,ivec2(p.side))))return i;
    int j=q.y*int(p.side)+q.x;
    return wall[j]!=0u?i:j;
}
float sample_c(int i,ivec2 d){
    ivec2 xy=ivec2(i%int(p.side),i/int(p.side))+d;
    if(any(lessThan(xy,ivec2(0)))||any(greaterThanEqual(xy,ivec2(p.side))))return c[i];
    int j=xy.y*int(p.side)+xy.x;
    if(wall[j]==0u)return c[j];
    float a=wall[j]>=2u?2.*p.wetting_cosine/p.width:0.;
    float cb=a==0.?c[i]:2.*c[i]/(1.+a+sqrt((1.+a)*(1.+a)-4.*a*c[i]));
    return 2.*cb-c[i];
}
vec2 gradient(int i) {
    return .5*vec2(sample_c(i,ivec2(1,0))-sample_c(i,ivec2(-1,0)),
                   sample_c(i,ivec2(0,1))-sample_c(i,ivec2(0,-1)));
}
float face(int i,int axis) {
    int j=neighbor(i,axis==0?ivec2(1,0):ivec2(0,1));
    if(j==i)return 0.;
    float speed=.5*(velocity[i][axis]+velocity[j][axis]);
    float mean_c=.5*(c[i]+c[j]);
    vec2 g=.5*(gradient(i)+gradient(j));
    float norm=g[axis]/sqrt(dot(g,g)+pow(0.08/p.width,2.));
    float sharp=4.*mean_c*(1.-mean_c)/p.width*norm;
    return p.dt*(speed*(speed>=0.?c[i]:c[j])-p.mobility*(c[j]-c[i]-sharp));
}
float limited(int i,int j,float f) {
    return f*(f>=0.?min(capacity[i].x,capacity[j].y):min(capacity[j].x,capacity[i].y));
}
void main() {
    int i=int(gl_GlobalInvocationID.x);
    if(i>=int(p.side*p.side))return;
    if(p.mode==0u){flux[i]=wall[i]!=0u?vec2(0):vec2(face(i,0),face(i,1));return;}
    if(p.mode==1u){
        float outgoing=0.,incoming=0.;
        for(int axis=0;axis<2;axis++){
            float f=flux[i][axis];outgoing+=max(f,0.);incoming+=max(-f,0.);
            int j=neighbor(i,axis==0?ivec2(-1,0):ivec2(0,-1));
            f=j==i?0.:flux[j][axis];incoming+=max(f,0.);outgoing+=max(-f,0.);
        }
        capacity[i]=vec2(outgoing>0.?min(1.,c[i]/outgoing):1.,incoming>0.?min(1.,(1.-c[i])/incoming):1.);
        return;
    }
    float value=c[i];
    if(wall[i]==0u)for(int axis=0;axis<2;axis++){
        ivec2 d=axis==0?ivec2(1,0):ivec2(0,1);
        int j=neighbor(i,d);if(j!=i)value-=limited(i,j,flux[i][axis]);
        j=neighbor(i,-d);if(j!=i)value+=limited(j,i,flux[j][axis]);
    }
    next_c[i]=value;
}
