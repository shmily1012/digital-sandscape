import unittest
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain,forces
from experiments.deposition.drainage_resistance import DrainageResistance
from experiments.deposition.matrix_free_drainage import MatrixFreeDrainage

class MatrixFreeDrainageTests(unittest.TestCase):
    def setUp(self):
        self.grid=DarcyGrid(16,circle_mask(16))
        self.grains=[Grain(.45,.5,.05,.04,2.65,1),Grain(.55,.5,.05,.03,2.2,2)]
        self.reference=DrainageResistance(self.grid,self.grains,geometric=True)
        self.operator=MatrixFreeDrainage(self.grid,self.grains)

    def test_apply_matches_all_reference_columns_and_energy(self):
        for i in range(4):
            vector=[float(k==i) for k in range(4)]
            result=self.operator.apply(vector)
            self.assertLess(max(abs(result[k]-self.reference.resistance[k][i]) for k in range(4)),1e-11)
        v=[.21,-.7,.41,.31];hv=self.operator.apply(v)
        self.assertAlmostEqual(sum(a*b for a,b in zip(v,hv)),self.reference.dissipation(v),places=11)

    def test_solve_matches_dense_inverse_under_gravity_and_separation(self):
        for force in ([v for pair in forces(self.grains,(.3,-.7)) for v in pair],[-1.,0.,1.,0.]):
            result=self.operator.solve(force)
            expected=[sum(a*b for a,b in zip(row,force)) for row in self.reference.mobility]
            self.assertLess(max(abs(a-b) for a,b in zip(result.velocity,expected)),1e-8)
            self.assertLessEqual(result.residual,1e-10)
            self.assertLessEqual(result.pressure_solves,2*128+1)

    def test_budget_failure_and_zero_force(self):
        force=[1.,2.,-.2,.3];original=force.copy()
        with self.assertRaisesRegex(ValueError,'budget exhausted'):self.operator.solve(force,max_iterations=1)
        self.assertEqual(force,original)
        result=self.operator.solve([0.]*4)
        self.assertEqual(result.velocity,[0.]*4)
        self.assertEqual(result.pressure_solves,0)

    def test_variable_mobility_remains_reciprocal(self):
        grid=DarcyGrid(16,circle_mask(16),[.1+((i%16)/16) for i in range(256)])
        op=MatrixFreeDrainage(grid,self.grains)
        a=[.3,.2,-.6,.1];b=[.8,-.1,.7,-.3]
        self.assertAlmostEqual(sum(x*y for x,y in zip(a,op.apply(b))),sum(x*y for x,y in zip(b,op.apply(a))),places=11)
