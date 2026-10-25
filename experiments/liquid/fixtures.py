"""CPU oracle for pressure/flux kernels and sealed return-flow scenarios."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from experiments.liquid.model import DarcyGrid, circle_mask
from experiments.liquid.capillary import circle_fractions,height_curvature,split_capillary_pressure


def main():
    fixtures = []
    for name, n, circular, velocity, variable in (
            ('settling',16,False,(0,0.1),False),
            ('rising_circle',16,True,(0,-0.1),False),
            ('oblique_variable',16,True,(0.08,0.06),True),
            ('settling_32',32,True,(0,0.1),False),
            ('capillary_constant',32,False,(0,0),False),
            ('capillary_estimated',32,False,(0,0),False)):
        mobility = [0.3+0.7*(i%n)/n if variable else 1 for i in range(n*n)]
        grid = DarcyGrid(n, circle_mask(n) if circular else None, mobility)
        prescribed = grid.prescribed_patch(velocity=velocity)
        base_pressure=None
        if name.startswith('capillary'):
            fraction=circle_fractions(n,center=(0.493,0.507))
            curvature=[5.0]*(n*n) if name.endswith('constant') else height_curvature(n,fraction)
            base_pressure,prescribed=split_capillary_pressure(grid,fraction,curvature,0.01)
        converged = grid.project(prescribed)
        steps = 2048 if n == 16 else 8192
        pressure = grid.jacobi(prescribed,steps)
        liquid = grid.liquid_flux(pressure)
        mixture = [a+b for a,b in zip(prescribed,liquid)]
        residual = max(map(abs,grid.divergence(mixture)))
        assert residual < 1e-7, (name,residual)
        rhs = [-v for v in grid.divergence(prescribed)]
        equations=[]
        for i, neighbors in enumerate(grid.neighbors):
            weights=[0.0]*4
            for j,w in neighbors:
                weights[{-1:0,1:1,-n:2,n:3}[j-i]]=w
            equations.extend(weights+[rhs[i],0,0,0])
        fixtures.append(dict(name=name,size=n,steps=steps,equations=equations,
                             faces=[list(f[:3])+[q] for f,q in zip(grid.faces,prescribed)],
                             pressure=pressure,liquid=liquid,mixture=mixture,
                             cg_residual=converged.residual,cg_iterations=converged.iterations,
                             jacobi_residual=residual,base_pressure=base_pressure))
        print(name,'CG iterations',converged.iterations,'Jacobi residual',residual)
    (ROOT/'reports/liquid-fixtures.json').write_text(json.dumps(fixtures),encoding='utf-8')


if __name__=='__main__':
    main()
