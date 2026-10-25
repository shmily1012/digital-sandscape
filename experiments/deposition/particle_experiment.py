"""Finite-inventory contact settling and reversal; CPU experiment only."""
from pathlib import Path
import sys,json,math,time
from dataclasses import asdict
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.deposition.contact_particles import advance_interval,circular_planes
from experiments.liquid.grain_coupling import Grain

def main():
    grains=[Grain(.4+.065*x+.002*math.sin(y*5+x),.24+.065*y,.025,.02,2.65,1+(x+y)%3) for y in range(4) for x in range(4)]
    walls=circular_planes(32)
    initial=list(grains)
    snapshots=[list(grains)]
    max_residual=0.;max_iterations=0;start=time.perf_counter();rows=[]
    failure=None
    for step in range(240):
        gravity=(0,1) if step<160 else (.6,-.8)
        try:
            interval=advance_interval(grains,gravity,.05,walls)
            result=interval.result
        except ValueError as error:
            failure=dict(step=step+1,error=str(error),gravity=gravity)
            break
        grains=result.grains
        max_residual=max(max_residual,result.residual)
        max_iterations=max(max_iterations,result.iterations)
        rows.append(dict(step=step+1,substeps=interval.substeps,attempts=interval.attempts,elapsed=interval.elapsed,max_speed=max(math.hypot(*v) for v in result.velocity),friction_power=result.friction_power))
        if step in (159,239): snapshots.append(list(grains))
    metadata=lambda group:[(g.radius,g.drag,g.density,g.material) for g in group]
    intact=metadata(grains)==metadata(initial)
    contained=all(math.hypot(g.x-.5,g.y-.5)+g.radius<=.46+1e-9 for group in snapshots for g in group)
    settled=len(rows)>159 and rows[159]['max_speed']<1e-6
    moved=len(snapshots)>2 and sum(math.hypot(a.x-b.x,a.y-b.y) for a,b in zip(snapshots[1],snapshots[2]))>.1
    report=dict(scope='CPU translational contact, local drag, no carrier or bubbles; 32-sided sealed polygon',steps=len(rows),failure=failure,dt=.05,particles=16,identity=intact,contained=contained,settled=settled,reversal_moved=moved,max_residual=max_residual,max_iterations=max_iterations,cpu_seconds=time.perf_counter()-start,rows=rows,last_accepted=[asdict(g) for g in grains],snapshots=[[asdict(g) for g in group] for group in snapshots],failures=sum(not v for v in (intact,contained,settled,moved))+int(failure is not None))
    (ROOT/'reports/particle-contact-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in ('rows','snapshots','last_accepted')}),flush=True)
    sys.path.insert(0,str(ROOT/'.tools/plot-libs'))
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.patches import Circle
    if len(snapshots)<3:
        snapshots.extend([list(grains)]*(3-len(snapshots)))
    fig,axes=plt.subplots(1,3,figsize=(10,3.5))
    for ax,group,title in zip(axes,snapshots,(['Initial','After settling' if len(rows)>=160 else 'Last accepted state','Last accepted before rejection'] if failure else ['Initial','After settling','After gravity reversal'])):
        ax.add_patch(Circle((.5,.5),.46,fill=False,color='.3'))
        for g in group:ax.add_patch(Circle((g.x,g.y),g.radius,facecolor={1:'.15',2:'.5',3:'.85'}[g.material],edgecolor='.25',linewidth=.5))
        ax.set(xlim=(0,1),ylim=(1,0),aspect='equal',title=title)
        ax.set_axis_off()
    fig.suptitle('CPU contact experiment — 16 grains, no liquid flow or bubbles')
    fig.savefig(ROOT/'reports/particle-contact-stages.png',dpi=150)
    if report['failures']:raise SystemExit(1)
if __name__=='__main__':main()
