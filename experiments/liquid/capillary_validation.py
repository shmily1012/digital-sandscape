"""Separate balanced-force identity from estimated-curvature accuracy."""
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid
from experiments.liquid.capillary import circle_fractions,height_curvature,capillary_flux


def main():
    results=[]
    for n in (32,64):
        grid=DarcyGrid(n)
        fraction=circle_fractions(n,center=(0.493,0.507))
        for method in ('constant_oracle','height_estimated'):
            curvature=[5.0]*(n*n) if method=='constant_oracle' else height_curvature(n,fraction)
            flux=capillary_flux(grid,fraction,curvature,0.01)
            solution=grid.project(flux)
            inside=[p for p,c in zip(solution.pressure,fraction) if c>0.999]
            outside=[p for p,c in zip(solution.pressure,fraction) if c<0.001]
            jump=sum(inside)/len(inside)-sum(outside)/len(outside)
            interface=[k for k,c in zip(curvature,fraction) if 1e-5<c<1-1e-5]
            result=dict(size=n,method=method,tension=0.01,radius=0.2,
                        pressure_jump=jump,expected_jump=0.05,relative_jump_error=abs(jump-0.05)/0.05,
                        max_spurious_face_speed=max(map(abs,solution.mixture)),
                        max_divergence=solution.residual,cg_iterations=solution.iterations,
                        mean_interface_curvature_error=sum(abs(k-5) for k in interface)/len(interface))
            results.append(result)
            print(json.dumps(result))
    (ROOT/'reports/capillary-validation.json').write_text(json.dumps(results,indent=2),encoding='utf-8')


if __name__=='__main__':
    main()
