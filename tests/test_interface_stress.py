import math
import unittest
from interface_stress_reference import forces, fixtures


class InterfaceStressTests(unittest.TestCase):
    def test_closed_system_reaction_and_nonzero_grain_force(self):
        for case in fixtures():
            f = case['force']
            for axis in range(2):
                self.assertLess(abs(math.fsum(v[axis] for v in f)), 1e-14)
            if case['sigma']:
                self.assertGreater(math.hypot(*f[65]), 1e-6)

    def test_pure_phases_have_no_capillary_force(self):
        n=9;m=[int(i%n in (0,n-1) or i//n in (0,n-1)) for i in range(n*n)]
        m[40]=2
        for c in (0.,1.):
            self.assertEqual(forces([c]*(n*n),m,n),[[0.,0.] for _ in m])

    def test_rotation_covariance(self):
        case=fixtures()[1];n=case['side']
        rotate=lambda a:[a[(n-1-x)*n+y] for y in range(n) for x in range(n)]
        result=forces(rotate(case['phase']),rotate(case['material']),n)
        expected=[[-v[1],v[0]] for v in rotate(case['force'])]
        self.assertLess(max(abs(a-b) for u,v in zip(result,expected) for a,b in zip(u,v)),1e-14)
