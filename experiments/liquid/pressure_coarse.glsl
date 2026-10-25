#[compute]
#version 450
// The 4x4 coarsest graph fits in one workgroup. Input/output storage must be distinct.
// All Jacobi iterations use workgroup memory and uniform barriers.
layout(local_size_x=64) in;
struct Equation {vec4 weights;vec4 source;};
layout(set=0,binding=0,std430) readonly buffer Previous {float p[];} previous;
layout(set=0,binding=1,std430) writeonly buffer Next {float p[];} next_state;
layout(set=0,binding=2,std430) readonly buffer Equations {Equation cell[];} equations;
layout(push_constant,std430) uniform Params {uint size;float relaxation;uint pad0;uint pad1;} pc;
shared float current[16];
shared float next_value[16];
void main(){
 uint i=gl_LocalInvocationID.x;
 if(i<16u)current[i]=previous.p[i];
 barrier();
 for(uint step=0u;step<32u;step++){
  if(i<16u){
   vec4 w=equations.cell[i].weights;float diagonal=dot(w,vec4(1.));
   float sum=equations.cell[i].source.x;
   if(w.x>0.)sum+=w.x*current[i-1u];
   if(w.y>0.)sum+=w.y*current[i+1u];
   if(w.z>0.)sum+=w.z*current[i-4u];
   if(w.w>0.)sum+=w.w*current[i+4u];
   next_value[i]=diagonal==0.?0.:mix(current[i],sum/diagonal,pc.relaxation);
  }
  barrier();
  if(i<16u)current[i]=next_value[i];
  barrier();
 }
 if(i<16u)next_state.p[i]=current[i];
}
