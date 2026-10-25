"""CPU oracle for contact forces coupled through reciprocal carrier mobility.

Regularized point-force Darcy carrier with self correction. No excluded solid
volume, lubrication, spin or gas interface; not a dense suspension model.
"""
from dataclasses import dataclass
import math
from experiments.deposition.contact_particles import advance_contacts, circular_planes
from experiments.liquid.grain_coupling import calibrate_self_response, face_weights, forces, sample

@dataclass
class CoupledContactResult:
    contact: object
    projection: object
    net_forces: list
    carrier_velocity: list
    mobility_error: float
    spread_force_error: float
    reciprocal_work_error: float

def advance_coupled(grid, grains, gravity, dt, planes=None, friction=.5, max_iterations=2000):
    if not math.isfinite(dt) or dt<=0:raise ValueError('Positive finite timestep required')
    if planes is None:planes=circular_planes(32)
    blocks,mobility=calibrate_self_response(grid,grains)
    result=advance_contacts(grains,gravity,dt,planes,friction,max_iterations,mobility_matrix=mobility)
    net=[list(f) for f in forces(grains,gravity)]
    for i,j,nx,ny,_,ln,lt in result.reactions:
        f=(nx*ln-ny*lt,ny*ln+nx*lt)
        for a in (0,1):
            net[i][a]+=f[a]
            if j>=0:net[j][a]-=f[a]
    # The load transmitted to the carrier includes the contact reaction.
    # A fully supported resting grain must not keep driving a gravity-only flow.
    weights=[face_weights(grid,g) for g in grains]
    source=[m*sum(w[k]*f[a] for w,f in zip(weights,net))/grid.h**2 for k,(_,_,m,a) in enumerate(grid.faces)]
    scale=max(map(abs,source),default=0.)
    projection=grid.project([v/scale for v in source]) if scale else grid.project(source)
    # Keep the pressure/flux object in physical scale, not normalized RHS units.
    if scale:
        from dataclasses import replace
        projection=replace(projection,mixture=[u*scale for u in projection.mixture],pressure=[p*scale for p in projection.pressure],liquid=[u*scale for u in projection.liquid],residual=projection.residual*scale)
    carrier=sample(grid,weights,projection.mixture)
    error=0.
    for g,u,f,k,v in zip(grains,carrier,net,blocks,result.velocity):
        corrected=(u[0]-k[0]*f[0]-k[1]*f[1]+f[0]/g.drag,u[1]-k[2]*f[0]-k[3]*f[1]+f[1]/g.drag)
        error=max(error,math.dist(corrected,v))
    spread_error=max(abs(sum(q*grid.h**2/m for q,(_,_,m,a) in zip(source,grid.faces) if a==axis)-sum(f[axis] for f in net)) for axis in (0,1))
    particle_work=sum(sum(f[a]*u[a] for a in (0,1)) for f,u in zip(net,carrier))
    face_work=sum(q*u*grid.h**2/m for q,u,(_,_,m,_) in zip(source,projection.mixture,grid.faces))
    return CoupledContactResult(result,projection,net,carrier,error,spread_error,abs(particle_work-face_work))
