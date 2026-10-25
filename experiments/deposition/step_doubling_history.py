"""Step-doubling candidate controller; empirical state error, not a strict bound."""
from dataclasses import dataclass
import math
from collections import OrderedDict
from experiments.deposition.operator_history import advance_operator_history
from experiments.deposition.contact_particles import ContactConvergenceError
from experiments.deposition.adaptive_drainage import DrainageBudgetError
from experiments.deposition.disk_volume import occupancy,swept_flux

@dataclass
class DoubledInterval:
    grains: list
    history: dict
    elapsed: float
    accepted_steps: list
    attempts: int
    solver_calls: int
    position_estimate_sum: float
    history_estimate_sum: float
    volume_error: float
    energy_error: float
    integrated_liquid_flux: list
    cache_hits: int
    cache_peak: int


def state_difference(a,b):
    position=max(abs(x-y) for ga,gb in zip(a.contact.grains,b.contact.grains) for x,y in ((ga.x,gb.x),(ga.y,gb.y)))
    keys=set(a.history)|set(b.history)
    history=max((abs((a.history[k].elastic_slip if k in a.history else 0.)-(b.history[k].elastic_slip if k in b.history else 0.)) for k in keys),default=0.)
    return position,history


def advance_doubled(grid,grains,ids,history,gravity,dt,planes=(),plane_ids=(),stiffness=1.,friction=.5,
                    position_tolerance=1e-5,history_tolerance=1e-5,max_leaves=32,max_outer=64,reuse=True):
    if any(not math.isfinite(x) or x<=0 for x in (dt,position_tolerance,history_tolerance)):
        raise ValueError('Positive finite time and state tolerances required')
    if type(max_leaves) is not int or not 1<=max_leaves<=32:raise ValueError('Invalid leaf budget')
    current=list(grains);old_history=dict(history);initial=occupancy(grid,current)
    initial_energy=sum(.5*s.stiffness*s.elastic_slip**2 for s in history.values())
    pending=[dt];accepted=[];leaves=attempts=calls=0;pos_sum=hist_sum=work=dissipated=0.
    integral=[0.]*len(grid.faces)
    cache=OrderedDict();hits=peak=0
    def solve(g,h,step):
        nonlocal calls,hits,peak
        # Parameters/grid are fixed for this invocation. Include full dynamic state;
        # two states at the same nominal time are not interchangeable.
        key=(tuple(g),tuple(sorted(h.items())),step)
        if reuse and key in cache:
            hits+=1;cache.move_to_end(key)
            return cache[key]
        calls+=1
        result=advance_operator_history(grid,g,ids,h,gravity,step,planes,plane_ids,stiffness,friction,max_outer=max_outer).candidate
        if reuse:
            cache[key]=result
            if len(cache)>8:cache.popitem(last=False)
            peak=max(peak,len(cache))
        return result
    while pending:
        step=pending.pop();attempts+=1;reject=False
        try:
            coarse=solve(current,old_history,step)
            half=solve(current,old_history,step/2)
            fine=solve(half.contact.grains,half.history,step/2)
            ep,eh=state_difference(coarse,fine)
            # Allocate a per-interval sum budget, without claiming a rigorous global bound.
            reject=ep>position_tolerance*step/dt or eh>history_tolerance*step/dt
        except ContactConvergenceError:reject=True
        if reject:
            if leaves+len(pending)+2>max_leaves:
                failure=DrainageBudgetError('Step-doubling budget exhausted; entire old state retained')
                failure.diagnostics=dict(attempts=attempts,solver_calls=calls,cache_hits=hits,cache_peak=peak)
                raise failure
            pending.extend([step/2,step/2]);continue
        previous=current
        for candidate in (half,fine):
            solid=swept_flux(grid,previous,candidate.contact.grains,step/2)
            liquid=grid.project(solid).liquid
            integral=[a+step/2*b for a,b in zip(integral,liquid)]
            work+=candidate.work_into_springs;dissipated+=candidate.dissipated
            previous=candidate.contact.grains;accepted.append(step/2)
        current=fine.contact.grains;old_history=fine.history;leaves+=1;pos_sum+=ep;hist_sum+=eh
    final=occupancy(grid,current)
    volume=max(abs((1-a)-d-(1-b)) for a,b,d in zip(initial,final,grid.divergence(integral)))
    energy=sum(.5*s.stiffness*s.elastic_slip**2 for s in old_history.values())
    balance=abs(work-(energy-initial_energy)-dissipated)
    if volume>1e-9 or balance>1e-9:raise ValueError('State-controlled interval conservation failed')
    return DoubledInterval(current,old_history,sum(accepted),accepted,attempts,calls,pos_sum,hist_sum,volume,balance,integral,hits,peak)
