"""Record actual coupled evolution; analytic geometry only at initialization."""
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid
from experiments.liquid.capillary import circle_fractions
from experiments.liquid.surface_cell import SurfaceCell


def main():
    n=32
    cell=SurfaceCell(DarcyGrid(n),circle_fractions(n,center=(0.493,0.507)))
    initial=cell.fraction.copy()
    trace=[]
    for _ in range(100):
        report=cell.step(0.00005)
        trace.append({k:v for k,v in report.items() if k not in ('base_pressure','residual_pressure')})
    result=dict(size=n,tension=cell.tension,time=cell.time,steps=cell.steps,
                initial_max_speed=trace[0]['max_speed'],final_max_speed=trace[-1]['max_speed'],
                peak_speed=max(t['max_speed'] for t in trace),
                gas_area_error=abs(sum(initial)-sum(cell.fraction))/(n*n),
                minimum=min(cell.fraction),maximum=max(cell.fraction),
                initial_fraction=initial,final_fraction=cell.fraction,trace=trace,
                scope='CPU two-phase surface relaxation; no grains, walls wetting, gravity or GPU coupling')
    assert result['gas_area_error']<1e-10
    assert result['final_max_speed']<result['initial_max_speed']
    (ROOT/'reports/surface-evolution.json').write_text(json.dumps(result),encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('initial_fraction','final_fraction','trace')}))


if __name__=='__main__':
    main()
