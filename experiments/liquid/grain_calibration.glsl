#[compute]
#version 450
layout(local_size_x=64) in;
struct Grain { vec4 geom; vec4 props; };
struct Face { uint a; uint b; float mobility; float source; };
struct Equation { vec4 weights; vec4 source; };
layout(set=0,binding=0,std430) readonly restrict buffer Grains { Grain g[]; } grains;
layout(set=0,binding=1,std430) readonly restrict buffer Norm { vec2 w[]; } norm;
layout(set=0,binding=2,std430) restrict buffer Faces { Face f[]; } faces;
layout(set=0,binding=3,std430) restrict buffer Equations { Equation cell[]; } equations;
layout(set=0,binding=4,std430) readonly restrict buffer Pressure { float p[]; } pressure;
layout(set=0,binding=5,std430) readonly restrict buffer Control { uint word[]; } control;
layout(set=0,binding=6,std430) restrict buffer Self { vec4 k[]; } self_response;
layout(set=0,binding=7,std430) restrict buffer Matrix { float k[]; } response;
layout(set=0,binding=8,std430) restrict buffer Certificate { uint valid; } certificate;
layout(set=0,binding=9,std430) readonly restrict buffer Adjacency { ivec4 ids[]; } adjacency;
layout(push_constant,std430) uniform Params { uint grains; uint faces; uint side; uint phase; uint unit; uint pad0; uint pad1; uint pad2; } p;
uint axis_of(Face f) { return f.b-f.a==1u ? 0u : 1u; }
float component(vec2 v,uint axis) { return axis==0u ? v.x : v.y; }
float weight(Face f,vec2 position) {
    vec2 a=vec2(f.a%p.side,f.a/p.side),b=vec2(f.b%p.side,f.b/p.side);
    vec2 center=((a+b)*0.5+0.5)/float(p.side);
    vec2 w=max(vec2(0),1.0-abs(center-position)*float(p.side)*0.5);
    return w.x*w.y;
}
void invalidate() {
    certificate.valid=0u;
    for(uint j=0u;j<p.grains;++j) self_response.k[j]=vec4(uintBitsToFloat(0x7fc00000u));
}
void main() {
    uint i=gl_GlobalInvocationID.x;
    if(p.phase==0u) {
        if(i>=p.faces) return;
        Face f=faces.f[i];uint axis=axis_of(f),grain=p.unit/2u;
        faces.f[i].source=axis==p.unit%2u ? 0.001*f.mobility*weight(f,grains.g[grain].geom.xy)/component(norm.w[grain],axis)*float(p.side*p.side) : 0.0;
    } else if(p.phase==1u) {
        if(i>=p.side*p.side) return;
        float d=0.0;
        for(int k=0;k<4;++k) {
            int id=adjacency.ids[i][k];
            if(id>=0) { Face f=faces.f[id];d+=(f.a==i ? 1.0 : -1.0)*f.source*float(p.side); }
        }
        equations.cell[i].source.x=-d;
    } else if(p.phase==2u) {
        if(i>=p.grains) return;
        vec2 u=vec2(0.0);
        for(uint id=0u;id<p.faces;++id) {
            Face f=faces.f[id];uint axis=axis_of(f);
            float velocity=f.source-f.mobility*(pressure.p[f.b]-pressure.p[f.a])*float(p.side);
            u+=(axis==0u ? vec2(1,0) : vec2(0,1))*weight(f,grains.g[i].geom.xy)/component(norm.w[i],axis)*velocity*1000.0;
        }
        if(control.word[1]!=1u || control.word[3]!=0u) u=vec2(uintBitsToFloat(0x7fc00000u));
        response.k[(2u*i)*(2u*p.grains)+p.unit]=u.x;
        response.k[(2u*i+1u)*(2u*p.grains)+p.unit]=u.y;
        if(i==p.unit/2u) {
            if(p.unit%2u==0u) { self_response.k[i].x=u.x;self_response.k[i].z=u.y; }
            else { self_response.k[i].y=u.x;self_response.k[i].w=u.y; }
        }
    } else if(p.phase==3u) {
        if(i!=0u) return;
        if(p.grains>8u) { invalidate();return; }
        uint n=2u*p.grains;
        float lower[256];
        for(uint k=0u;k<256u;++k) lower[k]=0.0;
        for(uint row=0u;row<n;++row) for(uint col=0u;col<=row;++col) {
            float a=response.k[row*n+col],b=response.k[col*n+row];
            if(isnan(a)||isnan(b)||isinf(a)||isinf(b)||abs(a-b)>0.001) { invalidate();return; }
            float v=row/2u==col/2u ? (row==col ? 1.0/grains.g[row/2u].geom.w : 0.0) : 0.5*(a+b);
            for(uint k=0u;k<col;++k) v-=lower[row*n+k]*lower[col*n+k];
            if(row==col) {
                if(v<=1e-6) { invalidate();return; }
                lower[row*n+col]=sqrt(v);
            } else lower[row*n+col]=v/lower[col*n+col];
        }
        certificate.valid=1u;
    } else if(p.phase==4u) {
        // Publish a symmetric self-corrected mobility only after certification.
        // One writer owns both triangles, avoiding in-place read/write races.
        if(i!=0u)return;
        uint n=2u*p.grains;
        for(uint row=0u;row<n;++row)for(uint col=0u;col<=row;++col) {
            float value=uintBitsToFloat(0x7fc00000u);
            if(certificate.valid==1u) {
                value=row/2u==col/2u ? (row==col ? 1.0/grains.g[row/2u].geom.w : 0.0) : 0.5*(response.k[row*n+col]+response.k[col*n+row]);
            }
            response.k[row*n+col]=value;response.k[col*n+row]=value;
        }

    }
}
