"""Independent implicit upwind gas-volume solve (Gauss-Seidel oracle)."""
import math


def transport_regions(graph,old,new_capacity,flux,dt=.1,tolerance=1e-12,max_iterations=512):
    """Implicit upwind gas volume on separate liquid regions.

    End capacities must already match the supplied local volume flux. This
    does not infer a moving-geometry correspondence or commit particle state.
    No concentration clipping or global inventory rescaling is performed.
    """
    count=len(graph['nodes']);capacity=[node['area'] for node in graph['nodes']]
    if not math.isfinite(dt) or dt<=0 or not math.isfinite(tolerance) or tolerance<=0 or not isinstance(max_iterations,int) or not 1<=max_iterations<=2048:
        raise ValueError('Invalid region transport budget')
    if len(old)!=count or len(new_capacity)!=count or len(flux)!=len(graph['edges']):
        raise ValueError('Region transport shape mismatch')
    if any(not math.isfinite(g) or not 0<=g<=v for g,v in zip(old,capacity)) or any(not math.isfinite(v) or v<0 for v in new_capacity) or any(not math.isfinite(q) for q in flux):
        raise ValueError('Invalid gas or capacity')
    incoming=[[] for _ in old];outgoing=[0.]*count;divergence=[0.]*count
    for (i,j,_),rate in zip(graph['edges'],flux):
        q=dt*rate;divergence[i]+=q;divergence[j]-=q
        donor,receiver=(i,j) if q>=0 else (j,i)
        outgoing[donor]+=abs(q);incoming[receiver].append((donor,abs(q)))
    volume_error=max((abs(b-a+d) for a,b,d in zip(capacity,new_capacity,divergence)),default=0.)
    if volume_error>tolerance:raise ValueError('Capacity and volume flux disagree')
    concentration=[g/v if v>0 else 0. for g,v in zip(old,capacity)]
    gas_residual=math.inf
    for iteration in range(max_iterations):
        for i in (range(count) if iteration%2==0 else range(count-1,-1,-1)):
            denominator=capacity[i]+math.fsum(q for _,q in incoming[i])
            concentration[i]=(old[i]+math.fsum(q*concentration[j] for j,q in incoming[i]))/denominator if denominator else 0.
        gas_residual=max((abs((new_capacity[i]+outgoing[i])*concentration[i]-old[i]-math.fsum(q*concentration[j] for j,q in incoming[i])) for i in range(count)),default=0.)
        if gas_residual<=tolerance:break
    else:raise RuntimeError('Region gas transport budget exhausted')
    gas=[c*v for c,v in zip(concentration,new_capacity)]
    if any(not math.isfinite(g) or g<0 or g>v*(1+1e-14) for g,v in zip(gas,new_capacity)):
        raise RuntimeError('Region gas bounds violated')
    # Check each disconnected inventory, not just a cancelling global sum.
    drift=[]
    for label in range(graph['components']):
        ids=[i for i,c in enumerate(graph['labels']) if c==label]
        delta=math.fsum(gas[i]-old[i] for i in ids)
        if abs(delta)>max(1e-12,len(ids)*tolerance):raise RuntimeError('Region gas inventory drift')
        drift.append(delta)
    return dict(gas=gas,iterations=iteration+1,gas_residual=gas_residual,
                volume_residual=volume_error,component_inventory_drift=drift)


def transport(old, capacities, flux, side, dt=1., tolerance=1e-12):
    count=side*side
    if any(min(v[:2]) < -1e-12 for v in capacities):
        raise ValueError('Negative fluid capacity')
    # Analytic rectangle subtraction can leave a negative double-roundoff tail.
    # Reject actual overlap; do not renormalize any positive capacity.
    capacities=[[max(0.,v[0]),max(0.,v[1]),*v[2:]] for v in capacities]
    if len(old)!=count or any(g<0 or g>capacities[i][0] for i,g in enumerate(old)):
        raise ValueError('Gas exceeds old fluid capacity')
    incoming=[[] for _ in old];outgoing=[0.]*count
    for i in range(count):
        for axis, j, allowed in ((0,i+1,i%side+1<side),(1,i+side,i+side<count)):
            if not allowed:continue
            q=flux[i][axis]*dt
            donor,receiver=(i,j) if q>=0 else (j,i)
            outgoing[donor]+=abs(q);incoming[receiver].append((donor,abs(q)))
    c=[g/capacities[i][0] if capacities[i][0]>0 else 0. for i,g in enumerate(old)]
    for iteration in range(512):
        for i in (range(count) if iteration%2==0 else range(count-1,-1,-1)):
            diagonal=capacities[i][1]+outgoing[i]
            c[i]=(old[i]+math.fsum(q*c[j] for j,q in incoming[i]))/diagonal if diagonal>0 else 0.
        residual=max(abs((capacities[i][1]+outgoing[i])*c[i]-old[i]-math.fsum(q*c[j] for j,q in incoming[i])) for i in range(count))
        if residual<=tolerance:return [c[i]*capacities[i][1] for i in range(count)]
    raise RuntimeError('Gas-volume oracle did not converge')


def profiles(case):
    n=case['side'];volume=case['expected'];q=case['fluid_flux'];result=[]
    for name in ('water','gas','interface'):
        fraction=[0. if name=='water' else 1. if name=='gas' else
                  .5*(1+math.tanh((i//n-n*.55)/1.5)) for i in range(n*n)]
        old=[max(0.,v[0])*c for v,c in zip(volume,fraction)]
        result.append(dict(name=name,fraction=fraction,expected=transport(old,volume,q,n)))
    return result
