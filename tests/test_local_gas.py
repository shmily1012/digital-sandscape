import math
import unittest
from grain_volume_reference import fixtures
from local_gas_reference import transport


class LocalGasTests(unittest.TestCase):
    def test_capacity_and_inventory_under_moving_grains(self):
        for case in fixtures():
            if not case['valid']:continue
            for profile in case['gas_profiles']:
                old=math.fsum(v[0]*c for v,c in zip(case['expected'],profile['fraction']))
                self.assertLess(abs(math.fsum(profile['expected'])-old),1e-9)
                for i,value in enumerate(profile['expected']):
                    self.assertGreaterEqual(value,-1e-12)
                    self.assertLessEqual(value,case['expected'][i][1]+1e-9)

    def test_no_flow_is_identity(self):
        n=4;old=[i/32 for i in range(16)]
        self.assertEqual(transport(old,[[1.,1.,0.,0.] for _ in old],[[0.,0.] for _ in old],n),old)

    def test_over_capacity_input_rejected(self):
        with self.assertRaises(ValueError):
            transport([.6,0,0,0],[[.5,.5,0,0] for _ in range(4)],[[0,0] for _ in range(4)],2)
