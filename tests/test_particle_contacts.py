import math
import unittest
import json
from pathlib import Path
from unittest.mock import patch
from experiments.deposition.contact_particles import Plane,advance_contacts,circular_planes,advance_interval,ContactConvergenceError
from experiments.liquid.grain_coupling import Grain

class ParticleContactTests(unittest.TestCase):
    def grain(self,x,y,material=1): return Grain(x,y,.02,.02,2.65,material)

    def test_captured_contact_network_completes_same_interval(self):
        fixture=json.loads((Path(__file__).parent/'fixtures/contact_failure_231.json').read_text())
        grains=[Grain(**g) for g in fixture['grains']]
        before=list(grains)
        result=advance_interval(grains,fixture['failure']['gravity'],.05,circular_planes(32))
        self.assertGreater(result.substeps,1)
        self.assertLessEqual(result.substeps,8)
        self.assertLessEqual(result.attempts,15)
        self.assertEqual(result.elapsed,.05)
        self.assertLessEqual(result.maximum_residual,1e-9)
        self.assertEqual(grains,before)
        self.assertEqual([g.material for g in grains],[g.material for g in result.result.grains])

    def test_subdivision_failure_after_partial_progress_is_transactional(self):
        grains=[self.grain(.5,.5)]
        before=list(grains)
        accepted=advance_contacts(grains,(0,1),.05)
        error=ContactConvergenceError('test failure')
        with patch('experiments.deposition.contact_particles.advance_contacts',side_effect=[error,accepted,error]):
            with self.assertRaisesRegex(ContactConvergenceError,'complete interval'):
                advance_interval(grains,(0,1),.1,max_substeps=2)
        self.assertEqual(grains,before)

    def test_bad_geometry_is_not_retried_as_convergence_failure(self):
        grains=[self.grain(.5,.5),self.grain(.5,.5)]
        with self.assertRaisesRegex(ValueError,'overlap'):
            advance_interval(grains,(0,1),.1)

    def test_supported_stack_transmits_load_and_releases_after_flip(self):
        grains=[self.grain(.5,.98-.04*i,i+1) for i in range(3)]
        floor=[Plane(0,-1,-1)]
        result=advance_contacts(grains,(0,1),.1,floor)
        self.assertLess(max(math.hypot(*v) for v in result.velocity),2e-9)
        wall_force=sum(c[5] for c in result.reactions if c[1]==-1)
        self.assertAlmostEqual(wall_force,sum((g.density-1)*math.pi*g.radius**2 for g in grains),places=8)
        flipped=advance_contacts(result.grains,(0,-1),.1,floor)
        self.assertTrue(all(a.y<b.y for a,b in zip(flipped.grains,result.grains)))
        self.assertEqual([g.material for g in flipped.grains],[1,2,3])

    def test_effective_friction_static_and_sliding_threshold(self):
        g=self.grain(.5,.98)
        for angle in (20,40):
            a=math.radians(angle)
            result=advance_contacts([g],(math.sin(a),math.cos(a)),.1,[Plane(0,-1,-1)],friction=.5)
            speed=(g.density-1)*math.pi*g.radius**2/g.drag*max(0,math.sin(a)-.5*math.cos(a))
            self.assertAlmostEqual(result.velocity[0][0],speed,places=10)
            self.assertAlmostEqual(result.velocity[0][1],0,places=10)
            self.assertLessEqual(result.friction_power,1e-15)

    def test_free_particle_has_no_contact_reaction(self):
        g=self.grain(.5,.5)
        result=advance_contacts([g],(.6,.8),.01,[Plane(0,-1,-1)])
        speed=(g.density-1)*math.pi*g.radius**2/g.drag
        self.assertAlmostEqual(result.velocity[0][0],.6*speed)
        self.assertTrue(all(c[5]==c[6]==0 for c in result.reactions))

    def test_resting_contact_does_not_accumulate_solver_overlap(self):
        grains=[self.grain(.5,.98-.04*i) for i in range(3)]
        for _ in range(100):
            grains=advance_contacts(grains,(0,1),.05,[Plane(0,-1,-1)]).grains
        for a,b in zip(grains,grains[1:]):
            self.assertGreaterEqual(math.hypot(a.x-b.x,a.y-b.y),.04-1e-10)

    def test_circle_containment_over_continuous_rotation(self):
        grains=[self.grain(.5,.5)]
        walls=circular_planes()
        for step in range(200):
            a=step*.03
            grains=advance_contacts(grains,(math.sin(a),math.cos(a)),.1,walls).grains
            self.assertLessEqual(math.hypot(grains[0].x-.5,grains[0].y-.5)+grains[0].radius,.46+1e-9)

    def test_failure_does_not_mutate_input(self):
        grains=[self.grain(.5,.98-.04*i) for i in range(4)]
        before=list(grains)
        with self.assertRaisesRegex(ValueError,'budget'):
            advance_contacts(grains,(0,1),.1,[Plane(0,-1,-1)],max_iterations=1)
        self.assertEqual(grains,before)
