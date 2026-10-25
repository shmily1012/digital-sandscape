#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly restrict buffer Positions { float value[]; } positions;
layout(set=0,binding=1,std430) writeonly restrict buffer Responses { vec4 k[]; } response;
layout(set=0,binding=2,std430) writeonly restrict buffer Validity { uint ok[]; } validity;
layout(set=0,binding=3,std430) readonly restrict buffer Kernel { float value[]; } kernel;
layout(push_constant,std430) uniform Params { uint side; uint grains; uint stride; uint pad1; } p;
void main() {
    uint id=gl_GlobalInvocationID.x;
    if(id>=p.grains) return;
    uint stride=p.stride==0u ? 2u : p.stride;
    vec2 position=vec2(positions.value[id*stride],positions.value[id*stride+1u]);
    validity.ok[id]=0u;
    response.k[id]=vec4(uintBitsToFloat(0x7fc00000u));
    if(any(isnan(position))||any(isinf(position))||length(position-0.5)+4.0/float(p.side)>=0.46) return;
    vec2 center[32];ivec2 cell[32];float weight[32];int axis[32];
    int count=0;vec2 norm=vec2(0);
    ivec2 origin=ivec2(floor(position*float(p.side)));
    for(int a=0;a<2;++a) for(int dy=-3;dy<=2;++dy) for(int dx=-3;dx<=2;++dx) {
        ivec2 q=origin+ivec2(dx,dy);
        vec2 c=(vec2(q)+(a==0 ? vec2(1,.5) : vec2(.5,1)))/float(p.side);
        vec2 w=max(vec2(0),1.0-abs(c-position)*float(p.side)*0.5);
        float v=w.x*w.y;
        if(v<=0.0) continue;
        if(count>=32) return;
        center[count]=c-0.5;cell[count]=q;weight[count]=v;axis[count]=a;
        norm+=(a==0 ? vec2(v,0) : vec2(0,v));
        count++;
    }
    vec4 result=vec4(0);
    for(int i=0;i<count;++i) for(int j=0;j<count;++j) {
        int a=axis[i],b=axis[j];
        ivec2 delta=cell[i]-cell[j];
        if(any(greaterThan(abs(delta),ivec2(4)))) return;
        float local=kernel.value[(2*a+b)*81+(delta.y+4)*9+delta.x+4]*float(p.side*p.side);
        vec2 z=center[i],w=center[j];
        vec2 product=vec2(dot(z,w),z.y*w.x-z.x*w.y);
        vec2 t=vec2(1,0)-product/(0.46*0.46);
        float d=dot(t,t);
        vec2 harmonic=vec2(t.x*t.x-t.y*t.y,-2.0*t.x*t.y)/(d*d*6.283185307179586*0.46*0.46);
        float boundary=a==b ? harmonic.x : (a==0 ? harmonic.y : -harmonic.y);
        float scale=weight[i]*weight[j]/((a==0 ? norm.x : norm.y)*(b==0 ? norm.x : norm.y));
        float v=scale*(local-boundary);
        if(a==0 && b==0) result.x+=v;
        else if(a==0) result.y+=v;
        else if(b==0) result.z+=v;
        else result.w+=v;
    }
    if(p.stride==8u) {
        float drag=positions.value[id*8u+3u];
        float a=1.0/drag-result.x,d=1.0/drag-result.w,b=-(result.y+result.z)*0.5;
        float margin=(a+d)*0.5-length(vec2((a-d)*0.5,b));
        if(isnan(margin)||isinf(margin)||drag<=0.0||margin<=1e-8) return;
    }
    response.k[id]=result;
    validity.ok[id]=1u;
}
