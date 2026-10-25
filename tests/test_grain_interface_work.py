import unittest
from grain_interface_work_reference import bond, energy, exchange_work, fixtures, neighbor, DIRECTIONS


class GrainInterfaceWorkTests(unittest.TestCase):
    def test_local_work_matches_global_energy_and_reverse(self):
        for case in fixtures():
            c, m, n, cosine = case['phase'], case['materials'], case['side'], case['cosine']
            initial = energy(c, m, n, cosine=cosine)
            for a in range(n*n):
                for q, d in enumerate(DIRECTIONS):
                    if not (case['mask'][a] & (1 << q)):
                        continue
                    b = neighbor(a, d, n)
                    moved_c, moved_m = c.copy(), m.copy()
                    moved_c[a], moved_c[b] = moved_c[b], moved_c[a]
                    moved_m[a], moved_m[b] = moved_m[b], moved_m[a]
                    work = case['work'][4*a+q]
                    self.assertAlmostEqual(energy(moved_c, moved_m, n, cosine=cosine)-initial, work, places=13)
                    self.assertAlmostEqual(exchange_work(moved_c, moved_m, n, b, a, cosine=cosine), -work, places=13)
                    self.assertEqual(sorted(m), sorted(moved_m))
                    self.assertEqual(sorted(c), sorted(moved_c))

    def test_boundary_energy_derivative_matches_robin(self):
        from wetting_reference import face_phase
        for cosine in (-.5, 0., .5):
            for c in (.1, .5, .9):
                eps = 1e-6
                derivative = (bond(c+eps, 0, 0., 2, cosine=cosine)-bond(c-eps, 0, 0., 2, cosine=cosine))/(2*eps)
                self.assertAlmostEqual(derivative, 2*.06*(c-face_phase(c, cosine)), places=10)

    def test_rotated_swap_has_same_work(self):
        for case in fixtures():
            n = case['side'];c = case['phase'];m = case['materials'];a=5*n+5;b=a+1
            rotate = lambda field: [field[(n-1-x)*n+y] for y in range(n) for x in range(n)]
            index = lambda i: (i%n)*n+n-1-i//n
            self.assertAlmostEqual(exchange_work(c,m,n,a,b,cosine=case['cosine']),
                                   exchange_work(rotate(c),rotate(m),n,index(a),index(b),cosine=case['cosine']), places=13)
