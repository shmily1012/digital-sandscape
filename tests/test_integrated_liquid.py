import unittest
from collections import Counter
from liquid_reference import liquid_initial,liquid_step
class IntegratedLiquidTests(unittest.TestCase):
 def test_gas_changes_release_without_losing_inventory(self):
  n=64;gas=liquid_initial(n,709);initial=gas.copy();water=[0 if m==5 else m for m in gas]
  for tick in range(300):
   liquid_step(gas,n,709,tick,(0,32767));liquid_step(water,n,709,tick,(0,32767))
  self.assertEqual(Counter(gas),Counter(initial))
  self.assertTrue(all(gas[i]==4 for i,m in enumerate(initial) if m==4))
  released=lambda a:sum(1 for i,m in enumerate(a) if 1<=m<=3 and i//n>40)
  self.assertLess(released(gas),released(water))
  gas_height=lambda a:sum(i//n for i,m in enumerate(a) if m==5)/a.count(5)
  self.assertLess(gas_height(gas),gas_height(initial))
 def test_unsupported_vertical_grain_does_not_wander(self):
  n=64;cells=[0]*(n*n);cells[8*n+32]=1
  for tick in range(50):liquid_step(cells,n,709,tick,(0,32767))
  self.assertEqual(cells.count(1),1)
  index=cells.index(1)
  self.assertEqual(index%n,32)
  self.assertGreater(index//n,8)
if __name__=='__main__':unittest.main()
