import unittest
import math
from experiments.liquid.model import DarcyGrid,add_compensated,incomplete_cholesky


class CompensatedPressureTests(unittest.TestCase):
    def test_sparse_preconditioner_does_not_shift_the_physical_equation(self):
        grid=DarcyGrid.from_graph(4,[(0,1,1e8),(1,2,1.),(2,3,2.)])
        rows=[{} for _ in range(4)]
        for i,j,w,_ in grid.faces:
            rows[i][i]=rows[i].get(i,0.)+w;rows[j][j]=rows[j].get(j,0.)+w
            rows[i][j]=-w;rows[j][i]=-w
        precondition,shift=incomplete_cholesky(rows)
        p,iterations,residual=grid.pressure_for_source([1.,0.,0.,-1.],tolerance=1e-12,
            max_iterations=64,compensated=True,precondition=precondition)
        self.assertGreater(shift,0.)
        self.assertLessEqual(iterations,64)
        self.assertLessEqual(residual,1e-12)
        self.assertLess(max(abs(q-1.) for q in grid.liquid_flux(p,grid.last_pressure_low)),1e-12)

    def test_custom_inertia_operator_keeps_low_pressure_in_force_and_flux(self):
        grid=DarcyGrid.from_graph(3,[(0,1,1e12),(1,2,1.)])
        normal=(1.,0.,-1.)
        def operator(p,low=None):
            low=[0.]*3 if low is None else low
            reaction=.2*math.fsum(normal[i]*v for i in range(3) for v in (p[i],low[i]))
            return [a+normal[i]*reaction for i,a in enumerate(grid.operator(p,low))]
        diagonal=[sum(w for _,w in row)+.2*normal[i]**2 for i,row in enumerate(grid.neighbors)]
        p,_,residual=grid.pressure_for_source([1.,0.,-1.],tolerance=1e-12,max_iterations=64,
            apply=operator,diagonal=diagonal,compensated=True,apply_compensated=operator)
        expected=1/(1+.2*(1+1e-12))
        self.assertLessEqual(residual,1e-12)
        self.assertLess(max(abs(q-expected) for q in grid.liquid_flux(p,grid.last_pressure_low)),1e-12)
        with self.assertRaises(ValueError):
            grid.pressure_for_source([1.,0.,-1.],apply=operator,compensated=True)
        self.assertIsNone(grid.last_pressure_low)

    def test_thin_edge_flow_survives_pressure_datum_shift(self):
        grid=DarcyGrid.from_graph(3,[(0,1,1e12),(1,2,1.)])
        diagonal=[sum(w for _,w in row) for row in grid.neighbors]
        p,iterations,residual=grid.pressure_for_source([1.,0.,-1.],tolerance=1e-12,
                                                      max_iterations=64,diagonal=diagonal,compensated=True)
        low=grid.last_pressure_low
        self.assertLessEqual(iterations,64)
        self.assertLessEqual(residual,1e-12)
        self.assertLess(max(abs(q-1.) for q in grid.liquid_flux(p,low)),1e-12)
        shifted=[add_compensated(a,b,1e6) for a,b in zip(p,low)]
        shifted_flux=grid.liquid_flux([a for a,_ in shifted],[b for _,b in shifted])
        self.assertLess(max(abs(q-1.) for q in shifted_flux),1e-12)

    def test_iteration_budget_remains_enforced(self):
        grid=DarcyGrid.from_graph(4,[(0,1,1e8),(1,2,1.),(2,3,2.)])
        with self.assertRaises(RuntimeError) as failure:
            grid.pressure_for_source([1.,0.,0.,-1.],max_iterations=1,compensated=True)
        self.assertEqual(failure.exception.pressure_diagnostic['iterations'],1)
        self.assertGreater(failure.exception.pressure_diagnostic['residual'],1e-10)
        self.assertIsNone(grid.last_pressure_low)
