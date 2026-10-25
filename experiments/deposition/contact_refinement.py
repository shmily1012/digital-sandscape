"""Bounded semismooth contact refinement oracle using project-local NumPy.

Solves the same normal and tangential projection equations as the PGS model.
No particle position is changed until all contact equations pass validation.
"""
import math,sys
from pathlib import Path
from dataclasses import replace
from experiments.liquid.grain_coupling import forces
from experiments.deposition.contact_particles import ContactResult,ContactConvergenceError


def refine(grains,contacts,gravity,dt,friction=.5,max_iterations=32,tolerance=1e-9,precision="float64",trace=None):
    sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'.tools/plot-libs'))
    import numpy as np
    if precision not in ('float32','float64'):raise ValueError('Unsupported reference precision')
    dtype=np.dtype(precision)
    rcond=1e-6 if precision=='float32' else 1e-12
    n=len(grains);count=len(contacts)
    if dt<=0 or not math.isfinite(dt) or max_iterations<1:raise ValueError('Invalid refinement bounds')
    j=np.zeros((2*count,2*n),dtype=dtype);gap=np.zeros(2*count,dtype=dtype)
    lam=np.array([c[5:7] for c in contacts],dtype=dtype).reshape(-1)
    for k,(i,other,nx,ny,distance,_,_) in enumerate(contacts):
        j[2*k,2*i:2*i+2]=(nx,ny);j[2*k+1,2*i:2*i+2]=(-ny,nx)
        if other>=0:
            j[2*k,2*other:2*other+2]=(-nx,-ny)
            j[2*k+1,2*other:2*other+2]=(ny,-nx)
        gap[2*k]=distance/dt
    mobility=np.repeat(np.asarray([1/g.drag for g in grains],dtype=dtype),2)
    free=np.asarray(forces(grains,gravity),dtype=dtype).reshape(-1)*mobility
    diagonal=(j*j)@mobility
    def evaluate(value):
        velocity=free+mobility*(j.T@value)
        speed=j@velocity+gap
        projected=value-speed/diagonal
        projected[0::2]=np.maximum(0,projected[0::2])
        bound=friction*np.maximum(0,value[0::2])
        projected[1::2]=np.clip(projected[1::2],-bound,bound)
        return (value-projected)*diagonal,velocity,speed
    history=[]
    for iteration in range(max_iterations):
        f,velocity,speed=evaluate(lam)
        residual=float(np.max(np.abs(f),initial=0))
        history.append(residual)
        if residual<=tolerance:break
        selected=np.flatnonzero((lam[0::2]>1e-14)|(speed[0::2]<-tolerance))
        # Include tangential residuals even when a normal force is near zero.
        selected=np.union1d(selected,np.flatnonzero(np.abs(f[1::2])>tolerance))
        indices=np.column_stack((2*selected,2*selected+1)).reshape(-1)
        if not len(indices):raise ContactConvergenceError('No active refinement direction')
        rows=j[indices];a=(rows*mobility)@rows.T
        jac=np.zeros_like(a)
        for local,k in enumerate(selected):
            normal,tangent=2*local,2*local+1
            if lam[2*k]-speed[2*k]/diagonal[2*k]>0:jac[normal]=a[normal]
            else:jac[normal,normal]=diagonal[2*k]
            z=lam[2*k+1]-speed[2*k+1]/diagonal[2*k+1]
            bound=friction*max(0,lam[2*k])
            if -bound<z<bound:jac[tangent]=a[tangent]
            else:
                jac[tangent,tangent]=diagonal[2*k+1]
                jac[tangent,normal]=(-friction if z>=bound else friction)*diagonal[2*k+1]
        if trace is not None:
            values=np.linalg.svd(jac,compute_uv=False)
            trace.append(dict(iteration=iteration+1,active_contacts=len(selected),selected_contacts=selected.tolist(),matrix_size=len(indices),rank=int(np.sum(values>max(float(values[0]),1.)*rcond)),singular_values=values.tolist(),matrix=jac.tolist(),rhs=(-f[indices]).tolist()))
        direction=np.linalg.lstsq(jac,-f[indices],rcond=rcond)[0]
        merit=float(np.dot(f,f));accepted=False
        for trial in range(20):
            candidate=lam.copy();candidate[indices]+=direction*(.5**trial)
            next_f,_,_=evaluate(candidate)
            if float(np.dot(next_f,next_f))<merit*(1-1e-4*(.5**trial)):
                lam=candidate;accepted=True;break
        if not accepted:
            # Redundant sticking constraints can have inconsistent velocity
            # corrections while their reaction forces remain indeterminate.
            # Follow a Jacobian null direction to a friction-cone boundary;
            # the next Newton iteration can then release that active constraint.
            _,singular,vh=np.linalg.svd(jac,full_matrices=True)
            cutoff=max(float(singular[0]),1.0)*rcond
            rank=int(np.sum(singular>cutoff))
            choices=[]
            for basis in vh[rank:]:
                for sign in (-1,1):
                    direction=basis*sign
                    limits=[]
                    for local,k in enumerate(selected):
                        ln,lt=lam[2*k:2*k+2];dn,dtan=direction[2*local:2*local+2]
                        for margin,slope in ((ln,dn),(friction*ln-lt,friction*dn-dtan),(friction*ln+lt,friction*dn+dtan)):
                            if slope < -1e-8 and margin>1e-12:limits.append(margin/-slope)
                    if not limits:continue
                    distance=min(limits)
                    candidate=lam.copy();candidate[indices]+=direction*distance
                    if np.min(candidate[0::2],initial=0)<-1e-10 or np.max(np.abs(candidate[1::2])-friction*candidate[0::2],initial=0)>1e-10:continue
                    next_f,_,_=evaluate(candidate);next_merit=float(np.dot(next_f,next_f))
                    if next_merit<=merit*(1+1e-5):choices.append((next_merit,float(np.dot(candidate,candidate)),candidate))
            if choices:
                choices.sort(key=lambda x:(x[0],x[1]))
                lam=choices[0][2]
                continue
            error=ContactConvergenceError(f'Refinement line search stalled at {residual:.9g}')
            error.history=history
            raise error
    else:
        error=ContactConvergenceError(f'Refinement budget exhausted at {residual:.9g}')
        error.history=history
        raise error
    positions=[replace(g,x=g.x+dt*velocity[2*i],y=g.y+dt*velocity[2*i+1]) for i,g in enumerate(grains)]
    # All-contact normal constraints imply pair separation and plane containment.
    if not np.all(np.isfinite(velocity)) or np.min(speed[0::2],initial=0)<-2*tolerance:
        raise ContactConvergenceError('Refinement violates contact feasibility')
    result_contacts=[tuple(c[:5])+tuple(lam[2*k:2*k+2]) for k,c in enumerate(contacts)]
    result=ContactResult(positions,velocity.reshape(-1,2).tolist(),result_contacts,iteration+1,residual,float(np.dot(lam[1::2],speed[1::2])))
    return result,history
