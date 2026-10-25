#[compute]
#version 450
layout(local_size_x=64) in;
struct Equation {vec4 weights;vec4 source;};
layout(set=0,binding=0,std430) readonly buffer Faces {uvec4 face[];};
layout(set=0,binding=1,std430) readonly buffer Source {float source[];};
layout(set=0,binding=2,std430) readonly buffer Adjacency {ivec4 adjacent[];};
layout(set=0,binding=3,std430) buffer Equations {Equation cell[];};
layout(set=0,binding=4,std430) readonly buffer Pressure {float p[];};
layout(set=0,binding=5,std430) readonly buffer Mobility {float mobility[];};
layout(set=0,binding=6,std430) buffer Liquid {float q[];};
layout(set=0,binding=7,std430) readonly buffer GeometryStatus {uint geometry_ok;};
layout(set=0,binding=8,std430) buffer PressureStatus {uint pressure_status[];};
layout(set=0,binding=9,std430) readonly buffer Velocity {vec2 v[];};
layout(set=0,binding=10,std430) readonly buffer Adjoint {vec2 adjoint[];};
layout(set=0,binding=11,std430) buffer Candidate {vec2 candidate[];};
layout(set=0,binding=12,std430) buffer Published {vec2 output_h[];};
layout(set=0,binding=13,std430) buffer Flags {uint valid[];};
layout(set=0,binding=14,std430) buffer Status {uint accepted;};
layout(set=0,binding=15,std430) buffer Scale {float source_scale;};
layout(push_constant,std430) uniform Params {uint count;uint faces;uint side;uint phase;} pc;
void main(){
 uint i=gl_GlobalInvocationID.x;
 if(pc.phase==5u){
  if(i<pc.faces)q[i]=0.;
  if(i==0u){for(uint j=0u;j<4u;j++)pressure_status[j]=0u;accepted=0u;}
  return;
 }
 if(pc.phase==6u){
  if(i!=0u)return;
  float peak=0.;
  if(geometry_ok==1u)for(uint f=0u;f<pc.faces;f++)peak=max(peak,abs(source[f]));
  source_scale=peak;return;
 }
 if(pc.phase==0u){
  if(i>=pc.side*pc.side)return;
  // Preserve divide-before-scale ordering near float32 limits.
  precise float rhs=0.;ivec4 a=adjacent[i];
  for(int k=0;k<4;k++)if(a[k]>=0)rhs+=(k%2==0?1.:-1.)*(source[a[k]]/(source_scale>0.?source_scale:1.))*float(pc.side);
  cell[i].source.x=geometry_ok==1u?rhs:0.;return;
 }
 if(pc.phase==1u){
  if(i<pc.faces){
   precise float normalized_q=-mobility[i]*(p[face[i].y]-p[face[i].x])*float(pc.side);
   precise float restored_q=normalized_q*source_scale;
   q[i]=source_scale==0.?0.:restored_q;
  }
  return;
 }
 if(pc.phase==2u){
  if(i>=pc.count)return;
  precise vec2 h=.04*v[i]+adjoint[i];candidate[i]=h;
  valid[i]=any(isnan(h))||any(isinf(h))?0u:1u;return;
 }
 if(pc.phase==3u){
  if(i!=0u)return;
  uint ok=geometry_ok & pressure_status[1];
  for(uint j=0u;j<pc.count;j++)ok &= valid[j];accepted=ok;return;
 }
 if(i<pc.count && accepted==1u)output_h[i]=candidate[i];
}
