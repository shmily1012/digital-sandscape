import math
import unittest
from moving_boundary_reference import fixture
from phase_momentum_reference import advance, E
from grain_traction_reference import traction


class MovingBoundaryTests(unittest.TestCase):
    def test_normal_link_correction_has_zero_mass_source_on_fixed_grid(self):
        data=fixture(0.,1);n=data['side'];m=data['materials'];f=data['initial']
        velocity=[(0.,0.) for _ in m]
        velocity[5]=(0.,.001)
        for _ in range(12):
            impulse=traction(f,m,n,True,velocity)
            after,_=advance(f,[0.]*(n*n),m,n,gravity=(0.,0.),sigma=0.,wall_velocity=velocity)
            self.assertAlmostEqual(math.fsum(after[9*i+q] for i in range(n*n) if m[i]==0 for q in range(9)),m.count(0),places=10)
            for axis in (0,1):
                delta=math.fsum((after[9*i+q]-f[9*i+q])*E[q][axis] for i in range(n*n) if m[i]==0 for q in range(9))
                self.assertAlmostEqual(delta+math.fsum(j[axis] for j in impulse),0.,places=12)
            f=after

    def test_wall_impulse_balances_fluid_and_supplies_positive_work(self):
        for speed in (.01,-.01):
            data=fixture(speed,1);m=data['materials'];n=data['side'];f=data['initial']
            uw=list(zip(data['wall_velocity'][::2],data['wall_velocity'][1::2]))
            impulse=traction(f,m,n,True,uw)
            after=data['expected']
            for axis in (0,1):
                delta=math.fsum((after[9*i+q]-f[9*i+q])*E[q][axis]
                                for i in range(n*n) if m[i]==0 for q in range(9))
                self.assertAlmostEqual(delta+math.fsum(j[axis] for j in impulse),0.,places=12)
            work=-math.fsum(j[0]*v[0]+j[1]*v[1] for j,v in zip(impulse,uw))
            self.assertGreater(work,0.)

    def test_tangential_plane_preserves_mass_and_reversal_symmetry(self):
        a,b=fixture(.01,40),fixture(-.01,40)
        n=a['side'];m=a['materials']
        self.assertAlmostEqual(math.fsum(a['expected'][9*i+q] for i in range(n*n)
                                        if m[i]==0 for q in range(9)),m.count(0),places=10)
        for y in range(1,n-1):
            for x in range(1,n-1):
                i=y*n+x;j=y*n+n-1-x
                self.assertAlmostEqual(a['expected_velocity'][2*i],-b['expected_velocity'][2*j],places=12)
                self.assertAlmostEqual(a['expected_velocity'][2*i+1],b['expected_velocity'][2*j+1],places=12)

    def test_zero_velocity_is_stationary_operator(self):
        data=fixture(0.,1)
        baseline,_=advance(data['initial'],[0.]*(data['side']**2),data['materials'],data['side'],gravity=(0.,0.),sigma=0.)
        self.assertEqual(data['expected'],baseline)
