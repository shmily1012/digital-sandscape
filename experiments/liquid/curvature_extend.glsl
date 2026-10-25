#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly restrict buffer Fraction { float c[]; } gas;
layout(set=0,binding=1,std430) readonly restrict buffer Height { vec2 value[]; } height;
layout(set=0,binding=2,std430) writeonly restrict buffer Extended { vec2 value[]; } result;
layout(push_constant,std430) uniform Params { uint side; uint pad0; uint pad1; uint pad2; } p;
void main() {
    uint i=gl_GlobalInvocationID.x;
    if(i>=p.side*p.side) return;
    result.value[i]=height.value[i];
    if(height.value[i].y>0.0 || gas.c[i]<=1e-10 || gas.c[i]>=1.0) return;
    ivec2 cell=ivec2(i%p.side,i/p.side);
    for(int radius=1;radius<=2;++radius) {
        float sum=0.0,low=1e30,high=-1e30;
        int count=0;
        for(int dy=-radius;dy<=radius;++dy) for(int dx=-radius;dx<=radius;++dx) {
            ivec2 q=cell+ivec2(dx,dy);
            if(max(abs(dx),abs(dy))!=radius || any(lessThan(q,ivec2(0))) || any(greaterThanEqual(q,ivec2(p.side)))) continue;
            vec2 donor=height.value[q.y*int(p.side)+q.x];
            if(donor.y>0.0) { sum+=donor.x;low=min(low,donor.x);high=max(high,donor.x);count++; }
        }
        if(count<2) continue;
        float mean=sum/float(count);
        if(high-low<=max(0.5,0.25*abs(mean))) result.value[i]=vec2(mean,1.0);
        return;
    }
}
