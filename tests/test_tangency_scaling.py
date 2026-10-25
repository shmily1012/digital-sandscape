import unittest
from experiments.deposition.tangency_time_scaling import run

class TangencyScalingTests(unittest.TestCase):
    def test_tangency_flux_rate_and_integrated_volume_have_different_orders(self):
        rows=run()
        for before,after in zip(rows,rows[1:]):
            self.assertAlmostEqual(after['flux_difference']/before['flux_difference'],.5,delta=.002)
            self.assertAlmostEqual(after['frozen_volume_error']/before['frozen_volume_error'],.125,delta=.002)
        self.assertTrue(all(r['geometric_volume_error']<1e-10 for r in rows))
