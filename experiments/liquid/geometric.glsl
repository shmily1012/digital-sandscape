#[compute]
#version 450
layout(local_size_x=64) in;
struct Face { uint a; uint b; float velocity; uint axis; };
layout(set=0,binding=0,std430) readonly restrict buffer Source { float c[]; } src;
layout(set=0,binding=1,std430) writeonly restrict buffer Destination { float c[]; } dst;
layout(set=0,binding=2,std430) readonly restrict buffer Neighbors { ivec4 cell[]; } neighbors;
layout(set=0,binding=3,std430) readonly restrict buffer Adjacency { ivec4 face[]; } adjacency;
layout(set=0,binding=4,std430) readonly restrict buffer Faces { Face face[]; } geometry;
layout(set=0,binding=5,std430) restrict buffer Planes { vec4 plane[]; } planes;
layout(set=0,binding=6,std430) restrict buffer Fluxes { vec2 flux[]; } fluxes;
layout(set=0,binding=7,std430) restrict buffer Limits { vec4 cell[]; } limits;
layout(set=0,binding=8,std430) restrict buffer Corrections { float flux[]; } correction;
layout(set=0,binding=9,std430) restrict buffer Compensation { float error[]; } compensation;
layout(set=0,binding=10,std430) readonly restrict buffer Status { float dt_h; uint accepted; float divergence; float outgoing_rate; } status;
layout(push_constant,std430) uniform Parameters { uint cells; uint faces; float dt_h; uint phase; } p;

float area(vec2 normal,float offset,vec2 low,vec2 high) {
    vec2 vertices[4]=vec2[4](low,vec2(high.x,low.y),high,vec2(low.x,high.y));
    vec2 clipped[8]; int count=0;
    for(int i=0;i<4;++i) {
        vec2 a=vertices[i],b=vertices[(i+1)%4];
        float da=dot(normal,a)-offset,db=dot(normal,b)-offset;
        if(da>=0.0) clipped[count++]=a;
        if((da>=0.0)!=(db>=0.0)) clipped[count++]=mix(a,b,da/(da-db));
    }
    float sum=0.0;
    for(int i=0;i<count;++i) {
        vec2 a=clipped[i],b=clipped[(i+1)%count];
        sum+=a.x*b.y-a.y*b.x;
    }
    return abs(sum)*0.5;
}
void main() {
    uint i=gl_GlobalInvocationID.x;
    bool face_pass=p.phase==1u||p.phase==3u;
    if(i>=(face_pass ? p.faces : p.cells)) return;
    if(p.dt_h<0.0 && status.accepted!=1u) {
        if(p.phase==4u) dst.c[i]=src.c[i];
        return;
    }
    if(p.phase==0u) {
        float c=src.c[i];
        if(c<=0.0||c>=1.0) { planes.plane[i]=vec4(0); return; }
        ivec4 ids=neighbors.cell[i];
        vec4 values;
        for(int k=0;k<4;++k) values[k]=ids[k]>=0 ? src.c[ids[k]] : c;
        vec2 gradient=vec2(values.y-values.x,values.w-values.z);
        float magnitude=length(gradient);
        vec2 normal=magnitude>1e-14 ? gradient/magnitude : vec2(1,0);
        float low=min(0.0,normal.x)+min(0.0,normal.y);
        float high=max(0.0,normal.x)+max(0.0,normal.y);
        for(int step=0;step<26;++step) {
            float middle=(low+high)*0.5;
            if(area(normal,middle,vec2(0),vec2(1))>c) low=middle; else high=middle;
        }
        planes.plane[i]=vec4(normal,(low+high)*0.5,0);
    } else if(p.phase==1u) {
        Face f=geometry.face[i];
        uint donor=f.velocity>=0.0 ? f.a : f.b;
        float width=abs(f.velocity)*(p.dt_h<0.0 ? status.dt_h : p.dt_h);
        float direction=f.velocity>=0.0 ? 1.0 : -1.0;
        float c=src.c[donor];
        float low_flux=direction*width*c;
        vec2 low=vec2(0),high=vec2(1);
        if(direction>0.0) low[f.axis]=1.0-width; else high[f.axis]=width;
        vec4 plane=planes.plane[donor];
        float high_flux=c<=0.0 ? 0.0 : (c>=1.0 ? direction*width : direction*area(plane.xy,plane.z,low,high));
        if(width==0.0) high_flux=0.0;
        fluxes.flux[i]=vec2(low_flux,high_flux-low_flux);
    } else if(p.phase==2u) {
        float change_low=0.0,positive=0.0,negative=0.0;
        ivec4 ids=adjacency.face[i];
        for(int k=0;k<4;++k) if(ids[k]>=0) {
            Face f=geometry.face[ids[k]];
            vec2 flux=fluxes.flux[ids[k]];
            float sign=f.a==i ? -1.0 : 1.0;
            change_low+=sign*flux.x;
            float change=sign*flux.y;
            positive+=max(change,0.0); negative+=max(-change,0.0);
        }
        float provisional=src.c[i]+change_low;
        float rplus=positive>0.0 ? min(1.0,max(0.0,1.0-provisional)/positive) : 1.0;
        float rminus=negative>0.0 ? min(1.0,max(0.0,provisional)/negative) : 1.0;
        limits.cell[i]=vec4(provisional,rplus,rminus,0);
    } else if(p.phase==3u) {
        Face f=geometry.face[i];
        float a=fluxes.flux[i].y;
        float limiter=a>=0.0 ? min(limits.cell[f.a].z,limits.cell[f.b].y) : min(limits.cell[f.a].y,limits.cell[f.b].z);
        correction.flux[i]=a*limiter*(1.0-1e-6);
    } else {
        float change=0.0;
        ivec4 ids=adjacency.face[i];
        for(int k=0;k<4;++k) if(ids[k]>=0) {
            change+=(geometry.face[ids[k]].a==i ? -1.0 : 1.0)*(fluxes.flux[ids[k]].x+correction.flux[ids[k]]);
        }
        // Accumulate small volume changes without silently clipping inventory.
        precise float corrected=change-compensation.error[i];
        precise float value=src.c[i]+corrected;
        precise float difference=value-src.c[i];
        compensation.error[i]=difference-corrected;
        dst.c[i]=value;
    }
}
