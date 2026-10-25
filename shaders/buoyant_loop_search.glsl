#[compute]
#version 450
// GPU transaction for one bounded mixed gas/grain loop.
// Exactly one invocation owns the proposal; concurrent proposals are unsupported.
// This is an effective overdamped model, not a resolved pressure/contact solve.
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) buffer Phase { float c[]; };
layout(set=0,binding=1,std430) buffer Material { uint m[]; };
layout(set=0,binding=2,std430) buffer Populations { float f[]; };
layout(set=0,binding=3,std430) buffer Residual { float residual[]; };
layout(set=0,binding=4,std430) buffer Moved { uint moved[]; };
layout(set=0,binding=5,std430) readonly buffer Candidate { uint indices[]; };
layout(set=0,binding=6,std430) buffer Result { float delta_work; uint accepted; uint reason; uint accepted_total; float interface_work; float sand_work; float gas_work; uint candidates_total; };
layout(push_constant,std430) uniform Params {
    uint side;float sigma;float width;float cosine;
    uint tick;uint seed;uint color;uint drag;
    float gx;float gy;float weight_scale;float mobility_scale;
} p;
const ivec2 D[4]=ivec2[4](ivec2(1,0),ivec2(0,1),ivec2(-1,0),ivec2(0,-1));
int adjacent(int i,ivec2 d){
    ivec2 v=ivec2(i%int(p.side),i/int(p.side))+d;
    if(any(lessThan(v,ivec2(0)))||any(greaterThanEqual(v,ivec2(p.side))))return -1;
    return v.y*int(p.side)+v.x;
}
float bond(int i,int j){
    if(m[i]!=0u&&m[j]!=0u)return 0.;
    precise float kappa=1.5*p.sigma*p.width;
    if(m[i]==0u&&m[j]==0u){precise float value=.5*kappa*(c[i]-c[j])*(c[i]-c[j]);return value;}
    int fluid=m[i]==0u?i:j,solid=m[i]==0u?j:i;
    precise float cf=c[fluid],preference=m[solid]>=2u?p.cosine:0.;
    precise float a=2.*preference/p.width;
    precise float cb=a==0.?cf:2.*cf/(1.+a+sqrt((1.+a)*(1.+a)-4.*a*cf));
    precise float value=kappa*(cb-cf)*(cb-cf)+p.sigma*preference*cb*cb*(3.-2.*cb);return value;
}

uint hash32(uint x){x^=x<<13;x^=x>>17;x^=x<<5;return x;}
float grain_weight(uint material){return material==2u?2.:(material==3u?1.7:1.4);}
ivec2 rect_origin,rect_up,rect_side;
int rect_length,rect_width;
int path_index(int i,int path[192],int count){
    ivec2 v=ivec2(i%int(p.side),i/int(p.side))-rect_origin;
    int q=v.x*rect_up.x+v.y*rect_up.y;
    int h=v.x*rect_side.x+v.y*rect_side.y;
    if(h==0&&q>=1-rect_length&&q<=1)return q+rect_length-1;
    if(q==1&&h>=1&&h<=rect_width)return rect_length+h;
    if(h==rect_width&&q>=1-rect_length&&q<=0)return rect_length+rect_width+1-q;
    if(q==1-rect_length&&h>=1&&h<rect_width)return 2*rect_length+2*rect_width-h;
    return -1;
}
float wi,ws,wg;
float loop_work(int path[192],int count){
    precise float change=0.;wi=0.;ws=0.;wg=0.;
    for(int k=0;k<count;k++){
        int i=path[k],old_i=path[(k+count-1)%count];
        for(int q=0;q<4;q++){
            int j=adjacent(i,D[q]);if(j<0)continue;
            int slot=path_index(j,path,count);
            if(slot>=0&&j<i)continue;
            int old_j=slot<0?j:path[(slot+count-1)%count];
            float term=bond(old_i,old_j)-bond(i,j);change+=term;wi+=term;
        }
        int next=path[(k+1)%count];
        ivec2 displacement=ivec2(next%int(p.side)-i%int(p.side),next/int(p.side)-i/int(p.side));
        float effective_mass=m[i]>=2u?grain_weight(m[i])*p.weight_scale:-c[i];
        float work=-effective_mass*dot(vec2(p.gx,p.gy),vec2(displacement));
        change+=work;if(m[i]>=2u)ws+=work;else wg+=work;
    }
    return change;
}
// Scan one tick-selected column. One invocation owns all writes in this stage.
void main(){
    accepted=0u;reason=2u;
    if(p.gx==0.&&p.gy==0.)return;
    bool vertical=abs(p.gy)>=abs(p.gx);
    ivec2 up=vertical?ivec2(0,-sign(p.gy)):ivec2(-sign(p.gx),0);
    int lateral=0;
    const int WIDTHS[7]=int[7](1,2,4,8,16,24,32);
    int path[192];int count=0;bool found=false;
    for(int column=0;column<8&&!found;column++){
    lateral=int((8u*p.tick+p.seed+uint(column))%p.side);
    for(int axial=0;axial<int(p.side)&&!found;axial++){
        int coordinate=(up.x+up.y)<0?axial:int(p.side)-1-axial;
        ivec2 pos=vertical?ivec2(lateral,coordinate):ivec2(coordinate,lateral);
        int a=pos.y*int(p.side)+pos.x;
        int front=adjacent(a,up);
        if(m[a]<2u||moved[a]==p.tick||front<0||m[front]!=0u)continue;
        bool gas_seen=false,ended=false;int length=0;
        for(int k=0;k<64;k++){
            int j=adjacent(a,-k*up);
            if(j<0||m[j]==1u||(m[j]>=2u&&moved[j]==p.tick))break;
            if(m[j]==0u&&c[j]>.05)gas_seen=true;
            else if(m[j]==0u&&gas_seen&&c[j]<=.05){length=k;ended=true;break;}
            // Include the complete contiguous cap, up to the bounded column length.
        }
        if(!gas_seen||!ended||length<2)continue;
        // A grain without an actual liquid neighbor stays fixed, even if it
        // touches gas. Reject the entire transaction rather than omit its load.
        bool wet_cap=true;
        for(int k=0;k<length;k++){
            int j=adjacent(a,-k*up);if(m[j]<2u)continue;
            bool wet=false;
            for(int q=0;q<4;q++){int v=adjacent(j,D[q]);if(v>=0&&m[v]==0u&&c[v]<=.05){wet=true;break;}}
            if(!wet){wet_cap=false;break;}
        }
        if(!wet_cap)continue;
        for(int w=0;w<7&&!found;w++)for(int sign_index=0;sign_index<2&&!found;sign_index++){
            int width=WIDTHS[w];ivec2 side=ivec2(-up.y,up.x)*(sign_index==0?1:-1);
            count=0;
            for(int k=length-1;k>=0;k--)path[count++]=adjacent(a,-k*up);
            for(int k=0;k<=width;k++)path[count++]=adjacent(a,up+k*side);
            for(int k=0;k<length;k++)path[count++]=adjacent(a,-k*up+width*side);
            for(int k=width-1;k>0;k--)path[count++]=adjacent(a,-(length-1)*up+k*side);
            bool valid=count<=192;
            for(int k=length;k<count;k++)if(path[k]<0||m[path[k]]!=0u||c[path[k]]>.05){valid=false;break;}
            if(!valid)continue;
            rect_origin=pos;rect_up=up;rect_side=side;rect_length=length;rect_width=width;
            float candidate_work=loop_work(path,count);
            if(!isnan(candidate_work)&&!isinf(candidate_work)){
                if(candidates_total==0u||candidate_work<delta_work){delta_work=candidate_work;interface_work=wi;sand_work=ws;gas_work=wg;}
                candidates_total+=1u;reason=8u;
                if(candidate_work < -1.e-8)found=true;
            }
        }
    }
    }
    if(!found)return;
    float change=loop_work(path,count);
    if(isnan(change)||isinf(change)){reason=32u;return;}
    if(change>=-1.e-8){reason=8u;return;}
    int last=path[count-1];uint carry_m=m[last],carry_stamp=moved[last];
    float carry_c=c[last],carry_r=residual[last],carry_f[9];
    for(int q=0;q<9;q++)carry_f[q]=f[9*last+q];
    for(int k=0;k<count;k++){
        int i=path[k];uint old_m=m[i],old_stamp=moved[i];float old_c=c[i],old_r=residual[i];
        m[i]=carry_m;c[i]=carry_c;residual[i]=carry_r;moved[i]=carry_m>=2u?p.tick:carry_stamp;
        carry_m=old_m;carry_c=old_c;carry_r=old_r;carry_stamp=old_stamp;
        for(int q=0;q<9;q++){float old=f[9*i+q];f[9*i+q]=carry_f[q];carry_f[q]=old;}
    }
    accepted=1u;reason=0u;accepted_total+=1u;
}
