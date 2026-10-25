import math
import unittest
from grain_volume_reference import fixtures


class GrainVolumeTests(unittest.TestCase):
    def test_projected_flow_respects_capacity_and_impermeable_faces(self):
        for case in fixtures():
            if not case['valid']:continue
            n=case['side'];q=case['fluid_flux'];g=case['expected']
            for i in range(n*n):
                divergence=sum(q[i])-(q[i-1][0] if i%n else 0)-(q[i-n][1] if i>=n else 0)
                self.assertLess(abs(g[i][1]-g[i][0]+divergence),1e-10)
                for axis in range(2):
                    if case['aperture'][i][axis]==0:self.assertEqual(q[i][axis],0.)

    def test_endpoint_continuity_for_every_cell(self):
        for case in fixtures():
            n=case['side'];g=case['expected']
            for i,row in enumerate(g):
                divergence=row[2]+row[3]-(g[i-1][2] if i%n else 0)-(g[i-n][3] if i>=n else 0)
                self.assertLess(abs(row[1]-row[0]-divergence),1e-13,case['name'])
            self.assertLess(abs(math.fsum(r[0]-r[1] for r in g)),1e-12)

    def test_capacity_and_wall_overlap_detection(self):
        for case in fixtures():
            negative=min(r[1] for r in case['expected']) < -5e-6
            self.assertEqual(negative,not case['valid'])
            if case['valid']:
                self.assertTrue(all(-1e-12<=r[k]<=1 for r in case['expected'] for k in (0,1)))

    def test_chain_exchanges_capacity_locally_not_whole_packets(self):
        case=next(c for c in fixtures() if c['name']=='twenty-grain-chain')
        n=case['side'];g=case['expected']
        self.assertAlmostEqual(g[3*n+16][1]-g[3*n+16][0],.02,places=13)
        self.assertAlmostEqual(g[23*n+16][1]-g[23*n+16][0],-.02,places=13)
        for y in range(4,23):
            self.assertAlmostEqual(g[y*n+16][0],0.,places=13)
            self.assertAlmostEqual(g[y*n+16][1],0.,places=13)
        self.assertLessEqual(max(abs(r[k]) for r in g for k in (2,3)),.02000000001)
