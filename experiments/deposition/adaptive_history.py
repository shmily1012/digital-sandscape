"""Whole-interval transaction for particles, spring histories and liquid flux."""
from dataclasses import dataclass
import math
from experiments.deposition.operator_history import advance_operator_history
from experiments.deposition.contact_particles import ContactConvergenceError
from experiments.deposition.adaptive_drainage import DrainageBudgetError
from experiments.deposition.disk_volume import occupancy,swept_flux

@dataclass
class HistoryInterval:
    grains: list
    history: dict
    elapsed: float
    attempts: int
    accepted_steps: list
    integrated_liquid_flux: list
    max_flux_error: float
    volume_error: float
    energy_error: float
    work_into_springs: float
    dissipated: float


def advance_history_interval(grid,grains,ids,history,gravity,dt,planes=(),plane_ids=(),
                             stiffness=1.,friction=.5,flux_tolerance=.005,max_substeps=32,max_outer=64,trace=None):
    if not math.isfinite(dt) or dt<=0 or not math.isfinite(flux_tolerance) or flux_tolerance<=0:
        raise ValueError('Positive finite timestep and flux tolerance required')
    if type(max_substeps) is not int or not 1<=max_substeps<=64:raise ValueError('Invalid substep budget')
    current=list(grains);current_history=dict(history);initial=occupancy(grid,current)
    initial_energy=sum(.5*s.stiffness*s.elastic_slip**2 for s in history.values())
    integral=[0.]*len(grid.faces);pending=[dt];accepted=[];attempts=0
    maximum=work=dissipated=0.
    while pending:
        step=pending.pop();attempts+=1;rejected=False;reason="flux";error=None;worst=None
        try:
            answer=advance_operator_history(grid,current,ids,current_history,gravity,step,planes,plane_ids,
                                           stiffness,friction,max_outer=max_outer)
        except ContactConvergenceError:
            rejected=True;reason="contact"
        if not rejected:
            candidate=answer.candidate
            solid=swept_flux(grid,current,candidate.contact.grains,step)
            liquid=grid.project(solid).liquid
            differences=[abs(a-b) for a,b in zip(liquid,answer.liquid_flux)]
            worst=max(range(len(differences)),key=differences.__getitem__);error=differences[worst]
            rejected=error>flux_tolerance
        if trace is not None:
            trace.append(dict(attempt=attempts,time=sum(accepted),dt=step,accepted=not rejected,
                              reason=reason if rejected else 'accepted',flux_error=error,worst_face=worst,
                              positions=[[g.x,g.y] for g in current],
                              history_count=len(current_history),
                              reactions=[list(c) for c in candidate.contact.reactions] if reason!='contact' else None))
        if rejected:
            if len(accepted)+len(pending)+2>max_substeps:
                raise DrainageBudgetError(f'History interval budget exhausted; accepted={len(accepted)}, step={step}, pending={len(pending)}; all old state retained')
            pending.extend([step/2,step/2]);continue
        current=candidate.contact.grains;current_history=candidate.history
        integral=[a+step*b for a,b in zip(integral,liquid)]
        maximum=max(maximum,error);work+=candidate.work_into_springs;dissipated+=candidate.dissipated
        accepted.append(step)
    final=occupancy(grid,current)
    volume_error=max(abs((1-a)-d-(1-b)) for a,b,d in zip(initial,final,grid.divergence(integral)))
    final_energy=sum(.5*s.stiffness*s.elastic_slip**2 for s in current_history.values())
    energy_error=abs(work-(final_energy-initial_energy)-dissipated)
    if volume_error>1e-9 or energy_error>1e-9:raise ValueError('Joint history interval certificate failed')
    return HistoryInterval(current,current_history,sum(accepted),attempts,accepted,integral,maximum,volume_error,energy_error,work,dissipated)
