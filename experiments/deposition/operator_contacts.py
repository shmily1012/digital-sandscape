"""Operator-split contact solve for the unchanged geometric drainage law.

Local Coulomb solve uses F - (H-D)v, then verifies full H force balance.
Convergence is not guaranteed for stiff drainage: bounded failure retains input.
"""
from dataclasses import dataclass
import math
from experiments.liquid.grain_coupling import forces
from experiments.deposition.contact_particles import advance_contacts,ContactConvergenceError
from experiments.deposition.matrix_free_drainage import MatrixFreeDrainage

@dataclass
class OperatorContactResult:
    contact: object
    outer_iterations: int
    pressure_solves: int
    force_residual: float


def advance_operator_contacts(grid,grains,gravity,dt,planes=(),friction=.5,
                              max_outer=64,force_tolerance=1e-11):
    if not isinstance(max_outer,int) or not 1<=max_outer<=256 or not math.isfinite(force_tolerance) or force_tolerance<=0:
        raise ValueError('Invalid operator contact budget')
    operator=MatrixFreeDrainage(grid,grains)
    base=[v for pair in forces(grains,gravity) for v in pair]
    velocity=[0.]*len(base);applied=[0.]*len(base)
    for iteration in range(max_outer):
        effective=[f-(h-d*v) for f,h,d,v in zip(base,applied,operator.drag,velocity)]
        result=advance_contacts(grains,gravity,dt,planes,friction,tolerance=1e-12,
                                external_forces=[effective[i:i+2] for i in range(0,len(base),2)])
        velocity=[v for pair in result.velocity for v in pair]
        applied=operator.apply(velocity)
        net=base.copy()
        for i,j,nx,ny,_,ln,lt in result.reactions:
            fx,fy=nx*ln-ny*lt,ny*ln+nx*lt
            net[2*i]+=fx;net[2*i+1]+=fy
            if j>=0:net[2*j]-=fx;net[2*j+1]-=fy
        error=max(abs(a-b) for a,b in zip(applied,net))
        if error<=force_tolerance:
            return OperatorContactResult(result,iteration+1,operator.pressure_solves,error)
    raise ContactConvergenceError('Operator contact budget exhausted; original state retained')
