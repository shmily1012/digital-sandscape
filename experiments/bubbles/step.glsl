#[compute]
#version 450
layout(local_size_x=64, local_size_y=1, local_size_z=1) in;
struct Body {
    vec4 geometry; // x, y, radius, log aspect (0 for grains).
    vec4 properties; // kind (0 grain, 1 bubble), material, density, reserved.
};
layout(set=0, binding=0, std430) readonly restrict buffer InputState { Body body[]; } src;
layout(set=0, binding=1, std430) writeonly restrict buffer OutputState { Body body[]; } dst;
layout(push_constant, std430) uniform Parameters {
    vec2 gravity;
    vec2 extent;
    float tension;
    float stiffness;
    float grain_drag;
    float bubble_drag;
    float shape_mobility;
    float dt;
    uint count;
    uint pad;
} p;
const float PI=3.14159265358979323846;
vec2 axes(Body b) { return b.geometry.z*exp(vec2(b.geometry.w,-b.geometry.w)); }
// Returns force on the first (external) body and overlap coordinate.
vec3 ellipse_contact(vec2 delta, vec2 ab, float stiffness) {
    float q=length(delta/ab);
    if(q>=1.0) return vec3(0.0);
    if(q<1e-12) return vec3(stiffness/ab.x,0.0,1.0);
    return vec3(stiffness*(1.0-q)/q*delta/(ab*ab),1.0-q);
}
float shape_derivative(vec2 ab) {
    float u=(ab.x-ab.y)/(ab.x+ab.y);
    float h=u*u;
    float root=sqrt(4.0-3.0*h);
    float denominator=10.0+root;
    float f=1.0+3.0*h/denominator;
    float derivative=3.0/denominator+4.5*h/(root*denominator*denominator);
    return PI*((ab.x-ab.y)*f+(ab.x+ab.y)*derivative*2.0*u*(1.0-u*u));
}
void main() {
    uint i=gl_GlobalInvocationID.x;
    if(i>=p.count) return;
    Body current=src.body[i];
    bool gas=current.properties.x>0.5;
    float radius=current.geometry.z;
    vec2 ab=axes(current);
    vec2 force=(gas ? -1.0 : current.properties.z-1.0)*PI*radius*radius*p.gravity;
    float shape_force=gas ? -p.tension*shape_derivative(ab) : 0.0;
    for(uint j=0u;j<p.count;++j) {
        if(i==j) continue;
        Body other=src.body[j];
        bool other_gas=other.properties.x>0.5;
        if(!gas && !other_gas) {
            vec2 delta=current.geometry.xy-other.geometry.xy;
            float distance=length(delta);
            float overlap=radius+other.geometry.z-distance;
            if(overlap>0.0) {
                vec2 normal=distance>1e-12 ? delta/distance : vec2(i>j ? 1.0 : -1.0,0.0);
                force+=p.stiffness*overlap*normal;
            }
        } else if(gas && other_gas) {
            vec2 summed=ab+axes(other);
            vec2 delta=current.geometry.xy-other.geometry.xy;
            vec3 contact=ellipse_contact(delta,summed,p.stiffness*0.1);
            if(length(delta)<1e-12 && i<j) contact.xy=-contact.xy;
            force+=contact.xy;
            float q=length(delta/summed);
            if(contact.z>0.0 && q>1e-12) {
                vec2 term=delta*delta*ab/(summed*summed*summed);
                shape_force+=p.stiffness*0.1*contact.z/q*(-term.x+term.y);
            }
        } else {
            Body grain=gas ? other : current;
            Body bubble=gas ? current : other;
            vec2 bubble_axes=axes(bubble);
            vec2 inflated=bubble_axes+vec2(grain.geometry.z);
            vec2 delta=grain.geometry.xy-bubble.geometry.xy;
            vec3 contact=ellipse_contact(delta,inflated,p.stiffness*grain.geometry.z);
            force+=gas ? -contact.xy : contact.xy;
            float q=length(delta/inflated);
            if(gas && contact.z>0.0 && q>1e-12) {
                vec2 term=delta*delta*bubble_axes/(inflated*inflated*inflated);
                shape_force+=p.stiffness*grain.geometry.z*contact.z/q*(-term.x+term.y);
            }
        }
    }
    if(gas) {
        float limit=min(log(2.5),log(min(p.extent.x,p.extent.y)/(2.0*radius)));
        current.geometry.w=clamp(current.geometry.w+p.dt*p.shape_mobility*shape_force,-limit,limit);
        ab=axes(current);
        current.geometry.xy=clamp(current.geometry.xy+p.dt*force/p.bubble_drag,ab,p.extent-ab);
    } else {
        current.geometry.xy=clamp(current.geometry.xy+p.dt*force/p.grain_drag,vec2(radius),p.extent-vec2(radius));
    }
    dst.body[i]=current;
}
