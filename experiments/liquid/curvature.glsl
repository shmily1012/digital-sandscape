#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly restrict buffer Fraction { float c[]; } gas;
layout(set=0,binding=1,std430) writeonly restrict buffer Curvature { vec2 value[]; } result;
layout(push_constant,std430) uniform Params { uint side; uint pad0; uint pad1; uint pad2; } p;
float sample_cell(ivec2 cell) { return gas.c[cell.y*int(p.side)+cell.x]; }
bool same_pure_phase(float a,float b) { return max(a,b)<=1e-6 || min(a,b)>=1.0-1e-6; }
void main() {
    uint index=gl_GlobalInvocationID.x;
    if(index>=p.side*p.side) return;
    result.value[index]=vec2(0.0);
    ivec2 cell=ivec2(index%p.side,index/p.side);
    float c=gas.c[index];
    if(cell.x<1 || cell.y<1 || cell.x>=int(p.side)-1 || cell.y>=int(p.side)-1 || c<=1e-10 || c>=1.0-1e-10) return;
    float gx=sample_cell(cell+ivec2(1,0))-sample_cell(cell-ivec2(1,0));
    float gy=sample_cell(cell+ivec2(0,1))-sample_cell(cell-ivec2(0,1));
    if(abs(gx)+abs(gy)<1e-12) return;
    int preferred=abs(gy)>=abs(gx) ? 1 : 0;
    for(int attempt=0;attempt<2;++attempt) {
        int axis=attempt==0 ? preferred : 1-preferred;
        vec3 heights=vec3(0.0);
        bool valid=true;
        for(int column=-1;column<=1;++column) {
            ivec2 origin=cell+(axis==1 ? ivec2(column,0) : ivec2(0,column));
            ivec2 direction=axis==1 ? ivec2(0,1) : ivec2(1,0);
            ivec2 first=origin-5*direction,last=origin+5*direction;
            if(any(lessThan(first,ivec2(0))) || any(greaterThanEqual(last,ivec2(p.side)))) { valid=false;break; }
            float a=sample_cell(first),b=sample_cell(last);
            if(!((a<=1e-6 && b>=1.0-1e-6) || (b<=1e-6 && a>=1.0-1e-6))) { valid=false;break; }
            float sign_value=b>a ? 1.0 : -1.0;
            float previous=a,total=0.0;
            for(int offset=-5;offset<=5;++offset) {
                float value=sample_cell(origin+offset*direction);
                if(isnan(value)||isinf(value)||(sign_value*(value-previous)<-1e-8 && !same_pure_phase(value,previous))) valid=false;
                total+=value;previous=value;
            }
            heights[column+1]=total/float(p.side);
        }
        if(valid) {
            float derivative=(heights.z-heights.x)*0.5*float(p.side);
            float second=(heights.z-2.0*heights.y+heights.x)*float(p.side*p.side);
            result.value[index]=vec2(-second/pow(1.0+derivative*derivative,1.5),1.0);
            return;
        }
    }
}
