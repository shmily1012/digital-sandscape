"""Same physical equations as liquid fixtures, a different pressure solver."""
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid
from experiments.liquid.multigrid import Multigrid


def main():
    fixtures=json.loads((ROOT/'reports/liquid-fixtures.json').read_text(encoding='utf-8'))
    for fixture in fixtures:
        n=fixture['size']
        grid=DarcyGrid(n)
        grid.faces=[(i,j,m,0 if j-i==1 else 1) for i,j,m,q in fixture['faces']]
        source=[f[3] for f in fixture['faces']]
        rhs=[-v for v in grid.divergence(source)]
        solver=Multigrid(grid)
        pressure,cycles,residual=solver.solve(rhs,tolerance=1e-8)
        descriptions=[]
        for index,level in enumerate(solver.levels):
            data=[]
            for i,row in enumerate(level.neighbors):
                weights=[0.0]*4
                for j,w in row:
                    weights[{-1:0,1:1,-level.size:2,level.size:3}[j-i]]=w
                data.extend(weights+[rhs[i] if index==0 else 0,0,0,0])
            descriptions.append(dict(size=level.size,equations=data))
        fixture['jacobi_steps']=fixture['steps']
        fixture['steps']=cycles
        fixture['levels']=descriptions
        fixture['pressure']=pressure
        fixture['liquid']=grid.liquid_flux(pressure)
        fixture['mixture']=[a+b for a,b in zip(source,fixture['liquid'])]
        fixture['multigrid_residual']=residual
        print(fixture['name'],cycles,residual,flush=True)
    (ROOT/'reports/multigrid-fixtures.json').write_text(json.dumps(fixtures),encoding='utf-8')


if __name__=='__main__':main()
