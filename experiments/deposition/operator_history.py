"""Matrix-free drainage plus immutable old tangential history during iteration."""
from dataclasses import dataclass
import math
from experiments.liquid.grain_coupling import forces
from experiments.deposition.history_contacts import advance_history_contacts
from experiments.deposition.contact_particles import ContactConvergenceError
from experiments.deposition.matrix_free_drainage import MatrixFreeDrainage

@dataclass
class OperatorHistoryResult:
    candidate: object
    iterations: int
    pressure_solves: int
    force_residual: float
    liquid_flux: list


def advance_operator_history(grid,grains,ids,history,gravity,dt,planes=(),plane_ids=(),
                             stiffness=1.,friction=.5,max_outer=64,force_tolerance=1e-11):
    if not isinstance(max_outer,int) or not 1<=max_outer<=256 or not math.isfinite(force_tolerance) or force_tolerance<=0:
        raise ValueError('Invalid history operator budget')
    operator=MatrixFreeDrainage(grid,grains)
    base=[v for pair in forces(grains,gravity) for v in pair]
    velocity=[0.]*len(base);applied=[0.]*len(base)
    for iteration in range(max_outer):
        effective=[f-(h-d*v) for f,h,d,v in zip(base,applied,operator.drag,velocity)]
        # Every iteration reads the same previous physical state, never its candidate.
        candidate=advance_history_contacts(grains,ids,history,gravity,dt,planes,plane_ids,
                     stiffness,friction,external_forces=[effective[i:i+2] for i in range(0,len(base),2)])
        velocity=[v for pair in candidate.contact.velocity for v in pair]
        applied=operator.apply(velocity);net=base.copy()
        for i,j,nx,ny,_,ln,lt in candidate.contact.reactions:
            fx,fy=nx*ln-ny*lt,ny*ln+nx*lt
            net[2*i]+=fx;net[2*i+1]+=fy
            if j>=0:net[2*j]-=fx;net[2*j+1]-=fy
        error=max(abs(a-b) for a,b in zip(applied,net))
        if error<=force_tolerance:return OperatorHistoryResult(candidate,iteration+1,operator.pressure_solves,error,list(operator.last_liquid))
    raise ContactConvergenceError('History operator budget exhausted; particle and history retained')
