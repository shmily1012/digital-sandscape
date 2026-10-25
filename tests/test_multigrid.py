import unittest
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.multigrid import Multigrid


class MultigridTests(unittest.TestCase):
    def test_warm_start_is_checked_against_current_equation(self):
        grid=DarcyGrid(16)
        rhs=[-v for v in grid.divergence(grid.prescribed_patch())]
        solver=Multigrid(grid)
        p,cold,_=solver.solve(rhs)
        _,unchanged,_=solver.solve(rhs,initial=p)
        changed=[v*1.01 for v in rhs]
        new,warm,residual=solver.solve(changed,initial=p)
        self.assertEqual(unchanged,0)
        self.assertGreater(warm,0)
        self.assertLess(warm,cold)
        self.assertLess(residual,1e-8)
        self.assertNotEqual(new,p)

    def test_coarse_operator_is_galerkin_projection(self):
        grid=DarcyGrid(16,circle_mask(16),[0.5+(i%16)/16 for i in range(256)])
        solver=Multigrid(grid)
        fine,coarse=solver.levels[:2]
        values=[(i%7)*0.2 for i in range(64)]
        parent=lambda i:(i//16//2)*8+i%16//2
        prolonged=[values[parent(i)] for i in range(256)]
        restricted=[0.0]*64
        for i,v in enumerate(fine.apply(prolonged)):
            restricted[parent(i)]+=v
        self.assertLess(max(abs(a-b) for a,b in zip(restricted,coarse.apply(values))),1e-10)

    def test_converges_to_same_flux_with_sealed_variable_mobility(self):
        grid=DarcyGrid(32,circle_mask(32),[0.3+(i%32)/32 for i in range(1024)])
        source=grid.prescribed_patch(velocity=(0.08,0.06))
        rhs=[-v for v in grid.divergence(source)]
        p,cycles,residual=Multigrid(grid).solve(rhs)
        reference=grid.project(source)
        self.assertLess(residual,1e-8)
        self.assertLess(cycles,128)
        self.assertLess(max(abs(a-b) for a,b in zip(grid.liquid_flux(p),reference.liquid)),1e-8)

    def test_budget_failure_is_explicit(self):
        grid=DarcyGrid(16)
        rhs=[-v for v in grid.divergence(grid.prescribed_patch())]
        with self.assertRaises(RuntimeError):
            Multigrid(grid).solve(rhs,max_cycles=1)
