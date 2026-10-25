from collections import Counter
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from experiments.deposition.model import ContactBed


class ContactBedTests(unittest.TestCase):
    def test_finite_supply_and_identity_conservation(self):
        bed = ContactBed([i % 3+1 for i in range(600)])
        initial = Counter(bed.inventory())
        for _ in range(60):
            bed.release(50, 10)
            bed.relax()
            self.assertEqual(Counter(bed.inventory()), initial)
        self.assertFalse(bed.reservoir)
        bed.release(50, 100)
        self.assertEqual(Counter(bed.inventory()), initial)

    def test_peak_follows_release_position(self):
        for source in (30, 70):
            bed = ContactBed([1]*1800)
            for _ in range(180):
                bed.release(source, 10)
                bed.relax()
            heights = bed.heights()
            self.assertLessEqual(abs(heights.index(max(heights))-source), 1)
            self.assertEqual(bed.relax(), 0)
            self.assertGreater(max(heights), 0)
            self.assertLessEqual(max(abs(a-b)/bed.dx for a,b in zip(heights, heights[1:])), bed.start_slope)

    def test_relaxation_lowers_gravitational_potential(self):
        bed = ContactBed([1]*1500)
        bed.release(50, 1500)
        before = bed.potential()
        self.assertGreater(bed.relax(), 0)
        self.assertLess(bed.potential(), before)

    def test_static_dynamic_hysteresis(self):
        # Surface slope 0.64 lies between tan(30) and tan(35).
        resting = ContactBed([], columns=3)
        resting.columns[0] = [1]*32
        active = ContactBed([], columns=3)
        active.columns[0] = [1]*32
        active.active[0] = True
        self.assertEqual(resting.relax(), 0)
        self.assertGreater(active.relax(), 0)

    def test_tilt_destabilizes_existing_deposit_without_reset(self):
        bed = ContactBed([1]*1200)
        bed.release(50, 1200)
        bed.relax()
        before = [len(c) for c in bed.columns]
        bed.tilt_floor(20)
        self.assertGreater(bed.relax(), 0)
        self.assertNotEqual(before, [len(c) for c in bed.columns])
        self.assertEqual(len(bed.inventory()), 1200)

    def test_seeded_update_order_replays(self):
        outputs = []
        for _ in range(2):
            bed = ContactBed([i % 3+1 for i in range(700)], seed=83)
            for index in range(70):
                bed.release(40 if index < 35 else 60, 10)
                bed.relax()
            outputs.append(bed.columns)
        self.assertEqual(*outputs)
