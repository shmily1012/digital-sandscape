#[compute]
#version 450
// Exact endpoint areas and swept volume of the existing unit-box particles.
// This pass does not move phase/population packets or approve a fluid update.
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Materials { uint m[]; };
layout(set=0,binding=1,std430) readonly buffer Offset { vec2 offset[]; };
layout(set=0,binding=2,std430) readonly buffer Velocity { vec2 velocity[]; };
layout(set=0,binding=3,std430) writeonly buffer Geometry { vec4 geometry[]; };
layout(set=0,binding=4,std430) buffer Status { uint status[]; };
layout(set=0,binding=5,std430) writeonly buffer Aperture { vec2 aperture[]; };
layout(push_constant,std430) uniform Params { uint side;float dt;uint pad0;uint pad1; } p;
float overlap(float center){return max(0.,1.-abs(center));}
float left_area(float center){return clamp(1.-center,0.,1.);}
float open_face(ivec2 cell,int axis,float time){
    vec2 intervals[9];int count=0;
    for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){
        ivec2 owner=cell+ivec2(x,y);
        if(any(lessThan(owner,ivec2(0)))||any(greaterThanEqual(owner,ivec2(p.side))))continue;
        uint j=uint(owner.y)*p.side+uint(owner.x);if(m[j]==0u)continue;
        vec2 center=vec2(x,y)+(m[j]>=2u?offset[j]+time*velocity[j]:vec2(0));
        if(abs(center[axis]-.5)>.5)continue;
        float low=max(-.5,center[1-axis]-.5),high=min(.5,center[1-axis]+.5);
        if(high>low){intervals[count]=vec2(low,high);count++;}
    }
    // Union is required: two touching boxes may cover the same boundary face.
    for(int a=1;a<count;a++){
        vec2 item=intervals[a];int b=a-1;
        while(b>=0&&intervals[b].x>item.x){intervals[b+1]=intervals[b];b--;}
        intervals[b+1]=item;
    }
    float covered=0.,end=-.5;
    for(int a=0;a<count;a++){covered+=max(0.,intervals[a].y-max(end,intervals[a].x));end=max(end,intervals[a].y);}
    return max(0.,1.-covered);
}
void main(){
    uint i=gl_GlobalInvocationID.x;if(i>=p.side*p.side)return;
    ivec2 cell=ivec2(i%p.side,i/p.side);
    float old_solid=0.,new_solid=0.;vec2 swept=vec2(0);
    for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){
        ivec2 owner=cell+ivec2(x,y);
        if(any(lessThan(owner,ivec2(0)))||any(greaterThanEqual(owner,ivec2(p.side))))continue;
        uint j=uint(owner.y)*p.side+uint(owner.x);if(m[j]==0u)continue;
        vec2 a=vec2(x,y)+(m[j]>=2u?offset[j]:vec2(0));
        vec2 d=m[j]>=2u?velocity[j]*p.dt:vec2(0);vec2 b=a+d;
        if(any(isnan(a))||any(isinf(a))||any(isnan(d))||any(isinf(d))||any(greaterThan(abs(d),vec2(.25))))atomicOr(status[1],1u);
        vec2 oa=vec2(overlap(a.x),overlap(a.y));
        vec2 ob=vec2(overlap(b.x),overlap(b.y));
        old_solid+=oa.x*oa.y;new_solid+=ob.x*ob.y;
        // Average x-then-y and y-then-x swept paths. Each face is owned once.
        swept.x+=(left_area(a.x)-left_area(b.x))*.5*(oa.y+ob.y)/p.dt;
        swept.y+=(left_area(a.y)-left_area(b.y))*.5*(oa.x+ob.x)/p.dt;
    }
    if(old_solid>1.000005||new_solid>1.000005)atomicOr(status[1],1u);
    // Keep the unrounded area ledger; do not hide overlaps by clipping.
    geometry[i]=vec4(1.-old_solid,1.-new_solid,swept);
    aperture[i]=.5*vec2(open_face(cell,0,0.)+open_face(cell,0,p.dt),open_face(cell,1,0.)+open_face(cell,1,p.dt));
}
