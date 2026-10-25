import unittest
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.contact_particles import Plane,ContactConvergenceError
from experiments.deposition.history_contacts import advance_history_contacts
from experiments.deposition.tangential_history import snapshot,restore

class HistoryContactTests(unittest.TestCase):
    def setUp(self):
        self.grains=[Grain(.5,.6,.05,.04,2.65,1),Grain(.5,.5,.05,.04,2.2,2)]
        self.kw=dict(planes=[Plane(0,-1,-.65)],plane_ids=[-1],stiffness=1.)

    def test_history_energy_and_restoration(self):
        first=advance_history_contacts(self.grains,[10,20],{},(.2,1),.01,**self.kw)
        self.assertTrue(first.history)
        self.assertAlmostEqual(first.work_into_springs-first.elastic_energy,first.dissipated,places=10)
        old_energy=first.elastic_energy
        second=advance_history_contacts(first.contact.grains,[10,20],first.history,(-.2,1),.01,**self.kw)
        copied=advance_history_contacts(first.contact.grains,[10,20],restore(snapshot(first.history)),(-.2,1),.01,**self.kw)
        self.assertEqual(second,copied)
        self.assertAlmostEqual(second.work_into_springs-(second.elastic_energy-old_energy),second.dissipated,places=10)

    def test_reorder_retains_stable_identity(self):
        a=advance_history_contacts(self.grains,[10,20],{},(.2,1),.01,**self.kw)
        b=advance_history_contacts(list(reversed(self.grains)),[20,10],{},(.2,1),.01,**self.kw)
        self.assertEqual(set(a.history),set(b.history))
        for x,y in zip(a.contact.velocity,reversed(b.contact.velocity)):
            self.assertLess(max(abs(i-j) for i,j in zip(x,y)),1e-9)

    def test_failure_does_not_mutate_particle_or_history(self):
        a=advance_history_contacts(self.grains,[10,20],{},(.2,1),.01,**self.kw)
        original=list(a.contact.grains);saved=snapshot(a.history)
        with self.assertRaises(ContactConvergenceError):advance_history_contacts(original,[10,20],a.history,(1,1),.01,max_iterations=1,**self.kw)
        self.assertEqual(original,a.contact.grains);self.assertEqual(snapshot(a.history),saved)
