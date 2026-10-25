import unittest
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.drainage_resistance import DrainageResistance
from experiments.deposition.contact_particles import advance_contacts,Plane

class DrainageTests(unittest.TestCase):
    def setUp(self):
        self.grid=DarcyGrid(16,circle_mask(16))
        self.grains=[Grain(.488,.5,.012,.04,2.65,1),Grain(.512,.5,.012,.04,2.2,2)]
        self.model=DrainageResistance(self.grid,self.grains)

    def test_nonoverlapping_counterexample_is_passive(self):
        self.model=DrainageResistance(DarcyGrid(32,circle_mask(32)),self.grains)
        f=[-1.,0.,1.,0.]
        v=[sum(a*b for a,b in zip(row,f)) for row in self.model.mobility]
        work=sum(a*b for a,b in zip(f,v))
        self.assertGreater(work,0)
        self.assertAlmostEqual(work,self.model.dissipation(v),places=10)
        self.assertGreater(v[2]-v[0],0)

    def test_mixture_volume_balance_and_reciprocity(self):
        v=[.2,-.3,-.1,.4]
        solid,liquid=self.model.flux(v)
        self.assertGreater(max(map(abs,liquid)),0)
        self.assertLess(max(map(abs,self.grid.divergence([a+b for a,b in zip(solid,liquid)]))),1e-9)
        for i in range(4):
            for j in range(4):self.assertAlmostEqual(self.model.mobility[i][j],self.model.mobility[j][i],places=12)
        hv=[sum(a*b for a,b in zip(row,v)) for row in self.model.resistance]
        self.assertAlmostEqual(sum(a*b for a,b in zip(v,hv)),self.model.dissipation(v),places=12)

    def test_supported_contact_has_no_drainage_then_releases(self):
        wall=[Plane(0,-1,-.512)]
        result=advance_contacts(self.grains,(0,1),.01,wall,mobility_matrix=self.model.mobility)
        speed=[x for pair in result.velocity for x in pair]
        self.assertLess(max(map(abs,speed)),1e-8)
        self.assertLess(self.model.dissipation(speed),1e-15)
        released=advance_contacts(self.grains,(0,-1),.01,wall,mobility_matrix=self.model.mobility)
        for old,new in zip(self.grains,released.grains):
            self.assertLess(new.y,old.y)
            self.assertEqual(new.material,old.material)

    def test_reduced_permeability_increases_required_work(self):
        slow=DrainageResistance(DarcyGrid(16,circle_mask(16),[.1]*256),self.grains)
        v=[0,1,0,1]
        self.assertGreater(slow.dissipation(v),self.model.dissipation(v))
