"""Compare state-controlled interval against two uniform fine trajectories."""
from pathlib import Path
import sys,json,time
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.contact_particles import Plane
from experiments.deposition.operator_history import advance_operator_history
from experiments.deposition.step_doubling_history import advance_doubled
from experiments.deposition.adaptive_drainage import DrainageBudgetError

def main():
    grid=DarcyGrid(16,circle_mask(16));kw=dict(planes=[Plane(0,-1,-.588)],plane_ids=[-1],stiffness=.1)
    first=advance_operator_history(grid,[Grain(.473,.517,.071,.04,2.65,1)],[10],{},(.4,1),.01,**kw).candidate
    references=[]
    for count in (128,256):
        g=first.contact.grains;h=first.history
        for _ in range(count):
            c=advance_operator_history(grid,g,[10],h,(1,1),.04/count,**kw).candidate;g=c.contact.grains;h=c.history
        references.append((g,h));print(json.dumps(dict(reference_steps=count,x=g[0].x)),flush=True)
    rows=[]
    report=dict(scope='One supported grain over .04; empirical comparison, no guaranteed trajectory bound',cases=rows,
                reference_position_difference=abs(references[0][0][0].x-references[1][0][0].x))
    path=ROOT/'reports/step-doubling-history.json'
    path.write_text(json.dumps(report,indent=2),encoding='utf-8')
    for tolerance in (1e-4,1e-5):
        start=time.perf_counter()
        try:r=advance_doubled(grid,first.contact.grains,[10],first.history,(1,1),.04,position_tolerance=tolerance,history_tolerance=tolerance,**kw)
        except DrainageBudgetError as error:
            row=dict(tolerance=tolerance,accepted=False,reason=str(error),cpu_ms=1000*(time.perf_counter()-start))
            rows.append(row);path.write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(row),flush=True)
            continue
        ms=1000*(time.perf_counter()-start);ref_g,ref_h=references[-1]
        error=max(abs(a-b) for g,bg in zip(r.grains,ref_g) for a,b in ((g.x,bg.x),(g.y,bg.y)))
        history_error=max(abs(s.elastic_slip-ref_h[k].elastic_slip) for k,s in r.history.items())
        row=dict(tolerance=tolerance,accepted=True,cpu_ms=ms,substeps=len(r.accepted_steps),attempts=r.attempts,solver_calls=r.solver_calls,
                 position_error=error,history_error=history_error,position_estimate_sum=r.position_estimate_sum,
                 volume_error=r.volume_error,energy_error=r.energy_error)
        rows.append(row);path.write_text(json.dumps(report,indent=2),encoding="utf-8");print(json.dumps(row),flush=True)
    report=dict(scope='One supported grain over .04; empirical comparison, no guaranteed trajectory bound',cases=rows,
                reference_position_difference=abs(references[0][0][0].x-references[1][0][0].x))
    (ROOT/'reports/step-doubling-history.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    if any(not r['accepted'] for r in rows):raise SystemExit('Requested state tolerance exceeds current work budget')
if __name__=='__main__':main()
