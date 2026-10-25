"""Constant translation isolates geometric tangency from contact dynamics."""
from pathlib import Path
from dataclasses import replace
import sys,json
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.disk_volume import face_apertures,occupancy,swept_flux

def run():
    grid=DarcyGrid(16,circle_mask(16));grain=Grain(.4915,.517,.071,.04,2.65,1);velocity=.5
    source=[w*velocity if axis==0 else 0. for w,(_,_,_,axis) in zip(face_apertures(grid,grain),grid.faces)]
    frozen=grid.project(source).liquid;old=occupancy(grid,[grain]);rows=[]
    for dt in (.001,.00025,.0000625,.000015625):
        new=replace(grain,x=grain.x+velocity*dt)
        phi=occupancy(grid,[new]);solid=swept_flux(grid,[grain],[new],dt);q=grid.project(solid).liquid
        rate=max(abs(a-b) for a,b in zip(q,frozen))
        frozen_volume=max(abs(a+dt*d-b) for a,b,d in zip(old,phi,grid.divergence(frozen)))
        exact_volume=max(abs(a+dt*d-b) for a,b,d in zip(old,phi,grid.divergence(q)))
        rows.append(dict(dt=dt,flux_difference=rate,frozen_volume_error=frozen_volume,geometric_volume_error=exact_volume))
    return rows

def main():
    rows=run()
    report=dict(scope='Constant velocity at grid-face tangency; not an integrated trajectory error bound',rows=rows,
        successive_flux_ratios=[rows[i+1]['flux_difference']/rows[i]['flux_difference'] for i in range(3)],
        successive_volume_ratios=[rows[i+1]['frozen_volume_error']/rows[i]['frozen_volume_error'] for i in range(3)])
    (ROOT/'reports/tangency-time-scaling.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report))
if __name__=='__main__':main()
