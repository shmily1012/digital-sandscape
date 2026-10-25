import collections
import math
import unittest

from reference_model import blocks, center, centered_cloud, gravity, initial_state, serialize, step


class PhysicalIntegrityTests(unittest.TestCase):
    def test_every_cell_has_exactly_one_writer_per_phase(self):
        for side in (15, 16, 31, 32, 256, 512):
            for phase in (0, 1):
                writers = collections.Counter(i for _, _, ids in blocks(side, phase)
                                              for i in ids if i is not None)
                self.assertEqual(len(writers), side*side)
                self.assertEqual(set(writers.values()), {1})

    def test_material_conservation_and_boundary_through_1000_rotations(self):
        side, seed = 24, 20261024
        cells = initial_state(side, seed)
        counts = collections.Counter(cells)
        wall = {i for i, value in enumerate(cells) if value == 4}
        for tick in range(1000):
            step(cells, side, seed, tick, gravity(tick*137.507764))
            self.assertEqual(collections.Counter(cells), counts)
            self.assertEqual({i for i, value in enumerate(cells) if value == 4}, wall)

    def test_seed_and_tick_replay(self):
        runs = []
        for _ in range(2):
            cells = initial_state(32, 709)
            for tick in range(70):
                step(cells, 32, 709, tick, gravity(tick*3.75))
            runs.append(serialize(cells))
        self.assertEqual(*runs)
        self.assertNotEqual(initial_state(32, 709), initial_state(32, 710))

    def test_dispatch_order_does_not_change_result(self):
        forward = initial_state(32, 91)
        reverse = forward.copy()
        for tick in range(20):
            step(forward, 32, 91, tick, gravity(33.7))
            step(reverse, 32, 91, tick, gravity(33.7), reverse_blocks=True)
        self.assertEqual(forward, reverse)

    def test_zero_gravity_has_no_motion(self):
        cells = initial_state(32, 52)
        previous = cells.copy()
        for tick in range(20):
            step(cells, 32, 52, tick, (0, 0))
        self.assertEqual(cells, previous)

    def test_all_requested_angles_move_downhill(self):
        for angle in (0, 30, 45, 90, 120, 180, 270, 13.7, 359.3):
            with self.subTest(angle=angle):
                cells = centered_cloud(48)
                before = center(cells, 48)
                g = gravity(angle)
                for tick in range(30):
                    step(cells, 48, 908, tick, g)
                after = center(cells, 48)
                projection = sum((a-b)*v for a, b, v in zip(after, before, g))/32767
                self.assertGreater(projection, 2.0)

    def test_gravity_is_continuous_and_periodic(self):
        self.assertEqual(gravity(0), gravity(360))
        for angle in range(360):
            a, b = gravity(angle), gravity(angle+0.1)
            self.assertLess(math.dist(a, b), 59)
            self.assertAlmostEqual(math.hypot(*a), 32767, delta=1)

    def test_rotation_changes_existing_world_without_reseeding(self):
        cells = initial_state(32, 82)
        for tick in range(100):
            step(cells, 32, 82, tick, gravity(0))
        settled = cells.copy()
        before = center(cells, 32)
        for tick in range(100, 200):
            step(cells, 32, 82, tick, gravity(180))
        self.assertNotEqual(cells, settled)
        self.assertLess(center(cells, 32)[1], before[1])
        self.assertEqual(collections.Counter(cells), collections.Counter(settled))

    def test_different_minerals_have_different_settling_rates(self):
        distances = []
        for material in (1, 2, 3):
            total = 0.0
            for seed in range(5):
                cells = centered_cloud(48, material)
                before = center(cells, 48)[1]
                for tick in range(12):
                    step(cells, 48, seed, tick, gravity(0))
                total += center(cells, 48)[1]-before
            distances.append(total)
        self.assertGreater(distances[0], distances[1])
        self.assertGreater(distances[1], distances[2])

    def test_gravitational_potential_never_increases(self):
        cells = initial_state(32, 821)
        g = gravity(43.8)
        def potential():
            return sum((i % 32*g[0] + i // 32*g[1])
                       for i, value in enumerate(cells) if 1 <= value <= 3)
        previous = potential()
        for tick in range(100):
            step(cells, 32, 821, tick, g)
            current = potential()
            self.assertGreaterEqual(current, previous)
            previous = current

    def test_eventually_reaches_a_stationary_deposit(self):
        cells = initial_state(24, 24)
        for tick in range(400):
            step(cells, 24, 24, tick, gravity(0))
        settled = cells.copy()
        for tick in range(400, 500):
            step(cells, 24, 24, tick, gravity(0))
        self.assertEqual(cells, settled)


if __name__ == "__main__":
    unittest.main()
