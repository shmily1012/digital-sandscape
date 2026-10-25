import unittest
from grain_displacement_reference import fixtures, joint_fixtures, forced_fixtures, coupled_fixtures

class GrainDisplacementTests(unittest.TestCase):
    def test_translation_conserves_packets(self):
        for case in fixtures():
            initial=case['materials']
            for frame in case['frames']:
                self.assertEqual(sorted(frame['sources']),list(range(len(initial))))
                self.assertEqual(sorted(frame['materials']),sorted(initial))
        for case in fixtures()[:4]:
            self.assertTrue(all(f['accepted'] for f in case['frames']))
            self.assertNotEqual(case['frames'][-1]['materials'],case['materials'])

    def test_constraints_reject(self):
        for case in fixtures()[4:]:
            self.assertFalse(case['frames'][-1]['accepted'],case['name'])

    def test_gap_is_traversed_before_wall_stops_grain(self):
        case=joint_fixtures()[0];a=3*case['side']+2
        self.assertEqual(case['frames'][0]['offset'][a],[-.0625,0.])
        self.assertEqual(case['frames'][1]['offset'][a],[0.,0.])
        self.assertEqual(case['frames'][2]['velocity'][a],[0.,0.])
        self.assertTrue(all(f['accepted'] for f in case['frames']))

    def test_rejected_motion_does_not_publish_contact_velocity(self):
        case=joint_fixtures()[2];frame=case['frames'][0]
        self.assertFalse(frame['accepted'])
        self.assertEqual(frame['velocity'],case['velocity'])
        self.assertEqual(frame['offset'],case['initial_offset'])
        self.assertTrue(all(v==[0.,0.] for v in frame['reaction']))

    def test_near_corner_clearance_and_overlap_are_distinct(self):
        cases=joint_fixtures()
        self.assertTrue(all(frame['accepted'] for frame in cases[3]['frames']))
        self.assertFalse(cases[4]['frames'][0]['accepted'])

    def test_fluid_and_grain_impulses_balance(self):
        from phase_momentum_reference import E
        from grain_contact_impulse_reference import MASS
        for case in forced_fixtures():
            frame=case['frames'][0]
            for axis in range(2):
                total=0.
                for i,m in enumerate(case['materials']):
                    if m==0:
                        total+=sum((case['fluid_next'][9*i+q]-case['populations'][9*i+q])*e[axis] for q,e in enumerate(E))
                    elif m==1:total+=case['raw_impulse'][i][axis]+frame['reaction'][i][axis]
                    else:total+=MASS[m]*(frame['velocity'][i][axis]-case['velocity'][i][axis])-(MASS[m]-1)*case['gravity'][axis]
                self.assertAlmostEqual(total,0.,places=10,msg=case['name'])

    def test_coupled_state_and_clock_commit_together(self):
        for case in coupled_fixtures():
            initial=case['initial']
            for frame in case['frames']:
                self.assertEqual(sorted(frame['materials']),sorted(initial['materials']))
                self.assertAlmostEqual(sum(frame['phase']),sum(initial['phase']),places=10)
            if case['name']=='coupled-reject':
                frame=case['frames'][0]
                self.assertEqual(frame['ticks'],0)
                for key in ('materials','phase','populations','velocity','offset'):
                    self.assertEqual(frame[key],initial[key])
            else:self.assertEqual(case['frames'][-1]['ticks'],12)
