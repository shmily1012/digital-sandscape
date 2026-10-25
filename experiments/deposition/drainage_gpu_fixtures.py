"""Generate sealed geometric drainage GPU fixtures with independent CPU oracle."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.deposition.geometric_operator_fixtures import main as geometry_fixtures
from experiments.liquid.model import DarcyGrid
from experiments.liquid.multigrid import Multigrid

def main():
    geometry_fixtures()
    cases=json.loads((ROOT/'reports/geometric-operator-fixtures.json').read_text(encoding='utf-8'))['cases'][:4]
    for c in cases:
        n=c['side'];grid=DarcyGrid(n)
        grid.faces=[(i,j,m,a) for (i,j,a,_),m in zip(c['faces'],c['mobility'])]
        adjacency=[[-1]*4 for _ in range(n*n)]
        for f,(i,j,m,a) in enumerate(grid.faces):
            adjacency[i][1 if a==0 else 3]=f;adjacency[j][0 if a==0 else 2]=f
        c['adjacency']=sum(adjacency,[]);c['levels']=[]
        for level in Multigrid(grid).levels:
            data=[]
            for row_index,row in enumerate(level.neighbors):
                weights=[0.]*4
                for j,w in row:weights[{-1:0,1:1,-level.size:2,level.size:3}[j-row_index]]=w
                data.extend(weights+[0.]*4)
            c['levels'].append(dict(size=level.size,equations=data))
        q=grid.project(c['expected_source']).liquid
        from experiments.deposition.disk_volume import face_apertures
        from experiments.liquid.grain_coupling import Grain
        weights=[face_apertures(grid,Grain(*g[:3],.04,2.65,1)) for g in c['grains']]
        c['expected_h']=[.04*v[a]-sum(w[f]*grid.h**2*q[f]/m for f,(_,_,m,axis) in enumerate(grid.faces) if axis==a) for w,v in zip(weights,c['velocities']) for a in (0,1)]
        c['expected_q']=q;c['budget']=128
    zero=dict(cases[0]);zero.update(name='zero_velocity',velocities=[[0.,0.]],expected_h=[0.,0.],expected_q=[0.]*len(zero['faces']));cases.append(zero)
    rejected=dict(cases[1]);rejected.update(name='pressure_budget',budget=1,accepted=False);cases.append(rejected)
    rejected=dict(cases[1]);rejected.update(name='invalid_geometry',fault='overlap',accepted=False);cases.append(rejected)
    rejected=dict(cases[1]);rejected.update(name='nan_velocity',fault='nan',accepted=False);cases.append(rejected)
    (ROOT/'reports/drainage-gpu-fixtures.json').write_text(json.dumps(dict(cases=cases)),encoding='utf-8')
if __name__=='__main__':main()
