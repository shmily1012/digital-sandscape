#[compute]
#version 450
// Frozen split-region operator A = L + dt S M^-1 S^T.
// Two passes, unique writers and a dispatch barrier; no atomics or state commit.
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Pressure { float pressure[]; };
layout(set=0,binding=1,std430) readonly buffer Edges { uvec2 edges[]; };
layout(set=0,binding=2,std430) readonly buffer EdgeRows { uint edge_rows[]; };
layout(set=0,binding=3,std430) readonly buffer Weights { uvec4 weights[]; };
layout(set=0,binding=4,std430) readonly buffer NodeRows { uint node_rows[]; };
layout(set=0,binding=5,std430) readonly buffer NodeIds { uint node_ids[]; };
layout(set=0,binding=6,std430) readonly buffer GrainRows { uint grain_rows[]; };
layout(set=0,binding=7,std430) readonly buffer GrainIds { uint grain_ids[]; };
layout(set=0,binding=8,std430) readonly buffer Mass { float mass[]; };
layout(set=0,binding=9,std430) readonly buffer Velocity { vec2 velocity[]; };
layout(set=0,binding=10,std430) buffer Force { vec2 force[]; };
layout(set=0,binding=11,std430) writeonly buffer Output { vec2 output_values[]; };
layout(set=0,binding=12,std430) readonly buffer SolveControl { vec4 solve_control; };
layout(set=0,binding=13,std430) readonly buffer PressureLow { float pressure_low[]; };
layout(set=0,binding=14,std430) buffer ForceLow { vec2 force_low[]; };
layout(set=0,binding=15,std430) writeonly buffer OutputLow { vec2 output_low[]; };
layout(push_constant,std430) uniform Params { uint nodes; uint grains; uint mode; float dt; } p;
vec2 two_sum(float a,float b){precise float s=a+b;precise float v=s-a;precise float e=(a-(s-v))+(b-v);return vec2(s,e);}
vec2 ds_add(vec2 a,vec2 b){vec2 s=two_sum(a.x,b.x);precise float e=(s.y+a.y)+b.y;return two_sum(s.x,e);}
vec2 ds_mul(vec2 a,float b){precise float h=a.x*b;precise float l=fma(a.x,b,-h)+a.y*b;return two_sum(h,l);}
vec2 ds_div(vec2 a,float b){precise float h=a.x/b;vec2 r=ds_add(a,-ds_mul(vec2(h,0),b));return two_sum(h,(r.x+r.y)/b);}
vec2 read_pressure(uint i){return vec2(pressure[i],pressure_low[i]);}
void main(){
    uint i=gl_GlobalInvocationID.x;
    // 0/1: active iteration; 2/3: unconditional; 4/5: verify apparent convergence.
    if(p.mode<2u&&solve_control.w!=0.)return;
    if(p.mode>=4u&&solve_control.w!=1.)return;
    if((p.mode&1u)==0u){
        if(i>=p.grains)return;
        vec2 sx=vec2(0),sy=vec2(0);
        for(uint k=grain_rows[i];k<grain_rows[i+1u];k++){
            uvec4 w=weights[grain_ids[k]];
            vec2 normal=uintBitsToFloat(w.zw),value=read_pressure(w.x);
            sx=ds_add(sx,ds_mul(value,-normal.x));sy=ds_add(sy,ds_mul(value,-normal.y));
        }
        force[i]=vec2(sx.x,sy.x);force_low[i]=vec2(sx.y,sy.y);return;
    }
    if(i>=p.nodes)return;
    vec2 sum=vec2(0),source=vec2(0);
    for(uint k=edge_rows[i];k<edge_rows[i+1u];k++){
        uvec2 e=edges[k];
        sum=ds_add(sum,ds_mul(ds_add(read_pressure(i),-read_pressure(e.x)),uintBitsToFloat(e.y)));
    }
    for(uint k=node_rows[i];k<node_rows[i+1u];k++){
        uvec4 w=weights[node_ids[k]];vec2 normal=uintBitsToFloat(w.zw);
        vec2 reaction=ds_add(ds_mul(vec2(force[w.y].x,force_low[w.y].x),normal.x),
                            ds_mul(vec2(force[w.y].y,force_low[w.y].y),normal.y));
        sum=ds_add(sum,ds_div(ds_mul(reaction,-p.dt),mass[w.y]));
        source=ds_add(source,ds_add(ds_mul(vec2(velocity[w.y].x,0),normal.x),ds_mul(vec2(velocity[w.y].y,0),normal.y)));
    }
    output_values[i]=vec2(sum.x,source.x);output_low[i]=vec2(sum.y,source.y);
}
