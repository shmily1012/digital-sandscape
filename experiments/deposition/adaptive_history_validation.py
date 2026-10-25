"""Bounded history interval diagnostic; reports refusal and successful retry."""
from pathlib import Path
import sys,json,time
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.contact_particles import Plane
from experiments.deposition.operator_history import advance_operator_history
from experiments.deposition.adaptive_history import advance_history_interval
from experiments.deposition.adaptive_drainage import DrainageBudgetError
from experiments.deposition.tangential_history import snapshot

def main():
    grid=DarcyGrid(16,circle_mask(16));kw=dict(planes=[Plane(0,-1,-.588)],plane_ids=[-1],stiffness=.1)
    first=advance_operator_history(grid,[Grain(.473,.517,.071,.04,2.65,1)],[10],{},(.4,1),.01,**kw).candidate
    grains=first.contact.grains;history=first.history;saved=snapshot(history);original=list(grains)
    refused=False
    try:advance_history_interval(grid,grains,[10],history,(1,1),.04,max_substeps=32,**kw)
    except DrainageBudgetError as error:
        refused=grains==original and snapshot(history)==saved
        print(str(error),flush=True)
    if not refused:raise RuntimeError('Expected 32-substep budget refusal with old state retained')
    start=time.perf_counter();result=advance_history_interval(grid,grains,[10],history,(1,1),.04,max_substeps=64,**kw)
    report=dict(scope='Single CPU history interval, one supported grain; not a long-run or GPU benchmark',
                budget32_refused=refused,substeps=len(result.accepted_steps),attempts=result.attempts,
                accepted_steps=result.accepted_steps,elapsed=result.elapsed,cpu_ms=1000*(time.perf_counter()-start),
                max_flux_error=result.max_flux_error,volume_error=result.volume_error,energy_error=result.energy_error)
    (ROOT/'reports/adaptive-history-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report),flush=True)
if __name__=='__main__':main()
