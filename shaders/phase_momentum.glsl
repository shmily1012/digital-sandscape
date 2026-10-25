#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Phase { float c[]; };
layout(set=0,binding=1,std430) readonly buffer Post { float f[]; };
layout(set=0,binding=2,std430) writeonly buffer Next { float next_f[]; };
layout(set=0,binding=3,std430) writeonly buffer Velocity { vec2 velocity[]; };
layout(set=0,binding=4,std430) readonly buffer Walls { uint wall[]; };
layout(set=0,binding=5,std430) readonly buffer Loads { float load[]; };
layout(set=0,binding=6,std430) readonly buffer BoundaryVelocity { vec2 boundary_velocity[]; };
layout(set=0,binding=7,std430) buffer MassResidual { float mass_residual[]; };
layout(set=0,binding=8,std430) readonly buffer InterfaceForce { vec2 interface_force[]; };
layout(push_constant,std430) uniform Params {
    uint side; float tau; float sigma; float width;
    // moving_boundary bits: 1 = moving bounce-back, 2 = paired interface stress.
    float gx; float gy; float load_factor; uint moving_boundary;
} p;
const ivec2 E[9]=ivec2[9](ivec2(0,0),ivec2(1,0),ivec2(0,1),ivec2(-1,0),ivec2(0,-1),ivec2(1,1),ivec2(-1,1),ivec2(-1,-1),ivec2(1,-1));
const float W[9]=float[9](4./9.,1./9.,1./9.,1./9.,1./9.,1./36.,1./36.,1./36.,1./36.);
const int O[9]=int[9](0,3,4,1,2,7,8,5,6);
int neighbor(int i,ivec2 d){
    ivec2 q=ivec2(i%int(p.side),i/int(p.side))+d;
    if(any(lessThan(q,ivec2(0)))||any(greaterThanEqual(q,ivec2(p.side))))return i;
    int j=q.y*int(p.side)+q.x;return wall[j]!=0u?i:j;
}
void main(){
    int i=int(gl_GlobalInvocationID.x);if(i>=int(p.side*p.side))return;
    if(wall[i]!=0u){velocity[i]=vec2(0);for(int q=0;q<9;q++)next_f[9*i+q]=f[9*i+q];return;}
    float east=c[neighbor(i,E[1])],south=c[neighbor(i,E[2])],west=c[neighbor(i,E[3])],north=c[neighbor(i,E[4])];
    vec2 grad=.5*vec2(east-west,south-north);
    float lap=east+west+north+south-4.*c[i];
    float beta=12.*p.sigma/p.width,kappa=1.5*p.sigma*p.width;
    float mu=2.*beta*c[i]*(1.-c[i])*(1.-2.*c[i])-kappa*lap;
    vec2 force=mu*grad+(p.load_factor*load[i]-c[i])*vec2(p.gx,p.gy);
    if((p.moving_boundary&2u)!=0u)force=interface_force[i]-c[i]*vec2(p.gx,p.gy);
    float pulled[9];float rho=0.;vec2 momentum=vec2(0);
    precise float wall_mass_source=0.;
    float local_rho=0.;
    if(p.moving_boundary!=0u)for(int q=0;q<9;q++)local_rho+=f[9*i+q];
    for(int q=0;q<9;q++){
        int j=neighbor(i,-E[q]);pulled[q]=(j==i&&q!=0)?f[9*i+O[q]]:f[9*j+q];
        if(p.moving_boundary!=0u && j==i && q!=0){
            ivec2 at=ivec2(i%int(p.side),i/int(p.side))-E[q];
            if(all(greaterThanEqual(at,ivec2(0)))&&all(lessThan(at,ivec2(p.side)))){
                int solid=at.y*int(p.side)+at.x;
                precise float before=pulled[q];
                precise float updated=before+6.*W[q]*local_rho*dot(vec2(E[q]),boundary_velocity[solid]);
                pulled[q]=updated;
                wall_mass_source+=updated-before;
            }
        }
        momentum+=pulled[q]*vec2(E[q]);
    }
    // Occupancy is fixed during this lattice step. Moving bounce-back must
    // exchange momentum without injecting mass into that fixed fluid volume.
    // The rest population has zero momentum; carry its subtraction roundoff.
    precise float old_rest=pulled[0];
    precise float corrected_rest=old_rest-wall_mass_source;
    precise float wall_mass_remainder=(old_rest-corrected_rest)-wall_mass_source;
    pulled[0]=corrected_rest;
    // Sum opposite populations together on input and output. Identical grouping
    // avoids a persistent rounding bias between the two mass evaluations.
    rho=pulled[0]+((pulled[1]+pulled[3])+(pulled[2]+pulled[4]))
        +((pulled[5]+pulled[7])+(pulled[6]+pulled[8]));
    vec2 u=(momentum+.5*force)/rho;velocity[i]=u;
    float post[9];
    for(int q=1;q<9;q++){
        vec2 e=vec2(E[q]);float eu=dot(e,u);
        float eq=W[q]*rho*(1.+3.*eu+4.5*eu*eu-1.5*dot(u,u));
        float source=W[q]*(1.-.5/p.tau)*dot(3.*(e-u)+9.*eu*e,force);
        float value=pulled[q]-(pulled[q]-eq)/p.tau+source;
        post[q]=value;
    }
    // Guo forcing changes the first moment by exactly force. Reconstruct two
    // cardinal populations from that target before closing mass. Independent
    // rounding of nine collision terms otherwise biases weak sustained forces.
    precise vec2 target_momentum=momentum+force;
    precise float diagonal_x=(post[5]-post[7])+(post[8]-post[6]);
    precise float diagonal_y=(post[5]-post[7])+(post[6]-post[8]);
    post[1]=post[3]+(target_momentum.x-diagonal_x);
    post[2]=post[4]+(target_momentum.y-diagonal_y);
    for(int q=1;q<9;q++)next_f[9*i+q]=post[q];
    // Guo forcing has zero mass moment. Balance collision increments rather than
    // subtracting two independently rounded O(1) densities. Near equilibrium,
    // each small difference is exact by Sterbenz's lemma; no global mass repair.
    precise float delta_mass=mass_residual[i]+wall_mass_remainder;
    for(int q=1;q<9;q++)delta_mass+=pulled[q]-post[q];
    precise float rest=pulled[0]+delta_mass;
    // Carry the lost low bits of the stationary population into the next step.
    // This residual travels with the full fluid packet when a voxel moves.
    precise float remainder=(pulled[0]-rest)+delta_mass;
    mass_residual[i]=remainder;
    next_f[9*i]=rest;
}
