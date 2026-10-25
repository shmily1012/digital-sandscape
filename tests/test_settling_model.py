import math
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from experiments.settling.model import Grain, Mineral, advance, reynolds


class SettlingModelTests(unittest.TestCase):
    def grain(self, diameter=20e-6, density=2650):
        return Grain(0.01, 0.02, 0, 0, Mineral(diameter, density, 7))

    def test_no_spurious_transverse_motion(self):
        grain = self.grain()
        for _ in range(120):
            grain = advance(grain, 1/60)
        self.assertEqual(grain.x, 0.01)
        self.assertEqual(grain.vx, 0)

    def test_matches_force_balance_and_stays_low_re(self):
        grain = advance(self.grain(), 1.0)
        # Independent terminal force balance using volume and drag coefficient.
        radius = grain.mineral.diameter_m/2
        buoyant_weight = (2650-1000)*4*math.pi*radius**3/3*9.81
        drag = 6*math.pi*0.001*radius*grain.vy
        self.assertAlmostEqual(drag/buoyant_weight, 1.0, places=12)
        self.assertLess(reynolds(grain), 0.1)

    def test_timestep_partition_preserves_elapsed_time(self):
        one = advance(self.grain(), 1.0)
        split = self.grain()
        for _ in range(120):
            split = advance(split, 1/120)
        self.assertAlmostEqual(split.y, one.y, places=14)
        self.assertAlmostEqual(split.vy, one.vy, places=14)

    def test_arbitrary_direction_has_no_grid_bias(self):
        for angle in (0, 13.7, 30, 45, 90, 120, 180, 270):
            a = math.radians(angle)
            g = (9.81*math.sin(a), 9.81*math.cos(a))
            result = advance(self.grain(), 1.0, gravity=g)
            self.assertAlmostEqual(result.vx*g[1]-result.vy*g[0], 0, places=14)
            self.assertGreater(result.vx*g[0]+result.vy*g[1], 0)

    def test_density_and_viscosity_have_physical_response(self):
        v = advance(self.grain(), 1.0).vy
        self.assertAlmostEqual(advance(self.grain(), 1.0, viscosity=0.002).vy, v/2)
        self.assertAlmostEqual(advance(self.grain(40e-6), 1.0).vy, 4*v)
        self.assertEqual(advance(self.grain(density=1000), 1.0).vy, 0)
        self.assertLess(advance(self.grain(density=900), 1.0).vy, 0)

    def test_material_identity_is_not_velocity(self):
        grain = self.grain()
        self.assertIs(advance(grain, 1.0).mineral, grain.mineral)

    def test_liquid_flow_advects_neutral_grain(self):
        result = advance(self.grain(density=1000), 1.0, liquid_velocity=(0.001, 0))
        self.assertAlmostEqual(result.vx, 0.001)
        self.assertEqual(result.vy, 0)
        self.assertGreater(result.x, 0.01)

    def test_rejects_unphysical_parameters(self):
        for diameter in (-1, 0, math.nan):
            with self.assertRaises(ValueError):
                self.grain(diameter)
        for dt in (-1, math.inf):
            with self.assertRaises(ValueError):
                advance(self.grain(), dt)
        with self.assertRaises(ValueError):
            advance(self.grain(), 1, viscosity=0)
