from pathlib import Path
import sys,json,math
from dataclasses import asdict
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.deposition.contact_particles import advance_contacts,advance_interval,Plane,circular_planes
from experiments.liquid.grain_coupling import Grain

def main():
    stack=[Grain(.5,.98-.04*i,.02,.02,2.65,i+1) for i in range(3)]
    cases=[]
    captured=json.loads((ROOT/"tests/fixtures/contact_failure_231.json").read_text())
    for name,initial,directions,budget in [
        ('stack_and_reverse',stack,[(0,1)]*10+[(0,-1)]*10,2000),
        ('static_friction',[stack[0]],[(math.sin(math.radians(20)),math.cos(math.radians(20)))]*10,2000),
        ('sliding',[stack[0]],[(math.sin(math.radians(40)),math.cos(math.radians(40)))]*10,2000),
        ('circle_rotation',[Grain(.5,.85,.02,.02,2.65,1)],[(math.sin(i*.04),math.cos(i*.04)) for i in range(100)],2000),
        ('captured_full',[Grain(**g) for g in captured['grains']],[captured['failure']['gravity']],2000),
        ('budget_reject',stack,[(0,1)],1),
        ('overlap_reject',[stack[0],stack[0]],[(0,1)],2000)]:
        budget=min(budget,256)
        grains=list(initial);steps=[]
        walls=circular_planes(32) if name in ('circle_rotation','captured_full') else [Plane(0,-1,-1)]
        dt=.05
        for gravity in directions:
            accepted=True;reactions=[];contacts=[]
            try:
                interval=advance_interval(grains,gravity,dt,walls,max_iterations=budget,tolerance=1e-7)
                result=interval.result
                grains=result.grains
                reactions=[list(c[5:7]) for c in result.reactions]
                contacts=[list(c) for c in result.reactions]
            except ValueError:accepted=False
            steps.append(dict(gravity=gravity,accepted=accepted,reactions=reactions,contacts=contacts,expected=[asdict(g) for g in grains]))
        cases.append(dict(name=name,initial=[asdict(g) for g in initial],steps=steps,budget=budget,dt=dt,friction=.5,planes=[[w.nx,w.ny,w.offset,0] for w in walls]))
    # GPU ordering has a captured 128-iteration failure after two accepted
    # internal substeps. This is a rollback probe, not a CPU acceptance oracle.
    probe=json.loads(json.dumps(next(c for c in cases if c['name']=='captured_full')))
    probe['name']='partial_rollback'
    probe['budget']=128
    probe['steps']=[dict(gravity=captured['failure']['gravity'],accepted=False,reactions=[],contacts=[],expected=probe['initial'])]
    cases.append(probe)
    (ROOT/'reports/contact-interval-fixtures.json').write_text(json.dumps(dict(cases=cases)),encoding='utf-8')
if __name__=='__main__':main()
