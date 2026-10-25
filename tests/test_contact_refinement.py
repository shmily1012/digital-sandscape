import json
import math
import unittest
from pathlib import Path
from experiments.deposition.contact_particles import advance_contacts,circular_planes,ContactConvergenceError
from experiments.deposition.contact_refinement import refine
from experiments.liquid.grain_coupling import Grain

class ContactRefinementTests(unittest.TestCase):
    def failed_network(self):
        fixture=json.loads((Path(__file__).parent/'fixtures/contact_gpu_failure_232.json').read_text())
        grains=[Grain(**g) for g in fixture['grains']]
        try:
            advance_contacts(grains,fixture['gravity'],.05,circular_planes(32),max_iterations=256,tolerance=1e-7)
        except ContactConvergenceError as error:
            return grains,fixture['gravity'],error.contacts
        self.fail('Captured difficult network no longer reproduces')

    def test_captured_network_converges_without_subdivision(self):
        grains,gravity,contacts=self.failed_network()
        before=list(grains)
        result,history=refine(grains,contacts,gravity,.05)
        self.assertLessEqual(result.residual,1e-9)
        self.assertLessEqual(len(history),32)
        self.assertEqual(grains,before)
        for i,g in enumerate(result.grains):
            self.assertEqual(g.material,grains[i].material)
            for other in result.grains[:i]:
                self.assertGreaterEqual(math.hypot(g.x-other.x,g.y-other.y),g.radius+other.radius-1e-10)
            for wall in circular_planes(32):
                self.assertGreaterEqual(wall.nx*g.x+wall.ny*g.y,wall.offset+g.radius-1e-10)
        self.assertLessEqual(result.friction_power,1e-10)
        for c in result.reactions:
            self.assertGreaterEqual(c[5],-1e-12)
            self.assertLessEqual(abs(c[6]),.5*c[5]+1e-12)

    def test_insufficient_refinement_budget_keeps_input(self):
        grains,gravity,contacts=self.failed_network()
        before=list(grains)
        with self.assertRaises(ContactConvergenceError):
            refine(grains,contacts,gravity,.05,max_iterations=1)
        self.assertEqual(grains,before)

    def test_float32_refinement_and_active_system_size(self):
        grains,gravity,contacts=self.failed_network()
        trace=[]
        result,_=refine(grains,contacts,gravity,.05,tolerance=1e-7,precision='float32',trace=trace)
        self.assertLessEqual(result.residual,1e-7)
        self.assertTrue(trace)
        self.assertTrue(all(s['matrix_size']<=32 for s in trace))
        self.assertTrue(any(s['rank']<s['matrix_size'] for s in trace))
