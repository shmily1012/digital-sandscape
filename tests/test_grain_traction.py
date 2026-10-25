import unittest
from grain_traction_reference import cases, traction_components


class GrainTractionTests(unittest.TestCase):
    def test_population_split_reconstructs_estimator(self):
        for case in cases():
            components=traction_components(case['populations'],case['materials'],case['side'])
            for i in range(len(case['materials'])):
                for axis in range(2):
                    self.assertAlmostEqual(sum(v[i][axis] for v in components.values()),
                                           case['expected'][2*i+axis],places=13)
            if case['name']=='pressure':
                self.assertLess(max(abs(x) for name in ('odd','even')
                                    for pair in components[name] for x in pair),1e-13)
    def test_uniform_pressure_cancels_even_with_partial_contacts(self):
        for case in cases()[:2]:
            self.assertLess(max(abs(x) for x in case['expected']),1e-14)

    def test_flow_and_pressure_gradient_force_directions(self):
        flow,pressure=cases()[2:]
        index=flow['center']*2
        self.assertAlmostEqual(flow['expected'][index],.02,places=12)
        self.assertAlmostEqual(flow['expected'][index+1],0.,places=12)
        self.assertAlmostEqual(pressure['expected'][index],0.,places=12)
        self.assertAlmostEqual(pressure['expected'][index+1],-2*.001/3,places=12)
