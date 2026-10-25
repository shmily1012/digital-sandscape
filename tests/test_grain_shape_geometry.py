"""Geometry checks only; round-grain pressure connectivity is not accepted."""
import math
import unittest
from grain_volume_reference import occupancy, geometry, apertures


class GrainShapeGeometryTests(unittest.TestCase):
    def test_disk_area_and_swept_volume(self):
        n=8;m=[0]*(n*n);m[27]=2
        o=[[0.,0.] for _ in m];v=[[0.,0.] for _ in m]
        o[27]=[.13,-.27];v[27]=[.02,-.01]
        self.assertAlmostEqual(sum(occupancy(m,o,n,'disk')),math.pi/4,places=12)
        data=geometry(m,o,v,n,.1,'disk')
        for i,row in enumerate(data):
            divergence=row[2]+row[3]-(data[i-1][2] if i%n else 0)-(data[i-n][3] if i>=n else 0)
            self.assertLess(abs(row[1]-row[0]-.1*divergence),1e-12)

    def test_wall_geometry_does_not_become_round(self):
        n=8;m=[int(i%n in (0,n-1) or i//n in (0,n-1)) for i in range(n*n)]
        o=[[0.,0.] for _ in m];v=[[0.,0.] for _ in m]
        self.assertEqual(geometry(m,o,v,n,1.,'disk'),geometry(m,o,v,n))
        self.assertEqual(apertures(m,o,v,n,1.,'disk'),apertures(m,o,v,n))

    def test_tangent_disk_face_opening_is_continuous(self):
        n=8;m=[0]*(n*n);m[27]=2
        o=[[0.,0.] for _ in m];v=[[0.,0.] for _ in m]
        baseline=apertures(m,o,v,n,.1,'disk')
        v[27][0]=1e-7
        shifted=apertures(m,o,v,n,.1,'disk')
        error=max(abs(a-b) for old,new in zip(baseline,shifted) for a,b in zip(old,new))
        self.assertLess(error,1.1e-4)
