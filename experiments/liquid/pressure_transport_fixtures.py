"""CPU oracle for a pressure-to-interface GPU command chain."""
import copy
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid
from experiments.liquid.geometric_transport import advect


def main():
    pressure=next(c for c in json.loads((ROOT/'reports/multigrid-fixtures.json').read_text()) if c['name']=='settling_32')
    geometric=next(c for c in json.loads((ROOT/'reports/geometric-fixtures.json').read_text()) if c['name']=='circular_returnflow')
    grid=DarcyGrid(32)
    grid.faces=[(i,j,m,0 if j-i==1 else 1) for i,j,m,q in pressure['faces']]
    cases=[]
    # Keep the observed high-forcing failure as a rejection regression.
    for name,scale,dt,budget,accepted in [('normal',1,0.02,96,True),('large_dt_cfl',1,1,96,True),('high_forcing_rejected',20,1,128,False),('reverse',-1,0.02,96,True),('unconverged',1,0.02,1,False),('nonfinite_velocity',1,0.02,96,False)]:
        forcing=[q*scale for i,j,m,q in pressure['faces']]
        solution=grid.project(forcing)
        expected,actual_dt=advect(grid,geometric['initial'],solution.mixture,dt) if accepted else (geometric['initial'],0)
        levels=copy.deepcopy(pressure['levels'])
        for i in range(1024):levels[0]['equations'][i*8+4]*=scale
        geometry=copy.deepcopy(geometric)
        for face in geometry['faces']:face[2]=0
        cases.append(dict(name=name,levels=levels,geometry=geometry,faces=[[i,j,m,q*scale] for i,j,m,q in pressure['faces']],
                          requested_dt=dt,expected_dt=actual_dt,expected=expected,budget=budget,accepted=accepted))
        print(name,'requested',dt,'accepted',actual_dt,flush=True)
    (ROOT/'reports/pressure-transport-fixtures.json').write_text(json.dumps(cases),encoding='utf-8')
    state=list(geometric['initial'])
    elapsed=0.0
    sequence=[]
    for index in range(41):
        name='normal' if index<20 else 'reverse'
        if index==20:name='nonfinite_velocity'
        case=next(c for c in cases if c['name']==name)
        if case['accepted']:
            velocity=grid.project([f[3] for f in case['faces']]).mixture
            state,step_dt=advect(grid,state,velocity,0.02)
            elapsed+=step_dt
        sequence.append(dict(case=name,expected=list(state),elapsed=elapsed))
    (ROOT/'reports/pressure-transport-sequence.json').write_text(json.dumps(sequence),encoding='utf-8')


if __name__=='__main__':main()
