import unittest
from grain_load_reference import loads, fixture


class GrainLoadTests(unittest.TestCase):
    def test_all_weight_reaches_fluid_or_wall_at_arbitrary_angles(self):
        data=fixture()
        for case in data['cases'][:-1]:
            terminal=sum(v for i,v in enumerate(case['expected']) if data['materials'][i]<2)
            self.assertAlmostEqual(terminal,data['total_weight'],places=10)
        self.assertEqual(data['cases'][-1]['expected'],[0.]*(data['side']**2))

    def test_stack_transmits_to_fluid_and_floor_absorbs_load(self):
        n=8;m=[0]*(n*n)
        for y in (2,3,4):m[y*n+3]=2
        result=loads(m,n,(0.,1.))
        self.assertEqual(result[5*n+3],6.)
        self.assertEqual(result[6*n+3],0.)
        m[5*n+3]=1
        result=loads(m,n,(0.,1.))
        self.assertEqual(sum(v for i,v in enumerate(result) if m[i]==0),0.)
        self.assertEqual(result[5*n+3],6.)

    def test_removed_top_grain_reduces_terminal_load(self):
        n=8;m=[0]*(n*n)
        for y in (2,3,4):m[y*n+3]=2
        before=loads(m,n,(0.,1.))[5*n+3]
        m[2*n+3]=0
        self.assertEqual(loads(m,n,(0.,1.))[5*n+3],before-2.)
