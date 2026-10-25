#[compute]
#version 450
layout(local_size_x=8,local_size_y=8) in;
layout(set=0,binding=0,std430) readonly buffer Materials { uint material[]; };
layout(set=0,binding=1,std430) buffer Loads { float load[]; };
layout(push_constant,std430) uniform Params { uint side;uint wave;float gx;float gy; } p;
shared float tile_load[64];
int index_at(ivec2 logical){
    ivec2 q=ivec2(p.gx<0.?int(p.side)-1-logical.x:logical.x,p.gy<0.?int(p.side)-1-logical.y:logical.y);
    return q.y*int(p.side)+q.x;
}
void main(){
    int tiles=(int(p.side)+7)/8;
    ivec2 tile=ivec2(int(gl_WorkGroupID.x),int(p.wave)-int(gl_WorkGroupID.x));
    if(tile.x>=tiles||tile.y<0||tile.y>=tiles)return;
    ivec2 local=ivec2(gl_LocalInvocationID.xy),logical=tile*8+local;
    int lane=local.y*8+local.x;tile_load[lane]=0.;barrier();
    float sum_g=abs(p.gx)+abs(p.gy);
    vec2 share=sum_g>0.?abs(vec2(p.gx,p.gy))/sum_g:vec2(0);
    bool valid=all(lessThan(logical,ivec2(p.side)));
    for(int diagonal=0;diagonal<15;diagonal++){
        if(valid&&local.x+local.y==diagonal&&sum_g>0.){
            int i=index_at(logical);uint m=material[i];
            float value=m==2u?2.0:(m==3u?1.7:(m==4u?1.4:0.));
            if(logical.x>0){
                int parent=index_at(logical-ivec2(1,0));
                if(material[parent]>=2u)value+=share.x*(local.x>0?tile_load[lane-1]:load[parent]);
            }
            if(logical.y>0){
                int parent=index_at(logical-ivec2(0,1));
                if(material[parent]>=2u)value+=share.y*(local.y>0?tile_load[lane-8]:load[parent]);
            }
            tile_load[lane]=value;
        }
        barrier();
    }
    if(valid)load[index_at(logical)]=tile_load[lane];
}
