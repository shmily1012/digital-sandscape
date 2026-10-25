#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(r32ui,set=0,binding=0) readonly uniform uimage2D cells;
layout(rgba8,set=0,binding=1) writeonly uniform image2D artwork;
layout(push_constant,std430) uniform Params {uint filtered;uint pad0;uint pad1;uint pad2;} pc;
const vec3 water=vec3(.73,.75,.74);
bool mineral(uint m){return m>=1u && m<=3u;}
vec3 palette(uint m){
 if(m==1u)return vec3(.09,.10,.105);
 if(m==2u)return vec3(.39,.41,.42);
 if(m==3u)return vec3(.88,.86,.80);
 return water;
}
uint read_cell(ivec2 q){return imageLoad(cells,clamp(q,ivec2(0),imageSize(cells)-1)).r;}
void main(){
 ivec2 pixel=ivec2(gl_GlobalInvocationID.xy);
 if(any(greaterThanEqual(pixel,imageSize(artwork))))return;
 vec2 point=(vec2(pixel)+.5)*vec2(imageSize(cells))/vec2(imageSize(artwork));
 ivec2 cell=ivec2(floor(point));uint material=read_cell(cell);
 vec3 color=palette(material);
 if(pc.filtered==0u){
  if(material==5u){
   bool edge=false;
   for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++)if(read_cell(cell+ivec2(x,y))!=5u)edge=true;
   color=edge?vec3(.53,.57,.57):vec3(.83,.85,.83);
  }
 }else{
  // Compact optical reconstruction only; all samples come from the current material field.
  float sum=0.,sand=0.,gas=0.;vec3 pigment=vec3(0.);
  for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){
   ivec2 q=cell+ivec2(x,y);uint m=read_cell(q);
   vec2 d=(vec2(q)+.5)-point;
   float weight=max(0.,1.25-abs(d.x))*max(0.,1.25-abs(d.y));
   sum+=weight;
   if(mineral(m)){sand+=weight;pigment+=weight*palette(m);}
   if(m==5u)gas+=weight;
  }
  float density=sand/max(sum,1e-6);
  vec3 mineral_color=sand>0.?pigment/sand:water;
  // Preserve isolated falling grains; blend pigments in dense deposits to reduce salt-and-pepper aliasing.
  if(mineral(material)){
   float packed=smoothstep(.35,.85,density);
   color=mix(palette(material),mineral_color,.85*packed);
   float coverage=1.-smoothstep(.23,.62,length(fract(point)-.5));
   color=mix(water,color,mix(coverage,1.,packed));
  }else if(material==0u && density>.55){
   color=mix(water,mineral_color,.45*smoothstep(.55,.95,density));
  }
  float gas_coverage=gas/max(sum,1e-6);
  if(gas_coverage>.05){
   float edge=exp(-pow((gas_coverage-.45)/.22,2.));
   vec3 bubble=mix(vec3(.84,.86,.84),vec3(.53,.57,.57),edge);
   color=mix(color,bubble,smoothstep(.08,.4,gas_coverage));
  }
 }
 if(mineral(material)){
  uint h=uint(pixel.x)*1664525u ^ uint(pixel.y)*1013904223u;
  color*=.975+float(h&255u)/255.*.05;
 }
 imageStore(artwork,pixel,vec4(color,material==4u?0.:1.));
}
