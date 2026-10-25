#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
struct Grain {vec4 geom;vec4 props;};
layout(set=0,binding=0,std430) readonly buffer Grains {Grain g[];} grains;
layout(set=0,binding=1,rgba8) uniform writeonly image2D output_image;
layout(set=0,binding=2,std430) readonly buffer Planes {vec4 p[];} planes;
layout(push_constant,std430) uniform Params {uint count;uint side;uint walls;uint pad;} p;
void main(){
 ivec2 pixel=ivec2(gl_GlobalInvocationID.xy);if(any(greaterThanEqual(pixel,ivec2(p.side))))return;
 vec2 point=(vec2(pixel)+0.5)/float(p.side);float aa=1.0/float(p.side);
 float radius=length(point-0.5);
 vec3 color=vec3(.075,.08,.085);
 color=mix(color,vec3(.79,.80,.79),1.0-smoothstep(.459-aa,.459+aa,radius));
 // The thin line depicts the actual contact fixture, not an invented deposit.
 float edge=1.0;
 for(uint i=0u;i<p.walls;++i)edge=min(edge,abs(dot(planes.p[i].xy,point)-planes.p[i].z));
 if(radius<.455)color=mix(color,vec3(.36),1.0-smoothstep(aa,2.0*aa,edge));
 for(uint i=0u;i<p.count;++i){
  Grain g=grains.g[i];float distance=length(point-g.geom.xy);
  float coverage=1.0-smoothstep(g.geom.z-aa,g.geom.z+aa,distance);
  float shade=g.props.y<1.5?.11:(g.props.y<2.5?.43:.91);
  color=mix(color,vec3(shade),coverage);
 }
 imageStore(output_image,pixel,vec4(color,1));
}
