#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Force {vec2 force[];};
layout(set=0,binding=1,std430) buffer Trial {vec2 velocity[];};
layout(set=0,binding=2,std430) readonly buffer Resistance {vec2 h[];};
layout(set=0,binding=3,std430) readonly buffer OperatorStatus {uint operator_ok;};
layout(set=0,binding=4,std430) buffer Output {vec2 published[];};
layout(set=0,binding=5,std430) buffer Status {uint accepted;uint failed;uint iterations;float residual;};
layout(push_constant,std430) uniform Params {uint count;uint phase;uint last;float tolerance;} pc;
bool finite2(vec2 x){return !any(isnan(x))&&!any(isinf(x));}
void main(){
 if(pc.phase==0u){
  accepted=0u;failed=0u;iterations=0u;residual=0.;
  for(uint i=0u;i<pc.count;i++){velocity[i]=vec2(0.);if(!finite2(force[i]))failed=1u;}
  return;
 }
 if(pc.phase==2u){
  if(accepted==1u && failed==0u)for(uint i=0u;i<pc.count;i++)published[i]=velocity[i];
  return;
 }
 if(accepted!=0u || failed!=0u)return;
 // A pressure budget miss may improve with the cached pressure on the next
 // bounded outer call. Never consume the previous published H on a miss.
 if(operator_ok!=1u){if(pc.last!=0u)failed=1u;return;}
 float peak=0.;
 for(uint i=0u;i<pc.count;i++){
  vec2 r=force[i]-h[i];
  if(!finite2(r)||!finite2(velocity[i])){failed=1u;return;}
  peak=max(peak,max(abs(r.x),abs(r.y)));
 }
 residual=peak;
 if(peak<=pc.tolerance){accepted=1u;return;}
 if(pc.last!=0u)return;
 // Damped Richardson with the positive background resistance as preconditioner.
 // Convergence is certified from a fresh H(v), never from the recurrence alone.
 for(uint i=0u;i<pc.count;i++)velocity[i]+=20.*(force[i]-h[i]);
 iterations++;
}
