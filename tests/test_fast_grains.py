import unittest
from unittest.mock import patch
from experiments.liquid.fast_grains import advance_fast, dissipation_margin
from experiments.liquid.grain_coupling import Grain
from experiments.liquid.model import DarcyGrid, circle_mask


class FastGrainSafetyTests(unittest.TestCase):
    def test_certificate_accounts_for_off_diagonal_work(self):
        self.assertLess(dissipation_margin([50, 60, 60, 50], .01), 0)
        self.assertGreater(dissipation_margin([50, 2, 2, 50], .01), 0)

    def test_unsupported_drag_rejected_without_mutation(self):
        grains = [Grain(.5, .5, .012, .04, 2.65, 1)]
        before = list(grains)
        with patch('experiments.liquid.fast_grains.estimate', return_value=[54, 0, 0, 54]):
            with self.assertRaisesRegex(ValueError, 'dissipation'):
                advance_fast(DarcyGrid(32, circle_mask(32)), grains, (0, 1), .02, {})
        self.assertEqual(grains, before)

    def test_geometry_not_silently_approximated_as_circle(self):
        with self.assertRaisesRegex(ValueError, 'circular geometry'):
            advance_fast(DarcyGrid(32), [], (0, 1), .02, {})

    def test_overlapping_grains_rejected_even_at_zero_gravity(self):
        grains = [Grain(.5, .5, .012, .01, 2.65, m) for m in (1, 2)]
        with patch('experiments.liquid.fast_grains.estimate', return_value=[54, 0, 0, 54]):
            with self.assertRaisesRegex(ValueError, 'contact'):
                advance_fast(DarcyGrid(32, circle_mask(32)), grains, (0, 0), .02, {})
