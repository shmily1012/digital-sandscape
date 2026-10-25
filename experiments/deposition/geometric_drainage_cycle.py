"""Persistent four-grain contact trajectory with geometric volume audit."""
from pathlib import Path
import sys,json,math
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.disk_volume import occupancy,swept_flux
from experiments.deposition.drainage_resistance import DrainageResistance
from experiments.deposition.contact_particles import Plane,advance_contacts


def run(refinement=1):
    if not isinstance(refinement,int) or not 1<=refinement<=8:raise ValueError("Invalid refinement")
    grid=DarcyGrid(24,circle_mask(24))
    grains=[Grain(x,y,.04,.04,2.65-.2*i,1+i%3) for i,(x,y) in enumerate(((.46,.54),(.54,.54),(.46,.46),(.54,.46)))]
    initial=list(grains);rows=[];dt=.025/refinement
    for tick in range(40*refinement):
        gravity=(0,1 if tick<24*refinement else -1)
        model=DrainageResistance(grid,grains,geometric=True)
        result=advance_contacts(grains,gravity,dt,[Plane(0,-1,-.65)],mobility_matrix=model.mobility,tolerance=1e-12)
        old_phi=occupancy(grid,grains);new_phi=occupancy(grid,result.grains)
        solid=swept_flux(grid,grains,result.grains,dt)
        liquid=grid.project(solid).liquid
        error=max(abs((1-a)-dt*d-(1-b)) for a,b,d in zip(old_phi,new_phi,grid.divergence(liquid)))
        velocity=[v for pair in result.velocity for v in pair]
        _,frozen_liquid=model.flux(velocity)
        flux_change=max(abs(a-b) for a,b in zip(liquid,frozen_liquid))
        rows.append(dict(tick=tick+1,liquid_volume_error=error,solid_area=sum(new_phi)*grid.h**2,
                         max_solid_fraction=max(new_phi),contact_residual=result.residual,
                         finite_vs_frozen_flux=flux_change,centroid_y=sum(g.y for g in result.grains)/len(grains)))
        if error>1e-9 or result.residual>1e-8:raise RuntimeError('Volume or contact audit failed')
        if [(g.radius,g.material) for g in grains]!=[(g.radius,g.material) for g in result.grains]:raise RuntimeError('Identity changed')
        grains=result.grains
    report=dict(scope='CPU geometric endpoint audit of a frozen-resistance contact trajectory; no gas or finite-step nonlinear coupling',
                steps=len(rows),dt=dt,final_positions=[[g.x,g.y] for g in grains],rows=rows,max_liquid_volume_error=max(r['liquid_volume_error'] for r in rows),
                max_flux_change=max(r['finite_vs_frozen_flux'] for r in rows),
                initial_centroid_y=sum(g.y for g in initial)/4,final_centroid_y=sum(g.y for g in grains)/4)
    return report

def main():
    report=run()
    (ROOT/'reports/geometric-drainage-cycle.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='rows'}))
if __name__=='__main__':main()
