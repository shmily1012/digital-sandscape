"""CPU adaptive contact/drainage cycle with bounded work and elapsed-time audit."""
from pathlib import Path
import sys,json,time,statistics,math
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.disk_volume import occupancy
from experiments.deposition.contact_particles import Plane
from experiments.deposition.adaptive_drainage import advance_drainage,DrainageBudgetError

def main():
    grid=DarcyGrid(24,circle_mask(24))
    grains=[Grain(x,y,.04,.04,2.65-.2*i,1+i%3) for i,(x,y) in enumerate(((.46,.54),(.54,.54),(.46,.46),(.54,.46)))]
    initial=list(grains);phi0=occupancy(grid,initial);rows=[];elapsed=0.;integral=[0.]*len(grid.faces)
    failures=0;budget_rejection=False
    for tick in range(40):
        gravity=(0,1 if tick<24 else -1)
        if tick==24:
            original=list(grains)
            try:advance_drainage(grid,grains,gravity,.025,[Plane(0,-1,-.65)],flux_tolerance=1e-12,max_substeps=1)
            except DrainageBudgetError:budget_rejection=grains==original
            if not budget_rejection:raise RuntimeError('Expected refusal without mutation')
        start=time.perf_counter()
        result=advance_drainage(grid,grains,gravity,.025,[Plane(0,-1,-.65)],flux_tolerance=.005,max_substeps=64)
        ms=1000*(time.perf_counter()-start)
        if [(g.radius,g.material) for g in grains]!=[(g.radius,g.material) for g in result.grains]:raise RuntimeError('Identity changed')
        grains=result.grains;elapsed+=result.elapsed
        integral=[a+b for a,b in zip(integral,result.integrated_liquid_flux)]
        phi=occupancy(grid,grains)
        total_error=max(abs((1-a)-d-(1-b)) for a,b,d in zip(phi0,phi,grid.divergence(integral)))
        row=dict(tick=tick+1,cpu_ms=ms,substeps=result.substeps,attempts=result.attempts,
                 resistance_builds=result.resistance_builds,flux_error=result.maximum_flux_error,
                 volume_error=total_error,centroid_y=sum(g.y for g in grains)/4)
        rows.append(row)
        if total_error>1e-9 or result.attempts>127 or abs(result.elapsed-.025)>1e-14:raise RuntimeError('Work/time/volume bound failed')
        if (tick+1)%10==0:print(json.dumps(row),flush=True)
    reference=json.loads((ROOT/'reports/drainage-time-convergence.json').read_text(encoding='utf-8'))['runs'][-1]['final_positions']
    difference=max(abs(a-b) for g,p in zip(grains,reference) for a,b in zip((g.x,g.y),p))
    report=dict(scope='CPU four-grain adaptive 1.0 time cycle; timings include Python pressure solves, not GPU performance',
                failures=failures,steps=len(rows),elapsed=elapsed,budget_rejection_retained=budget_rejection,
                cpu_median_ms=statistics.median(r['cpu_ms'] for r in rows),cpu_max_ms=max(r['cpu_ms'] for r in rows),
                substeps=sum(r['substeps'] for r in rows),attempts=sum(r['attempts'] for r in rows),
                max_substeps=max(r['substeps'] for r in rows),reference_position_difference=difference,rows=rows)
    (ROOT/'reports/adaptive-drainage-cycle.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='rows'}))
if __name__=='__main__':main()
