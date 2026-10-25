#[compute]
#version 450
// Secant adjoint of the same finite-step box flux used for local drainage.
// Candidate reaction only; never add it on top of the legacy LBM pressure.
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Materials { uint m[]; };
layout(set=0,binding=1,std430) readonly buffer Offset { vec2 offset[]; };
layout(set=0,binding=2,std430) readonly buffer Velocity { vec2 velocity[]; };
layout(set=0,binding=3,std430) readonly buffer Pressure { vec4 state[]; };
layout(set=0,binding=4,std430) readonly buffer Status { uint status[]; };
layout(set=0,binding=5,std430) writeonly buffer Reaction { vec2 reaction[]; };
layout(push_constant,std430) uniform Params { uint side;float dt;uint pad0;uint pad1; } p;
float overlap(float center){return max(0.,1.-abs(center));}
float left_area(float center){return clamp(1.-center,0.,1.);}
float stationary_cut(float center){return center>0.&&center<1.?1.:(center==0.||center==1.?.5:0.);}
void main(){
    uint i=gl_GlobalInvocationID.x;if(i>=p.side*p.side)return;
    reaction[i]=vec2(0);if(m[i]<2u||status[1]!=1u)return;
    ivec2 owner=ivec2(i%p.side,i/p.side);vec2 v=velocity[i],d=v*p.dt,result=vec2(0);
    for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){
        ivec2 cell=owner+ivec2(x,y);
        if(any(lessThan(cell,ivec2(0)))||any(greaterThanEqual(cell,ivec2(p.side))))continue;
        uint j=uint(cell.y)*p.side+uint(cell.x);
        vec2 a=offset[i]-vec2(x,y),b=a+d;
        vec2 mean_overlap=.5*vec2(overlap(a.x)+overlap(b.x),overlap(a.y)+overlap(b.y));
        for(int axis=0;axis<2;axis++){
            if(cell[axis]+1>=int(p.side))continue;
            uint k=j+(axis==0?1u:p.side);
            float coefficient=d[axis]!=0.?(left_area(a[axis])-left_area(b[axis]))/d[axis]:stationary_cut(a[axis]);
            coefficient*=mean_overlap[1-axis];
            result[axis]+=(state[j].x-state[k].x)*coefficient;
        }
    }
    reaction[i]=result;
}
