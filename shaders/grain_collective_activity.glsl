#[compute]
#version 450
// Conservative global activity gate. A nonzero result keeps every color;
// skipping individual colors would miss newly exposed chains after a move.
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Materials { uint m[]; };
layout(set=0,binding=1,std430) readonly buffer Moved { uint moved[]; };
layout(set=0,binding=2,std430) buffer Dispatch { uint args[]; };
layout(push_constant,std430) uniform Params { uint side;uint tick;uint mode;uint pad;float gx;float gy;uint pad1;uint pad2; } p;
int adjacent(int i,ivec2 d){
    ivec2 v=ivec2(i%int(p.side),i/int(p.side))+d;
    if(any(lessThan(v,ivec2(0)))||any(greaterThanEqual(v,ivec2(p.side))))return -1;
    return v.y*int(p.side)+v.x;
}
void main(){
    uint id=gl_GlobalInvocationID.x;
    if(p.mode==0u){if(id==0u)for(int k=0;k<4;k++)args[k]=0u;return;}
    if(id>=p.side*p.side||(p.gx==0.&&p.gy==0.))return;
    int a=int(id);if(m[a]<2u||moved[a]==p.tick)return;
    ivec2 down=abs(p.gy)>=abs(p.gx)?ivec2(0,sign(p.gy)):ivec2(sign(p.gx),0);
    int target=adjacent(a,down);if(target<0||m[target]!=0u)return;
    int length=0;
    for(int k=0;k<8;k++){
        int j=adjacent(a,-k*down);if(j<0||m[j]<2u)break;
        if(moved[j]==p.tick)break;
        length++;
    }
    if(length<2)return;
    bool eligible=false;
    for(int direction=0;direction<2;direction++){
        ivec2 side=ivec2(down.y,-down.x)*(direction==0?1:-1);
        bool valid=true;
        // A two-grain lower loop suffices; longer routes may be obstructed.
        for(int k=0;k<=2;k++){
            int j=adjacent(a,(1-k)*down+side);
            if(j<0||m[j]!=0u){valid=false;break;}
        }
        eligible=eligible||valid;
    }
    if(!eligible)return;
    atomicMax(args[0],(p.side+31u)/32u);
    atomicMax(args[1],(p.side+95u)/96u);
    atomicMax(args[2],1u);
    atomicAdd(args[3],1u);
}
