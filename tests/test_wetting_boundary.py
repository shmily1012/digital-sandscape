import math
import unittest
from wetting_reference import face_phase
from interface_stress_reference import fixtures, forces


class WettingBoundaryTests(unittest.TestCase):
    def test_surface_energy_variation_and_limits(self):
        sigma=.01;width=4.;kappa=1.5*sigma*width
        for cosine in (-.95,-.5,0.,.5,.95):
            for phase in (0.,.001,.1,.5,.9,.999,1.):
                cb=face_phase(phase,cosine,width)
                self.assertLess(abs(kappa*2*(cb-phase)+6*sigma*cosine*cb*(1-cb)),1e-15)
                self.assertTrue(0<=cb<=1)
                self.assertTrue(0<=2*cb-phase<=1)

    def test_liquid_preference_reduces_gas_at_grain_surface(self):
        self.assertLess(face_phase(.4,.5),.4)
        self.assertGreater(face_phase(.4,-.5),.4)
        self.assertEqual(face_phase(.4,0.),.4)

    def test_wetting_phase_transport_and_reaction_conserve(self):
        for case in fixtures():
            self.assertLess(abs(math.fsum(case['phase'])-math.fsum(case['phase_after'])),1e-12)
            self.assertTrue(all(0<=x<=1 for x in case['phase_after']))
            self.assertTrue(all(case['phase_after'][i]==0 for i,m in enumerate(case['material']) if m))
            for axis in range(2):
                self.assertLess(abs(math.fsum(f[axis] for f in case['force'])),1e-14)

    def test_nonzero_wetting_rotation_covariance(self):
        case=fixtures()[-1];n=case['side']
        rotate=lambda a:[a[(n-1-x)*n+y] for y in range(n) for x in range(n)]
        actual=forces(rotate(case['phase']),rotate(case['material']),n,wetting_cosine=case['wetting_cosine'])
        expected=[[-v[1],v[0]] for v in rotate(case['force'])]
        self.assertLess(max(abs(a-b) for u,v in zip(actual,expected) for a,b in zip(u,v)),1e-14)
