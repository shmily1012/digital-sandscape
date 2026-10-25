"""Exact on/off reuse audit, including matched budget refusals."""
from pathlib import Path
from dataclasses import asdict
import sys,json,time
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.contact_particles import Plane
from experiments.deposition.operator_history import advance_operator_history
from experiments.deposition.step_doubling_history import advance_doubled
from experiments.deposition.adaptive_drainage import DrainageBudgetError
from experiments.deposition.tangential_history import snapshot

def main():
    grid=DarcyGrid(16,circle_mask(16));kw=dict(planes=[Plane(0,-1,-.588)],plane_ids=[-1],stiffness=.1)
    first=advance_operator_history(grid,[Grain(.473,.517,.071,.04,2.65,1)],[10],{},(.4,1),.01,**kw).candidate
    rows=[];accepted={};rejected={};original=snapshot(first.history)
    for tolerance in (1e-4,1e-5):
        for reuse in (False,True):
            start=time.perf_counter()
            try:
                r=advance_doubled(grid,first.contact.grains,[10],first.history,(1,1),.04,position_tolerance=tolerance,history_tolerance=tolerance,reuse=reuse,**kw)
                data=asdict(r)
                row=dict(accepted=True,attempts=r.attempts,solver_calls=r.solver_calls,cache_hits=r.cache_hits,cache_peak=r.cache_peak)
                for key in ('solver_calls','cache_hits','cache_peak'):data.pop(key)
                accepted[reuse]=data
            except DrainageBudgetError as error:
                row=dict(accepted=False,**error.diagnostics);rejected[reuse]=row['attempts']
            row.update(tolerance=tolerance,reuse=reuse,cpu_ms=1000*(time.perf_counter()-start));rows.append(row)
            print(json.dumps(row),flush=True)
            if snapshot(first.history)!=original:raise RuntimeError('Input history mutated')
    if accepted[False]!=accepted[True] or rejected[False]!=rejected[True]:raise RuntimeError('Reuse changed outcome')
    report=dict(scope='One CPU interval, exact state/schedule equality and matched refusal; one timing sample per mode',cases=rows,accepted_state_exact=True,refusal_attempt_exact=True)
    (ROOT/'reports/step-reuse-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
if __name__=='__main__':main()
