import unittest
from unittest.mock import patch
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.contact_particles import Plane,ContactConvergenceError
from experiments.deposition.drainage_resistance import DrainageResistance
from experiments.deposition.history_contacts import advance_history_contacts
from experiments.deposition.operator_history import advance_operator_history
from experiments.deposition.tangential_history import snapshot

class OperatorHistoryTests(unittest.TestCase):
    def setUp(self):
        self.grid=DarcyGrid(16,circle_mask(16));self.ids=[10,20]
        self.grains=[Grain(.5,.6,.05,.04,2.65,1),Grain(.5,.5,.05,.04,2.2,2)]
        self.kw=dict(planes=[Plane(0,-1,-.65)],plane_ids=[-1],stiffness=1.)

    def test_nonempty_history_matches_dense_and_not_accumulated_per_iteration(self):
        first=advance_history_contacts(self.grains,self.ids,{},(.2,1),.01,**self.kw)
        grains=first.contact.grains;history=first.history;saved=snapshot(history)
        dense=DrainageResistance(self.grid,grains,geometric=True)
        expected=advance_history_contacts(grains,self.ids,history,(-.4,1),.01,mobility_matrix=dense.mobility,**self.kw)
        actual=advance_operator_history(self.grid,grains,self.ids,history,(-.4,1),.01,**self.kw)
        self.assertGreater(actual.iterations,1)
        self.assertEqual(snapshot(history),saved)
        self.assertEqual(set(actual.candidate.history),set(expected.history))
        for key in expected.history:self.assertAlmostEqual(actual.candidate.history[key].elastic_slip,expected.history[key].elastic_slip,places=9)
        for va,vb in zip(expected.contact.velocity,actual.candidate.contact.velocity):
            self.assertLess(max(abs(a-b) for a,b in zip(va,vb)),1e-8)

    def test_budget_failure_preserves_both(self):
        first=advance_history_contacts(self.grains,self.ids,{},(.2,1),.01,**self.kw)
        grains=list(first.contact.grains);history=first.history;before=snapshot(history)
        with self.assertRaises(ContactConvergenceError):advance_operator_history(self.grid,grains,self.ids,history,(1,-1),.01,max_outer=1,**self.kw)
        self.assertEqual(grains,first.contact.grains);self.assertEqual(snapshot(history),before)
