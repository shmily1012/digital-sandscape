"""CPU oracle for a complete 16-grain GPU contact cycle."""
from pathlib import Path
import sys,json,math
from dataclasses import asdict
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.deposition.contact_particles import advance_interval,circular_planes
from experiments.liquid.grain_coupling import Grain

def main():
    initial=[Grain(.4+.065*x+.002*math.sin(y*5+x),.24+.065*y,.025,.02,2.65,1+(x+y)%3) for y in range(4) for x in range(4)]
    grains=list(initial);walls=circular_planes(32);steps=[]
    for index in range(240):
        gravity=(0,1) if index<160 else (.6,-.8)
        interval=advance_interval(grains,gravity,.05,walls,max_iterations=256,tolerance=1e-7)
        result=interval.result;grains=result.grains
        steps.append(dict(gravity=gravity,accepted=True,reactions=[list(c[5:7]) for c in result.reactions],contacts=[list(c) for c in result.reactions],expected=[asdict(g) for g in grains]))
    test=dict(name='complete_cycle',initial=[asdict(g) for g in initial],steps=steps,budget=256,dt=.05,friction=.5,planes=[[w.nx,w.ny,w.offset,0] for w in walls])
    (ROOT/'reports/contact-cycle-fixtures.json').write_text(json.dumps(dict(cases=[test])),encoding='utf-8')
    print('CPU cycle fixture: 240 accepted intervals')
if __name__=='__main__':main()
