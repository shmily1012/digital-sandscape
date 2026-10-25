"""Bounded, transactional explicit drainage with geometric flux error control.

The error is the max face-flux difference, not a rigorous trajectory bound.
No time is advanced or partial state returned on budget exhaustion.
"""
from dataclasses import dataclass
import math
from experiments.deposition.drainage_resistance import DrainageResistance
from experiments.deposition.disk_volume import swept_flux,occupancy
from experiments.deposition.contact_particles import advance_contacts,ContactConvergenceError


class DrainageBudgetError(ValueError):
    pass


@dataclass
class DrainageInterval:
    grains: list
    elapsed: float
    substeps: int
    attempts: int
    maximum_flux_error: float
    integrated_liquid_flux: list
    volume_residual: float
    resistance_builds: int


def advance_drainage(grid,grains,gravity,dt,planes=(),friction=.5,
                     flux_tolerance=.005,max_substeps=16):
    if not math.isfinite(dt) or dt<=0 or not math.isfinite(flux_tolerance) or flux_tolerance<=0:
        raise ValueError('Positive finite timestep and flux tolerance required')
    if not isinstance(max_substeps,int) or not 1<=max_substeps<=64:
        raise ValueError('Invalid substep budget')
    current=list(grains);initial=occupancy(grid,current)
    pending=[dt];attempts=steps=0;elapsed=maximum=0.
    integral=[0.]*len(grid.faces)
    model=None;builds=0
    while pending:
        step=pending.pop();attempts+=1
        if model is None:
            model=DrainageResistance(grid,current,geometric=True);builds+=1
        rejected=False
        try:
            result=advance_contacts(current,gravity,step,planes,friction,
                                    tolerance=1e-12,mobility_matrix=model.mobility)
        except ContactConvergenceError:
            rejected=True
        if not rejected:
            solid=swept_flux(grid,current,result.grains,step)
            liquid=grid.project(solid).liquid
            _,frozen=model.flux([v for pair in result.velocity for v in pair])
            error=max(abs(a-b) for a,b in zip(liquid,frozen))
            rejected=error>flux_tolerance
        if rejected:
            if steps+len(pending)+2>max_substeps:
                raise DrainageBudgetError('Drainage substep budget exhausted; entire interval retained')
            pending.extend([step/2,step/2]);continue
        integral=[a+step*b for a,b in zip(integral,liquid)]
        maximum=max(maximum,error);elapsed+=step;steps+=1;current=result.grains
        model=None  # Accepted geometry changed; rejected retries reuse the same operator.
    final=occupancy(grid,current)
    residual=max(abs((1-a)-d-(1-b)) for a,b,d in zip(initial,final,grid.divergence(integral)))
    if residual>1e-9:raise ValueError('Integrated liquid volume balance failed')
    return DrainageInterval(current,elapsed,steps,attempts,maximum,integral,residual,builds)
