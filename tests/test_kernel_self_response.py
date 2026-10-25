import unittest
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.liquid.kernel_self_response import estimate

class KernelDomainTests(unittest.TestCase):
    def test_near_wall_is_rejected_before_lookup(self):
        grid=DarcyGrid(32,circle_mask(32))
        with self.assertRaisesRegex(ValueError,'interior'):
            estimate(grid,Grain(.9,.5,.012,.04,2.65,1),{})

    def test_nonuniform_mobility_requires_new_operator(self):
        mobility=[1.0]*1024
        mobility[528]=2
        grid=DarcyGrid(32,circle_mask(32),mobility)
        with self.assertRaisesRegex(ValueError,'mobility'):
            estimate(grid,Grain(.5,.5,.012,.04,2.65,1),{})
