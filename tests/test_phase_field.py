import math
import unittest
from phase_field_reference import circle, step


class PhaseFieldTests(unittest.TestCase):
    def test_gas_inventory_and_sealed_circle_under_transport(self):
        n = 24
        c, wall = circle(n, (11., 12.), 4.)
        inventory = math.fsum(c)
        start_y = sum(i // n * q for i, q in enumerate(c)) / inventory
        for _ in range(80):
            c, _ = step(c, n, [(0., -0.1)] * (n*n), wall)
        self.assertAlmostEqual(math.fsum(c), inventory, places=11)
        self.assertTrue(all(-1e-14 <= q <= 1 + 1e-14 for q in c))
        self.assertTrue(all(c[i] == 0 for i, w in enumerate(wall) if w))
        self.assertLess(sum(i // n * q for i, q in enumerate(c)) / inventory, start_y - 0.5)

    def test_extreme_flux_is_limited_without_destroying_mass(self):
        n = 9
        c = [0.] * (n*n)
        c[40] = 1.
        result, limited = step(c, n, [(20., 10.)] * (n*n), [False] * (n*n), dt=1.)
        self.assertGreater(limited, 0)
        self.assertAlmostEqual(math.fsum(result), 1., places=14)
        self.assertTrue(all(-1e-14 <= q <= 1 + 1e-14 for q in result))

    def test_constant_phase_has_no_spurious_transport(self):
        n = 9
        c = [0.37] * (n*n)
        result, limited = step(c, n, [(0., 0.)] * (n*n), [False] * (n*n))
        self.assertEqual(result, c)
        self.assertEqual(limited, 0)

    def test_rotation_covariance_for_quarter_turn(self):
        n = 17
        rotate = lambda a: [a[(n - 1 - x) * n + y] for y in range(n) for x in range(n)]
        c, wall = circle(n, (7., 9.), 3.)
        a, _ = step(c, n, [(0.04, -0.07)] * (n*n), wall)
        b, _ = step(rotate(c), n, [(0.07, 0.04)] * (n*n), rotate(wall))
        self.assertLess(max(abs(x-y) for x, y in zip(rotate(a), b)), 2e-15)

    def test_bulk_noise_does_not_nucleate_liquid_holes(self):
        n=13
        c=[.99 + (1e-4 if (x+y)%2 else -1e-4) for y in range(n) for x in range(n)]
        initial_range=max(c)-min(c)
        mass=math.fsum(c)
        for _ in range(80):
            c,_=step(c,n,[(0.,0.)]*(n*n),[False]*(n*n),dt=1.)
        self.assertLess(max(c)-min(c),initial_range*.25)
        self.assertAlmostEqual(math.fsum(c),mass,places=11)

    def test_invalid_input_does_not_mutate_state(self):
        c, wall = circle(9, (4., 4.), 2.)
        original = c.copy()
        with self.assertRaises(ValueError):
            step(c, 9, [(0., 0.)] * 81, wall, dt=float('nan'))
        self.assertEqual(c, original)


if __name__ == '__main__':
    unittest.main()
