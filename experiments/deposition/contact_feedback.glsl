#[compute]
#version 450
layout(local_size_x=64) in;
struct Grain {vec4 geom;vec4 props;};
struct Contact {vec4 geometry;ivec4 ids;vec4 reaction;};
struct Face {uint a;uint b;float mobility;float source;};
struct Equation {vec4 weights;vec4 source;};
layout(set=0,binding=0,std430) readonly buffer Input {Grain g[];} src;
layout(set=0,binding=1,std430) readonly buffer Candidate {Grain g[];} candidate;
layout(set=0,binding=2,std430) readonly buffer Contacts {Contact c[];} contacts;
layout(set=0,binding=3,std430) readonly buffer ContactStatus {uvec4 value;} contact_status;
layout(set=0,binding=4,std430) readonly buffer Norm {vec2 w[];} norm;
layout(set=0,binding=5,std430) buffer Faces {Face f[];} faces;
layout(set=0,binding=6,std430) buffer Equations {Equation c[];} equations;
layout(set=0,binding=7,std430) readonly buffer Adjacency {ivec4 ids[];} adjacency;
layout(set=0,binding=8,std430) readonly buffer Pressure {float p[];} pressure;
layout(set=0,binding=9,std430) readonly buffer PressureStatus {uint word[];} pressure_status;
layout(set=0,binding=10,std430) buffer Published {Grain g[];} published;
layout(set=0,binding=11,std430) buffer PublishedFlux {float u[];} flux;
layout(set=0,binding=12,std430) buffer JointStatus {uvec4 value;} status;
layout(set=0,binding=13,std430) buffer NetForces {vec2 f[];} net;
layout(set=0,binding=14,std430) readonly buffer Self {vec4 k[];} self_response;
layout(push_constant,std430) uniform Params {uint grains;uint faces;uint contacts;uint phase;vec2 gravity;float dt;uint side;} p;
uint axis_of(Face f){return f.b-f.a==1u?0u:1u;}
float weight(Face f,vec2 point){vec2 a=vec2(f.a%p.side,f.a/p.side),b=vec2(f.b%p.side,f.b/p.side);vec2 center=((a+b)*0.5+0.5)/float(p.side);vec2 w=max(vec2(0),1.0-abs(center-point)*float(p.side)*0.5);return w.x*w.y;}
float face_velocity(uint k){Face f=faces.f[k];return f.source-f.mobility*(pressure.p[f.b]-pressure.p[f.a])*float(p.side);}
void main(){
 uint i=gl_GlobalInvocationID.x;
 if(p.phase==0u){
  if(i==0u)status.value=uvec4(0);
  if(i>=p.grains)return;
  net.f[i]=vec2(0);
  if(contact_status.value.x!=1u)return;
  Grain g=src.g[i];precise float area=3.141592653589793*(g.geom.z*g.geom.z);precise float mass=(g.props.x-1.0)*area;
  precise vec2 total=mass*p.gravity;
  for(uint k=0u;k<p.contacts;++k){Contact c=contacts.c[k];vec2 n=c.geometry.xy;vec2 f=n*c.reaction.x+vec2(-n.y,n.x)*c.reaction.y;if(c.ids.x==int(i))total+=f;if(c.ids.y==int(i))total-=f;}
  net.f[i]=total;
 }else if(p.phase==1u){
  if(i>=p.faces)return;
  Face f=faces.f[i];uint axis=axis_of(f);float total=0.0;
  for(uint g=0u;g<p.grains;++g)total+=weight(f,src.g[g].geom.xy)/norm.w[g][axis]*net.f[g][axis];
  faces.f[i].source=f.mobility*total*float(p.side*p.side);
 }else if(p.phase==2u){
  if(i>=p.side*p.side)return;
  float d=0.0;
  for(int k=0;k<4;++k){int id=adjacency.ids[i][k];if(id>=0){Face f=faces.f[id];d+=(f.a==i?1.0:-1.0)*f.source*float(p.side);}}
  equations.c[i].source.x=-d;
 }else if(p.phase==3u){
  if(i!=0u)return;
  if(contact_status.value.x!=1u||pressure_status.word[1]!=1u||pressure_status.word[3]!=0u)return;
  float maximum=0.0;
  for(uint g=0u;g<p.grains;++g){
   vec2 u=vec2(0);
   for(uint k=0u;k<p.faces;++k){Face f=faces.f[k];uint axis=axis_of(f);float value=face_velocity(k);if(isnan(value)||isinf(value))return;u[axis]+=weight(f,src.g[g].geom.xy)/norm.w[g][axis]*value;}
   vec2 force=net.f[g];vec4 own=self_response.k[g];
   vec2 velocity=u-vec2(dot(own.xy,force),dot(own.zw,force))+force/src.g[g].geom.w;
   vec2 expected=src.g[g].geom.xy+p.dt*velocity;
   float error=length(candidate.g[g].geom.xy-expected);
   if(isnan(error)||isinf(error))return;
   maximum=max(maximum,error);
  }
  status.value=uvec4(maximum<=2e-7?1u:0u,floatBitsToUint(maximum),0,0);
 }else if(p.phase==4u){
  if(status.value.x!=1u)return;
  if(i<p.grains)published.g[i]=candidate.g[i];
  if(i<p.faces)flux.u[i]=face_velocity(i);
 }
}
