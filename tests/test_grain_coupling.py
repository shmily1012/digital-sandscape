import math
import unittest
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain,spread,sample,advance,forces,calibrate_self_response

class GrainCouplingTests(unittest.TestCase):
    def test_isolated_speed_is_grid_independent_after_self_correction(self):
        g=Grain(.473,.521,.012,.04,2.65,1)
        gravity=(.6,.8)
        f=forces([g],gravity)[0]
        for n in (16,32,64):
            state,_,_=advance(DarcyGrid(n,circle_mask(n)),[g],gravity,.01)
            self.assertAlmostEqual((state[0].x-g.x)/.01,f[0]/g.drag,places=9)
            self.assertAlmostEqual((state[0].y-g.y)/.01,f[1]/g.drag,places=9)

    def test_other_grain_flow_is_not_subtracted(self):
        g=Grain(.42,.43,.012,.04,2.65,1)
        h=Grain(.58,.43,.01,.03,2.2,2)
        alone,_,_=advance(self.grid,[g],(0,1),.01)
        pair,_,_=advance(self.grid,[g,h],(0,1),.01)
        self.assertGreater(abs(pair[0].y-alone[0].y),1e-7)

    def test_dense_configuration_with_negative_mobility_is_rejected(self):
        grid=DarcyGrid(32,circle_mask(32))
        g=Grain(.5,.5,.012,.04,2.65,1)
        with self.assertRaisesRegex(ValueError,'positive definite'):
            calibrate_self_response(grid,[g,g])

    def setUp(self):
        self.grid=DarcyGrid(16,circle_mask(16))
        self.grains=[Grain(0.42,0.43,0.012,0.04,2.65,1),Grain(0.58,0.43,0.01,0.03,2.2,2),Grain(0.5,0.6,0.014,0.05,1.8,3)]

    def test_force_conservation_and_reciprocal_work(self):
        grid=self.grid
        source,w,force=spread(grid,self.grains,(0.6,0.8))
        velocity=[math.sin(i*0.37) for i in range(len(grid.faces))]
        sampled=sample(grid,w,velocity)
        for axis in range(2):
            deposited=sum(q*grid.h**2/m for q,(_,_,m,a) in zip(source,grid.faces) if a==axis)
            self.assertAlmostEqual(deposited,sum(f[axis] for f in force),places=12)
        particle_work=sum(sum(a*b for a,b in zip(f,u)) for f,u in zip(force,sampled))
        grid_work=sum(q*u*grid.h**2/m for q,u,(_,_,m,a) in zip(source,velocity,grid.faces))
        self.assertAlmostEqual(particle_work,grid_work,places=12)

    def test_projected_carrier_has_positive_dissipation(self):
        grid=self.grid
        source,w,force=spread(grid,self.grains,(0,1))
        p=grid.project(source)
        carrier=sample(grid,w,p.mixture)
        work=sum(sum(a*b for a,b in zip(f,u)) for f,u in zip(force,carrier))
        dissipation=sum(u*u*grid.h**2/m for u,(_,_,m,a) in zip(p.mixture,grid.faces))
        self.assertGreater(work,0)
        self.assertAlmostEqual(work,dissipation,places=10)

    def test_rotation_changes_motion_and_preserves_identity(self):
        down,_,_=advance(self.grid,self.grains,(0,1),0.01)
        up,_,_=advance(self.grid,self.grains,(0,-1),0.01)
        for old,a,b in zip(self.grains,down,up):
            self.assertGreater(a.y,old.y)
            self.assertLess(b.y,old.y)
            self.assertEqual((a.radius,a.drag,a.density,a.material),(old.radius,old.drag,old.density,old.material))

    def test_wall_candidate_rejected_without_mutation(self):
        grains=[Grain(0.5,0.94,0.01,0.00001,2.65,1)]
        original=list(grains)
        with self.assertRaises(ValueError):advance(self.grid,grains,(0,1),1)
        self.assertEqual(grains,original)

    def test_touching_nonoverlapping_grains_can_invalidate_self_correction(self):
        from experiments.liquid.grain_coupling import carrier_response
        grid=DarcyGrid(32,circle_mask(32))
        grains=[Grain(.488,.5,.012,.04,2.65,1),Grain(.512,.5,.012,.04,2.2,2)]
        self.assertGreaterEqual(grains[1].x-grains[0].x,grains[0].radius+grains[1].radius)
        raw=carrier_response(grid,grains)
        direction=[-1.,0.,1.,0.]
        raw_work=sum(direction[i]*sum(raw[i][j]*direction[j] for j in range(4)) for i in range(4))
        corrected=[list(row) for row in raw]
        for i,g in enumerate(grains):
            for a in range(2):
                for b in range(2):corrected[2*i+a][2*i+b]=1/g.drag if a==b else 0.
        corrected_work=sum(direction[i]*sum(corrected[i][j]*direction[j] for j in range(4)) for i in range(4))
        self.assertGreater(raw_work,0.)
        self.assertLess(corrected_work,-1.)
        with self.assertRaisesRegex(ValueError,'positive definite'):calibrate_self_response(grid,grains)
