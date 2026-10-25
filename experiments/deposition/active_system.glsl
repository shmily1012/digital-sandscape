#[compute]
#version 450
#ifndef CONTACT_CAPACITY
#define CONTACT_CAPACITY 16
#endif
#define MATRIX_SIZE (2 * CONTACT_CAPACITY)
// Assemble a fixed 32x32 padded active Jacobian from current contact forces.
layout(local_size_x=1) in;
struct Grain {vec4 geom;vec4 props;};
struct Contact {vec4 geometry;ivec4 ids;vec4 reaction;};
layout(set=0,binding=0,std430) readonly buffer Grains {Grain g[];} grains;
layout(set=0,binding=1,std430) readonly buffer Contacts {Contact c[];} contacts;
layout(set=0,binding=2,std430) writeonly buffer Matrix {float a[];} matrix;
layout(set=0,binding=3,std430) writeonly buffer RHS {float b[];} rhs;
layout(set=0,binding=4,std430) writeonly buffer Selection {uint ids[];} selection;
layout(set=0,binding=5,std430) writeonly buffer Meta {uvec4 state;} meta;
layout(push_constant,std430) uniform Params {uint grains;uint contacts;float dt;float friction;vec2 gravity;float tolerance;uint pad;} p;
vec2 velocity[16];vec2 speeds[CONTACT_CAPACITY];vec2 residuals[CONTACT_CAPACITY];uint selected_ids[CONTACT_CAPACITY];
vec2 normal(Contact c) {return c.geometry.xy;}
vec2 tangent(Contact c) {return vec2(-c.geometry.y,c.geometry.x);}
vec2 relative(Contact c) {vec2 v=velocity[c.ids.x];if(c.ids.y>=0)v-=velocity[c.ids.y];return vec2(dot(v,normal(c))+c.geometry.z/p.dt,dot(v,tangent(c)));}
float coupling(Contact a,vec2 da,Contact b,vec2 db) {
    float value=0.0;
    if(a.ids.x==b.ids.x)value+=1.0/grains.g[a.ids.x].geom.w;
    if(a.ids.x==b.ids.y)value-=1.0/grains.g[a.ids.x].geom.w;
    if(a.ids.y>=0) {
        if(a.ids.y==b.ids.x)value-=1.0/grains.g[a.ids.y].geom.w;
        if(a.ids.y==b.ids.y)value+=1.0/grains.g[a.ids.y].geom.w;
    }
    return dot(da,db)*value;
}
void main() {
    meta.state=uvec4(0,0,0,1);
    for(uint r=0u;r<uint(MATRIX_SIZE);++r){rhs.b[r]=0.0;for(uint c=0u;c<uint(MATRIX_SIZE);++c)matrix.a[r*uint(MATRIX_SIZE)+c]=r==c?100.0:0.0;}
    if(p.grains==0u||p.grains>16u||p.contacts>1144u||p.dt<=0.0||isnan(p.dt)||isinf(p.dt)||p.friction<0.0||isnan(p.friction)||isinf(p.friction)||p.tolerance<=0.0||isnan(p.tolerance)||isinf(p.tolerance)) return;
    for(uint i=0u;i<p.grains;++i) {
        Grain g=grains.g[i];
        if(any(isnan(g.geom))||any(isinf(g.geom))||g.geom.w<=0.0||g.geom.z<=0.0||isnan(g.props.x)||isinf(g.props.x))return;
        vec2 force=(g.props.x-1.0)*3.141592653589793*g.geom.z*g.geom.z*p.gravity;
        vec2 correction=vec2(0);
        for(uint k=0u;k<p.contacts;++k) {
            Contact c=contacts.c[k];
            if(any(isnan(c.geometry))||any(isinf(c.geometry))||any(isnan(c.reaction))||any(isinf(c.reaction)))return;
            if(c.ids.x<0||c.ids.x>=int(p.grains)||c.ids.y>=int(p.grains)||c.ids.y < -1) return;
            vec2 f=normal(c)*c.reaction.x+tangent(c)*c.reaction.y;
            float sign=c.ids.x==int(i)?1.0:(c.ids.y==int(i)?-1.0:0.0);
            vec2 y=sign*f-correction;vec2 next=force+y;correction=(next-force)-y;force=next;
        }
        velocity[i]=force/g.geom.w;
        if(any(isnan(velocity[i]))||any(isinf(velocity[i])))return;
    }
    uint count=0u;float maximum=0.0;
    for(uint k=0u;k<p.contacts;++k) {
        Contact c=contacts.c[k];vec2 speed=relative(c),lambda=c.reaction.xy;float mobility=c.geometry.w;
        if(mobility<=0.0||isnan(mobility)||isinf(mobility))return;
        vec2 projected=vec2(max(0.0,lambda.x-speed.x/mobility),clamp(lambda.y-speed.y/mobility,-p.friction*max(0.0,lambda.x),p.friction*max(0.0,lambda.x)));
        vec2 f=(lambda-projected)*mobility;
        maximum=max(maximum,max(abs(f.x),abs(f.y)));
        if(lambda.x>1e-14||speed.x < -p.tolerance||abs(f.y)>p.tolerance) {
            if(count==uint(CONTACT_CAPACITY)){meta.state=uvec4(0,CONTACT_CAPACITY+1,floatBitsToUint(maximum),2);return;}
            selected_ids[count]=k;speeds[count]=speed;residuals[count]=f;count++;
        }
    }
    for(uint i=0u;i<count;++i) {
        selection.ids[i]=selected_ids[i];Contact a=contacts.c[selected_ids[i]];vec2 lambda=a.reaction.xy;float mobility=a.geometry.w;
        bool closed=lambda.x-speeds[i].x/mobility>0.0;
        float z=lambda.y-speeds[i].y/mobility,bound=p.friction*max(0.0,lambda.x);
        bool sticking=z > -bound && z < bound;
        rhs.b[2u*i]=-residuals[i].x;rhs.b[2u*i+1u]=-residuals[i].y;
        for(uint j=0u;j<count;++j) {
            Contact b=contacts.c[selected_ids[j]];
            matrix.a[(2u*i)*uint(MATRIX_SIZE)+2u*j]=closed ? coupling(a,normal(a),b,normal(b)) : (i==j ? mobility : 0.0);
            matrix.a[(2u*i)*uint(MATRIX_SIZE)+2u*j+1u]=closed ? coupling(a,normal(a),b,tangent(b)) : 0.0;
            matrix.a[(2u*i+1u)*uint(MATRIX_SIZE)+2u*j]=sticking ? coupling(a,tangent(a),b,normal(b)) : (i==j ? (z>=bound?-p.friction:p.friction)*mobility : 0.0);
            matrix.a[(2u*i+1u)*uint(MATRIX_SIZE)+2u*j+1u]=sticking ? coupling(a,tangent(a),b,tangent(b)) : (i==j ? mobility : 0.0);
        }
    }
    meta.state=uvec4(1,count,floatBitsToUint(maximum),0);
}
