import unittest
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.contact_particles import advance_contacts,Plane,ContactConvergenceError
from experiments.deposition.drainage_resistance import DrainageResistance
from experiments.deposition.operator_contacts import advance_operator_contacts

class OperatorContactTests(unittest.TestCase):
    def setUp(self):
        self.grid=DarcyGrid(16,circle_mask(16))
        self.grains=[Grain(.5,.6,.05,.04,2.65,1),Grain(.5,.5,.05,.03,2.2,2)]
        self.planes=[Plane(0,-1,-.65)]

    def test_rest_release_slide_and_diagonal_match_dense(self):
        model=DrainageResistance(self.grid,self.grains,geometric=True)
        for gravity in ((0,1),(0,-1),(1,1),(.2,1)):
            with self.subTest(gravity=gravity):
                dense=advance_contacts(self.grains,gravity,.01,self.planes,mobility_matrix=model.mobility,tolerance=1e-12)
                actual=advance_operator_contacts(self.grid,self.grains,gravity,.01,self.planes)
                self.assertLess(max(abs(a-b) for va,vb in zip(dense.velocity,actual.contact.velocity) for a,b in zip(va,vb)),1e-8)
                self.assertLessEqual(actual.force_residual,1e-11)
                self.assertLessEqual(actual.contact.residual,1e-12)
                self.assertLessEqual(actual.contact.friction_power,1e-12)

    def test_budget_failure_retains_state(self):
        original=list(self.grains)
        with self.assertRaises(ContactConvergenceError):
            advance_operator_contacts(self.grid,self.grains,(1,-1),.01,self.planes,max_outer=1)
        self.assertEqual(self.grains,original)

    def test_external_force_validation(self):
        with self.assertRaises(ValueError):advance_contacts(self.grains,(0,1),.01,external_forces=[(0,1)])
        with self.assertRaises(ValueError):advance_contacts(self.grains,(0,1),.01,external_forces=[(0,float('nan')),(0,1)])
