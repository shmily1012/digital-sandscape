"""Matched dense versus matrix-free free-response diagnostic, single RHS."""
from pathlib import Path
import sys,json,time
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain,forces
from experiments.deposition.drainage_resistance import DrainageResistance
from experiments.deposition.matrix_free_drainage import MatrixFreeDrainage

def main():
    rows=[]
    for count in (4,16,36):
        side=int(count**.5);spacing=.07
        grains=[Grain(.5+(x-(side-1)/2)*spacing,.5+(y-(side-1)/2)*spacing,.03,.04,2.65-.1*((x+y)%3),1+(x+y)%3) for y in range(side) for x in range(side)]
        grid=DarcyGrid(24,circle_mask(24));force=[v for pair in forces(grains,(.3,1)) for v in pair]
        start=time.perf_counter();dense=DrainageResistance(grid,grains,geometric=True)
        expected=[sum(a*b for a,b in zip(row,force)) for row in dense.mobility]
        dense_ms=1000*(time.perf_counter()-start)
        start=time.perf_counter();op=MatrixFreeDrainage(grid,grains);result=op.solve(force)
        operator_ms=1000*(time.perf_counter()-start)
        error=max(abs(a-b) for a,b in zip(expected,result.velocity))
        row=dict(particles=count,dense_ms=dense_ms,matrix_free_ms=operator_ms,
                 dense_pressure_solves=2*count,matrix_free_pressure_solves=result.pressure_solves,
                 iterations=result.iterations,residual=result.residual,velocity_difference=error,
                 sparse_entries=sum(map(len,op.columns)),dense_response_values=2*count*len(grid.faces)+(2*count)**2)
        if error>1e-8:raise RuntimeError('Reference mismatch')
        rows.append(row);print(json.dumps(row),flush=True)
    (ROOT/'reports/matrix-free-drainage.json').write_text(json.dumps(dict(scope='Single CPU free-force response, no contacts; one timing sample per size, not a product benchmark',cases=rows),indent=2),encoding='utf-8')
if __name__=='__main__':main()
