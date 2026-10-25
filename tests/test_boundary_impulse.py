"""Independent physical budget checks for the fixed-geometry streaming step."""
import math
import unittest
from grain_traction_reference import cases
from phase_momentum_reference import advance, E


class BoundaryImpulseTests(unittest.TestCase):
    def test_fluid_momentum_change_balances_all_boundary_impulses(self):
        for case in cases():
            with self.subTest(case=case['name']):
                f, m, n = case['populations'], case['materials'], case['side']
                after, _ = advance(f, [0.] * len(m), m, n, gravity=(0., 0.), sigma=0.)
                for axis in (0, 1):
                    delta = math.fsum((after[9*i+q]-f[9*i+q])*E[q][axis]
                                      for i in range(len(m)) if m[i] == 0 for q in range(9))
                    reaction = math.fsum(case['raw_expected'][axis::2])
                    self.assertAlmostEqual(delta + reaction, 0., places=12)

    def test_partial_contact_requires_nonzero_static_support(self):
        case = cases()[1]
        center = case['center']
        # At rho=2 the missing upper fluid link leaves -2*rho/9 force.
        self.assertAlmostEqual(case['raw_expected'][center*2+1], -4/9, places=12)
        self.assertAlmostEqual(case['expected'][center*2+1], 0., places=12)
        # The legacy background subtraction hides a load that contacts must balance.
        self.assertGreater(abs(case['raw_expected'][center*2+1]), .4)
