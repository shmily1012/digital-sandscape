"""Overdamped translational contact experiment, with effective Coulomb friction.

No particle spin, lubrication, gas interface or resolved carrier feedback.
Contact reactions are forces (not inertial impulses). This is not a full DEM.
"""
from dataclasses import dataclass, replace
import math
from experiments.liquid.grain_coupling import forces

@dataclass(frozen=True)
class Plane:
    nx: float
    ny: float
    offset: float  # allowed centers satisfy n dot x >= offset + radius

@dataclass
class ContactResult:
    grains: list
    velocity: list
    reactions: list
    iterations: int
    residual: float
    friction_power: float

class ContactConvergenceError(ValueError):
    """Only nonlinear solve failures are eligible for timestep subdivision."""


@dataclass
class ContactInterval:
    result: ContactResult
    substeps: int
    attempts: int
    elapsed: float
    maximum_residual: float


def advance_interval(grains, gravity, dt, planes=(), friction=.5,
                     max_substeps=8, max_iterations=2000, tolerance=1e-9):
    """Transactionally integrate one requested interval with bounded bisection.

    A failed parent is replaced by two halves. No partially advanced state is
    returned if the subdivision limit is exhausted. At most 2*limit-1 solves.
    """
    if not isinstance(max_substeps,int) or max_substeps<1 or max_substeps>64:
        raise ValueError('Invalid subdivision budget')
    if not math.isfinite(dt) or dt<=0:
        raise ValueError('Positive finite dt required')
    current=list(grains)
    pending=[dt]
    substeps=attempts=0
    residual=0.
    elapsed=0.
    while pending:
        step=pending.pop()
        attempts+=1
        try:
            result=advance_contacts(current,gravity,step,planes,friction,max_iterations,tolerance)
        except ContactConvergenceError:
            if substeps+len(pending)+2>max_substeps:
                raise ContactConvergenceError('Subdivision budget exhausted; complete interval retained')
            pending.extend([step/2,step/2])
            continue
        current=result.grains
        residual=max(residual,result.residual)
        substeps+=1
        elapsed+=step
    return ContactInterval(result,substeps,attempts,elapsed,residual)


def advance_contacts(grains, gravity, dt, planes=(), friction=.5, max_iterations=2000, tolerance=1e-9, relaxation=1.0, mobility_matrix=None, external_forces=None, tangential_compliance=None):
    if not math.isfinite(dt) or dt<=0 or not math.isfinite(friction) or friction<0:
        raise ValueError('Invalid contact timestep or friction')
    if max_iterations<1 or not math.isfinite(tolerance) or tolerance<=0:
        raise ValueError('Invalid contact convergence budget')
    if not math.isfinite(relaxation) or not 0<relaxation<=1:
        raise ValueError('Relaxation must be in (0,1]')
    for g in grains:
        if not all(math.isfinite(v) for v in (g.x,g.y,g.radius,g.drag,g.density)) or min(g.radius,g.drag,g.density)<=0:
            raise ValueError('Invalid grain')
    for p in planes:
        if not all(math.isfinite(v) for v in (p.nx,p.ny,p.offset)) or abs(math.hypot(p.nx,p.ny)-1)>1e-10:
            raise ValueError('Plane requires a finite unit normal')
    force=forces(grains,gravity)
    if external_forces is not None:
        if len(external_forces)!=len(grains) or any(len(f)!=2 or any(not math.isfinite(v) for v in f) for f in external_forces):
            raise ValueError("Invalid explicit particle forces")
        force=[tuple(f) for f in external_forces]
    velocity=[[f[0]/g.drag,f[1]/g.drag] for g,f in zip(grains,force)]
    if mobility_matrix is not None:
        size=2*len(grains)
        if len(mobility_matrix)!=size or any(len(row)!=size for row in mobility_matrix):
            raise ValueError('Mobility matrix shape mismatch')
        lower=[[0.]*size for _ in range(size)]
        for i in range(size):
            for j in range(i+1):
                a,b=mobility_matrix[i][j],mobility_matrix[j][i]
                if not math.isfinite(a) or not math.isfinite(b) or abs(a-b)>1e-8:
                    raise ValueError('Mobility must be finite and reciprocal')
                value=(a+b)*.5-sum(lower[i][k]*lower[j][k] for k in range(j))
                if i==j:
                    if value<=1e-10:raise ValueError('Mobility must be positive definite')
                    lower[i][j]=math.sqrt(value)
                else:lower[i][j]=value/lower[j][j]
        flat=[v for f in force for v in f]
        v=[sum(a*b for a,b in zip(row,flat)) for row in mobility_matrix]
        velocity=[v[i:i+2] for i in range(0,size,2)]
    contacts=[]
    for i,g in enumerate(grains):
        for j in range(i):
            other=grains[j]
            dx,dy=g.x-other.x,g.y-other.y
            distance=math.hypot(dx,dy)
            gap=distance-g.radius-other.radius
            if gap < -tolerance or distance<=0: raise ValueError('Initial overlap requires separate recovery')
            contacts.append([i,j,dx/distance,dy/distance,gap,0.,0.])
        for p in planes:
            gap=p.nx*g.x+p.ny*g.y-p.offset-g.radius
            if gap < -tolerance: raise ValueError('Initial wall overlap')
            contacts.append([i,-1,p.nx,p.ny,gap,0.,0.])

    springs=[(0.,0.)]*len(contacts)
    if tangential_compliance is not None:
        if len(tangential_compliance)!=len(contacts):raise ValueError('Spring/contact count mismatch')
        springs=[]
        for old,k in tangential_compliance:
            if not math.isfinite(old) or not math.isfinite(k) or k<=0:raise ValueError('Invalid contact spring')
            springs.append((old/dt,1/(k*dt)))

    def relative(c):
        i,j,nx,ny,_,_,_=c
        vx,vy=velocity[i]
        if j>=0: vx,vy=vx-velocity[j][0],vy-velocity[j][1]
        return vx*nx+vy*ny,-vx*ny+vy*nx

    def apply(c,delta_n,delta_t):
        i,j,nx,ny,_,_,_=c
        fx,fy=nx*delta_n-ny*delta_t,ny*delta_n+nx*delta_t
        if mobility_matrix is not None:
            for k in range(len(grains)):
                for a in range(2):
                    row=mobility_matrix[2*k+a]
                    velocity[k][a]+=row[2*i]*fx+row[2*i+1]*fy
                    if j>=0:velocity[k][a]-=row[2*j]*fx+row[2*j+1]*fy
            return
        velocity[i][0]+=fx/grains[i].drag
        velocity[i][1]+=fy/grains[i].drag
        if j>=0:
            velocity[j][0]-=fx/grains[j].drag
            velocity[j][1]-=fy/grains[j].drag

    def contact_mobility(c):
        i,j,nx,ny,_,_,_=c
        if mobility_matrix is None:
            value=1/grains[i].drag+(1/grains[j].drag if j>=0 else 0)
            return value,value
        values=[]
        for dx,dy in ((nx,ny),(-ny,nx)):
            direction=[0.]*(2*len(grains))
            direction[2*i:2*i+2]=[dx,dy]
            if j>=0:direction[2*j:2*j+2]=[-dx,-dy]
            values.append(sum(x*sum(a*b for a,b in zip(row,direction)) for x,row in zip(direction,mobility_matrix)))
        return values

    mobilities=[contact_mobility(c) for c in contacts]
    residual=math.inf
    for iteration in range(max_iterations):
        for c,(mobility,tangent_mobility),(history_rate,compliance) in zip(contacts,mobilities,springs):
            i,j,_,_,gap,ln,lt=c
            un,_=relative(c)
            next_n=ln+relaxation*(max(0,ln-(un+gap/dt)/mobility)-ln)
            apply(c,next_n-ln,0)
            _,ut=relative(c)
            # Friction acts only when this step's unilateral reaction is active.
            bound=friction*next_n
            next_t=lt+relaxation*(min(bound,max(-bound,lt-(ut+history_rate+compliance*lt)/(tangent_mobility+compliance)))-lt)
            apply(c,0,next_t-lt)
            c[5],c[6]=next_n,next_t
        residual=0.
        for c,(mobility,tangent_mobility),(history_rate,compliance) in zip(contacts,mobilities,springs):
            i,j,_,_,gap,ln,lt=c
            un,ut=relative(c)
            projected_n=max(0,ln-(un+gap/dt)/mobility)
            projected_t=min(friction*ln,max(-friction*ln,lt-(ut+history_rate+compliance*lt)/(tangent_mobility+compliance)))
            residual=max(residual,mobility*abs(projected_n-ln),tangent_mobility*abs(projected_t-lt))
        if residual<=tolerance: break
    else:
        error=ContactConvergenceError(f'Contact iteration budget exhausted; residual={residual:.9g}; original state retained')
        error.contacts=[tuple(c) for c in contacts]
        error.velocity=[list(v) for v in velocity]
        error.residual=residual
        raise error
    candidate=[replace(g,x=g.x+dt*v[0],y=g.y+dt*v[1]) for g,v in zip(grains,velocity)]
    for i,g in enumerate(candidate):
        if not math.isfinite(g.x+g.y): raise ValueError('Nonfinite contact candidate')
        for other in candidate[:i]:
            if math.hypot(g.x-other.x,g.y-other.y)<g.radius+other.radius-2*dt*tolerance:
                raise ValueError('Contact candidate overlaps')
        for p in planes:
            if p.nx*g.x+p.ny*g.y<p.offset+g.radius-2*dt*tolerance:
                raise ValueError('Contact candidate crosses wall')
    power=sum(c[6]*relative(c)[1] for c in contacts)
    return ContactResult(candidate,velocity,[tuple(c) for c in contacts],iteration+1,residual,power)


def circular_planes(sides=64,radius=.46,center=(.5,.5)):
    """Inscribed polygon: conservative circular enclosure, not a smooth wall."""
    if sides<8 or radius<=0: raise ValueError('Invalid polygon')
    apothem=radius*math.cos(math.pi/sides)
    result=[]
    for i in range(sides):
        a=2*math.pi*i/sides
        nx,ny=math.cos(a),math.sin(a)
        result.append(Plane(nx,ny,nx*center[0]+ny*center[1]-apothem))
    return result
