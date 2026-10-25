"""Dilute overdamped grains coupled to a sealed Darcy carrier, dimensionless.

Force spreading and velocity sampling use identical normalized face weights,
so discrete particle/carrier work is reciprocal. No solid exclusion, packing,
gas contact or dense-bed friction is supplied by this dilute model.
"""
from dataclasses import dataclass,replace
import math

@dataclass(frozen=True)
class Grain:
    x: float
    y: float
    radius: float
    drag: float
    density: float
    material: int

def face_weights(grid,grain):
    if not all(math.isfinite(v) for v in (grain.x,grain.y,grain.radius,grain.drag,grain.density)) or min(grain.radius,grain.drag,grain.density)<=0:
        raise ValueError('Finite positive grain properties required')
    weights=[]
    normal=[0.0,0.0]
    for i,j,m,axis in grid.faces:
        x=((i%grid.size+j%grid.size)*0.5+0.5)*grid.h
        y=((i//grid.size+j//grid.size)*0.5+0.5)*grid.h
        w=max(0,1-abs(x-grain.x)/(2*grid.h))*max(0,1-abs(y-grain.y)/(2*grid.h))
        weights.append(w)
        normal[axis]+=w
    if min(normal)<=0:raise ValueError('Grain has no carrier support')
    return [w/normal[axis] for w,(_,_,_,axis) in zip(weights,grid.faces)]

def forces(grains,gravity):
    if len(gravity)!=2 or any(not math.isfinite(v) for v in gravity):raise ValueError('Finite gravity required')
    return [tuple((g.density-1)*math.pi*g.radius**2*v for v in gravity) for g in grains]

def spread(grid,grains,gravity):
    weights=[face_weights(grid,g) for g in grains]
    force=forces(grains,gravity)
    source=[m*sum(w[f]*v[axis] for w,v in zip(weights,force))/grid.h**2 for f,(_,_,m,axis) in enumerate(grid.faces)]
    return source,weights,force

def sample(grid,weights,velocity):
    return [tuple(sum(w*u for w,u,(_,_,_,axis) in zip(row,velocity,grid.faces) if axis==a) for a in range(2)) for row in weights]

def carrier_response(grid,grains):
    """Raw reciprocal carrier response, without particle self-block replacement."""
    weights=[face_weights(grid,g) for g in grains]
    count=2*len(grains)
    response=[[0.0]*count for _ in range(count)]
    for j,row in enumerate(weights):
        for axis in range(2):
            source=[m*w/grid.h**2 if a==axis else 0.0 for w,(_,_,m,a) in zip(row,grid.faces)]
            # Normalize unit-force RHS before solving; grid refinement otherwise
            # magnifies its absolute residual despite identical relative accuracy.
            scale=max(map(abs,source),default=0.0)
            velocity=[u*scale for u in grid.project([q/scale for q in source]).mixture] if scale else [0.0]*len(source)
            sampled=sample(grid,weights,velocity)
            for i,u in enumerate(sampled):
                for a in range(2):response[2*i+a][2*j+axis]=u[a]
    return response


def calibrate_self_response(grid,grains):
    """Exact reference calibration; reject a non-positive corrected mobility."""
    response=carrier_response(grid,grains)
    count=2*len(grains)
    corrected=[list(row) for row in response]
    blocks=[]
    for i,g in enumerate(grains):
        blocks.append([response[2*i+a][2*i+b] for a in range(2) for b in range(2)])
        for a in range(2):
            for b in range(2):corrected[2*i+a][2*i+b]=1/g.drag if a==b else 0.0
    # Cholesky certifies nonnegative work for any force, not just gravity.
    lower=[[0.0]*count for _ in range(count)]
    for i in range(count):
        for j in range(i+1):
            if abs(corrected[i][j]-corrected[j][i])>1e-7:
                raise ValueError('Carrier transfer lost reciprocal symmetry')
            value=(corrected[i][j]+corrected[j][i])*0.5-sum(lower[i][k]*lower[j][k] for k in range(j))
            if i==j:
                if value<=1e-10:raise ValueError('Corrected mobility is not positive definite; dilute model invalid')
                lower[i][j]=math.sqrt(value)
            else:lower[i][j]=value/lower[j][j]
    return blocks,corrected

def advance(grid,grains,gravity,dt):
    if not math.isfinite(dt) or dt<=0:raise ValueError('Positive finite dt required')
    source,weights,force=spread(grid,grains,gravity)
    projection=grid.project(source)
    carrier=sample(grid,weights,projection.mixture)
    blocks,_=calibrate_self_response(grid,grains)
    candidate=[]
    for g,u,f,k in zip(grains,carrier,force,blocks):
        x=g.x+dt*(u[0]-k[0]*f[0]-k[1]*f[1]+f[0]/g.drag)
        y=g.y+dt*(u[1]-k[2]*f[0]-k[3]*f[1]+f[1]/g.drag)
        if math.hypot(x-0.5,y-0.5)+g.radius>0.46:
            raise ValueError('Candidate hits sealed wall; contact model required')
        candidate.append(replace(g,x=x,y=y))
    return candidate,projection,carrier
