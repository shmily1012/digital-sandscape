import math, unittest
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain,advance
from experiments.deposition.contact_particles import advance_contacts,Plane
from experiments.deposition.coupled_contacts import advance_coupled

class CoupledContactTests(unittest.TestCase):
    def setUp(self):self.grid=DarcyGrid(16,circle_mask(16))
    def test_diagonal_mobility_recovers_local_contact_model(self):
        g=[Grain(.45,.5,.025,.02,2.65,1),Grain(.5,.5,.025,.03,2.2,2)]
        matrix=[[0.]*4 for _ in range(4)]
        for i,grain in enumerate(g):matrix[2*i][2*i]=matrix[2*i+1][2*i+1]=1/grain.drag
        a=advance_contacts(g,(1,0),.05)
        b=advance_contacts(g,(1,0),.05,mobility_matrix=matrix)
        for x,y in zip(a.grains,b.grains):self.assertLess(math.dist((x.x,x.y),(y.x,y.y)),1e-12)
    def test_supported_grain_stops_driving_carrier_and_flip_releases_it(self):
        g=[Grain(.5,.5,.025,.002,2.65,1)]
        planes=[Plane(0,-1,-.525)]
        rested=advance_coupled(self.grid,g,(0,1),.01,planes)
        self.assertLess(max(map(abs,rested.projection.mixture)),1e-10)
        self.assertLess(math.hypot(*rested.net_forces[0]),1e-10)
        self.assertLess(math.dist(rested.contact.velocity[0],(0,0)),1e-10)
        released=advance_coupled(self.grid,rested.contact.grains,(0,-1),.01,planes)
        self.assertLess(released.contact.grains[0].y,g[0].y)
        self.assertGreater(max(map(abs,released.projection.mixture)),1e-6)
        self.assertEqual(released.contact.grains[0].material,1)
    def test_free_limit_matches_dilute_reference(self):
        grains=[Grain(.42,.43,.012,.04,2.65,1),Grain(.58,.43,.01,.03,2.2,2)]
        expected,_,_=advance(self.grid,grains,(.6,.8),.01)
        result=advance_coupled(self.grid,grains,(.6,.8),.01)
        for a,b in zip(expected,result.contact.grains):self.assertLess(math.dist((a.x,a.y),(b.x,b.y)),1e-9)
        self.assertLess(result.mobility_error,1e-8)
        self.assertLess(result.spread_force_error,1e-12)
        self.assertLess(result.reciprocal_work_error,1e-12)
    def test_contact_feedback_is_included_in_carrier_force(self):
        grains=[Grain(.475,.5,.025,.002,2.65,1),Grain(.525,.5,.025,.002,2.2,2)]
        result=advance_coupled(self.grid,grains,(.6,.8),.01,[Plane(0,-1,-.525)],friction=.5)
        self.assertGreater(sum(c[5] for c in result.contact.reactions),0)
        self.assertLess(result.mobility_error,1e-8)
        self.assertLess(result.spread_force_error,1e-12)
        self.assertLess(result.reciprocal_work_error,1e-12)
        self.assertLessEqual(result.contact.friction_power,1e-10)
        for g in result.contact.grains:self.assertLessEqual(g.y+g.radius,.525+1e-9)
    def test_nonreciprocal_or_indefinite_mobility_rejected(self):
        g=[Grain(.5,.5,.025,.02,2.65,1)]
        for matrix in ([[1,2],[0,1]],[[1,2],[2,1]],[[math.nan,0],[0,1]]):
            with self.assertRaises(ValueError):advance_contacts(g,(0,1),.01,mobility_matrix=matrix)
        self.assertEqual(g[0].y,.5)

    def test_continuous_settle_then_flip_preserves_state(self):
        grains=[Grain(.475,.46,.025,.002,2.65,1),Grain(.525,.46,.025,.002,2.2,2)]
        identities=[(g.radius,g.drag,g.density,g.material) for g in grains]
        plane=[Plane(0,-1,-.525)]
        at_flip=None
        for step in range(80):
            gravity=(0,1) if step<60 else (0,-1)
            result=advance_coupled(self.grid,grains,gravity,.005,plane)
            self.assertLess(result.mobility_error,1e-8)
            self.assertLess(max(map(abs,self.grid.divergence(result.projection.mixture))),1e-7)
            grains=result.contact.grains
            self.assertEqual([(g.radius,g.drag,g.density,g.material) for g in grains],identities)
            self.assertGreaterEqual(math.dist((grains[0].x,grains[0].y),(grains[1].x,grains[1].y)),.05-1e-9)
            if step==59:
                at_flip=[g.y for g in grains]
                self.assertTrue(all(abs(g.y-.5)<1e-7 for g in grains))
        self.assertTrue(all(g.y<y-.005 for g,y in zip(grains,at_flip)))
