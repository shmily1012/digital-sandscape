#[compute]
#version 450
#ifndef SVD_SIZE
#define SVD_SIZE 32
#endif
#define LANES (SVD_SIZE / 2)
// Bounded one-sided Jacobi SVD, at most 32 columns. No normal equations.
layout(local_size_x=LANES) in;
layout(set=0,binding=0,std430) readonly buffer Matrix { float a[]; } matrix;
layout(set=0,binding=1,std430) readonly buffer RHS { float b[]; } rhs;
layout(set=0,binding=2,std430) writeonly buffer Solution { float x[]; } solution;
layout(set=0,binding=3,std430) writeonly buffer Meta { uvec4 state; } meta;
layout(set=0,binding=4,std430) writeonly buffer NullVector { float x[]; } null_vector;
layout(set=0,binding=5,std430) readonly buffer AssemblyControl {uvec4 state;} assembly_control;
layout(push_constant,std430) uniform Params { uint size; uint sweeps; float rcond; uint pad; } p;
shared float b[SVD_SIZE*SVD_SIZE];
shared float v[SVD_SIZE*SVD_SIZE];
shared float norm2[SVD_SIZE];
shared float coefficient[SVD_SIZE];
shared float cutoff;
shared uint least;
uint player(uint slot,uint round) {return slot==0u ? 0u : 1u+(slot-1u+uint(SVD_SIZE-1)-round)%uint(SVD_SIZE-1);}
void main() {
    uint lane=gl_LocalInvocationID.x;
    if(p.pad==1u && assembly_control.state.x!=1u) {
        for(uint r=lane;r<p.size && r<uint(SVD_SIZE);r+=uint(LANES)){solution.x[r]=0.0;null_vector.x[r]=0.0;}
        if(lane==0u)meta.state=uvec4(0,0,0,1);
        return;
    }
    if(p.size==0u||p.size>uint(SVD_SIZE)||p.sweeps==0u||p.sweeps>32u) return;
    for(uint c=lane;c<p.size;c+=uint(LANES)) for(uint r=0u;r<p.size;++r) {
        b[c*uint(SVD_SIZE)+r]=matrix.a[r*p.size+c];v[c*uint(SVD_SIZE)+r]=r==c ? 1.0 : 0.0;
    }
    barrier();
    for(uint sweep=0u;sweep<p.sweeps;++sweep) {
        for(uint round=0u;round<uint(SVD_SIZE-1);++round) {
            uint first=player(lane,round),second=player(uint(SVD_SIZE-1)-lane,round);
            if(first<p.size&&second<p.size) {
                float a=0.0,d=0.0,c=0.0;
                for(uint r=0u;r<p.size;++r) {float x=b[first*uint(SVD_SIZE)+r],y=b[second*uint(SVD_SIZE)+r];a+=x*x;d+=y*y;c+=x*y;}
                if(abs(c)>1e-7*sqrt(a*d) && a>0.0 && d>0.0) {
                    float tau=(d-a)/(2.0*c);
                    float t=(tau>=0.0 ? 1.0 : -1.0)/(abs(tau)+sqrt(1.0+tau*tau));
                    float cosine=inversesqrt(1.0+t*t),sine=t*cosine;
                    for(uint r=0u;r<p.size;++r) {
                        float x=b[first*uint(SVD_SIZE)+r],y=b[second*uint(SVD_SIZE)+r];
                        b[first*uint(SVD_SIZE)+r]=cosine*x-sine*y;b[second*uint(SVD_SIZE)+r]=sine*x+cosine*y;
                        x=v[first*uint(SVD_SIZE)+r];y=v[second*uint(SVD_SIZE)+r];
                        v[first*uint(SVD_SIZE)+r]=cosine*x-sine*y;v[second*uint(SVD_SIZE)+r]=sine*x+cosine*y;
                    }
                }
            }
            barrier();
        }
    }
    for(uint c=lane;c<p.size;c+=uint(LANES)) {norm2[c]=0.0;for(uint r=0u;r<p.size;++r) norm2[c]+=b[c*uint(SVD_SIZE)+r]*b[c*uint(SVD_SIZE)+r];}
    barrier();
    if(lane==0u) {
        float largest=0.0;least=0u;
        for(uint c=0u;c<p.size;++c) {largest=max(largest,norm2[c]);if(norm2[c]<norm2[least]) least=c;}
        cutoff=largest*p.rcond*p.rcond;
        uint rank=0u;for(uint c=0u;c<p.size;++c) if(norm2[c]>cutoff) rank++;
        meta.state=uvec4(rank,p.sweeps,0,0);
    }
    barrier();
    for(uint c=lane;c<p.size;c+=uint(LANES)) {
        float dot_rhs=0.0;for(uint r=0u;r<p.size;++r) dot_rhs+=b[c*uint(SVD_SIZE)+r]*rhs.b[r];
        coefficient[c]=norm2[c]>cutoff ? dot_rhs/norm2[c] : 0.0;
    }
    barrier();
    for(uint r=lane;r<p.size;r+=uint(LANES)) {
        float x=0.0;for(uint c=0u;c<p.size;++c) x+=v[c*uint(SVD_SIZE)+r]*coefficient[c];
        solution.x[r]=x;null_vector.x[r]=v[least*uint(SVD_SIZE)+r];
    }
}
