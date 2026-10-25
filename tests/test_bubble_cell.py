from collections import Counter
import math
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from experiments.bubbles.model import Bubble, BubbleCell, Grain


class BubbleCellTests(unittest.TestCase):
    def test_perimeter_force_matches_energy_gradient(self):
        for shape in (-0.5, -0.1, 0, 0.2, 0.5):
            bubble = Bubble(0.5, 0.5, 0.12, shape)
            epsilon = 1e-5
            numeric = (bubble.perimeter(shape+epsilon)-bubble.perimeter(shape-epsilon))/(2*epsilon)
            self.assertAlmostEqual(bubble.perimeter_derivative(), numeric, places=8)

    def test_buoyant_rise_and_area_conservation(self):
        cell = BubbleCell(bubbles=[Bubble(0.5, 0.6, 0.12)])
        area = cell.gas_area()
        for _ in range(100):
            cell.step(0.01)
        self.assertLess(cell.bubbles[0].y, 0.6)
        self.assertAlmostEqual(cell.gas_area(), area, places=14)

    def test_surface_energy_relaxes_non_circular_shape(self):
        bubble = Bubble(0.5, 0.5, 0.12, 0.3)
        cell = BubbleCell(bubbles=[bubble], gravity=(0, 0), shape_mobility=30)
        perimeter = bubble.perimeter()
        area = cell.gas_area()
        for _ in range(100):
            cell.step(0.01)
        self.assertLess(bubble.perimeter(), perimeter)
        self.assertAlmostEqual(cell.gas_area(), area, places=14)

    def test_contact_force_is_reciprocal(self):
        cell = BubbleCell(grains=[Grain(0.5, 0.375, 0.02, 1)],
                          bubbles=[Bubble(0.5, 0.5, 0.12)], gravity=(0, 0))
        gf, bf, _, penetration = cell.forces()
        self.assertGreater(penetration, 0)
        self.assertLess(gf[0][1], 0)
        self.assertGreater(bf[0][1], 0)
        self.assertAlmostEqual(gf[0][1]+bf[0][1], 0, places=14)

    def test_gas_and_materials_survive_gravity_reversal(self):
        cell = BubbleCell(grains=[Grain(0.3, 0.3, 0.02, 1), Grain(0.7, 0.3, 0.02, 2)],
                          bubbles=[Bubble(0.5, 0.55, 0.12)])
        inventory, area = Counter(cell.inventory()), cell.gas_area()
        for step in range(100):
            angle = step*0.11
            cell.gravity = math.sin(angle), math.cos(angle)
            cell.step(0.01)
        self.assertEqual(Counter(cell.inventory()), inventory)
        self.assertAlmostEqual(cell.gas_area(), area, places=14)

    def test_bubble_wall_containment(self):
        cell = BubbleCell(bubbles=[Bubble(0.12, 0.12, 0.12)], gravity=(-1, -1))
        for _ in range(100):
            cell.step(0.01)
        bubble = cell.bubbles[0]
        a, b = bubble.axes
        self.assertTrue(a <= bubble.x <= cell.width-a)
        self.assertTrue(b <= bubble.y <= cell.height-b)

    def test_dt_convergence_for_contact(self):
        results = []
        for dt, count in [(0.01, 100), (0.001, 1000)]:
            cell = BubbleCell(grains=[Grain(0.5, 0.37, 0.02, 1)],
                              bubbles=[Bubble(0.5, 0.5, 0.12)])
            for _ in range(count):
                cell.step(dt)
            results.append((cell.grains[0].y, cell.bubbles[0].y))
        self.assertLess(math.dist(*results), 0.001)

    def test_invalid_dt_rejected(self):
        with self.assertRaises(ValueError):
            BubbleCell().step(-1)
