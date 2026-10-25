import math
import unittest
from dataclasses import replace
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.disk_volume import disk_rectangle_area,occupancy,face_apertures,swept_flux
from experiments.deposition.drainage_resistance import DrainageResistance

class DiskVolumeTests(unittest.TestCase):
    def setUp(self):
        self.grid=DarcyGrid(32,circle_mask(32))
        self.g=Grain(.473,.517,.071,.04,2.65,1)

    def test_analytic_area_and_quadrants_without_normalization(self):
        r=.17
        self.assertAlmostEqual(disk_rectangle_area(0,0,r,0,0,r,r),math.pi*r*r/4,places=15)
        for n in (16,32,64):
            grid=DarcyGrid(n,circle_mask(n));phi=occupancy(grid,[self.g])
            self.assertAlmostEqual(sum(phi)*grid.h**2,math.pi*self.g.radius**2,places=14)
            self.assertGreaterEqual(min(phi),-1e-13);self.assertLessEqual(max(phi),1+1e-13)

    def test_face_flux_is_derivative_of_geometric_occupancy(self):
        velocity=(.31,-.23);dt=1e-6
        a=occupancy(self.grid,[replace(self.g,x=self.g.x-dt*velocity[0],y=self.g.y-dt*velocity[1])])
        b=occupancy(self.grid,[replace(self.g,x=self.g.x+dt*velocity[0],y=self.g.y+dt*velocity[1])])
        flux=[w*velocity[axis] for w,(_,_,_,axis) in zip(face_apertures(self.grid,self.g),self.grid.faces)]
        error=max(abs((y-x)/(2*dt)+d) for x,y,d in zip(a,b,self.grid.divergence(flux)))
        self.assertLess(error,2e-7)

    def test_finite_rotation_path_preserves_solid_and_liquid(self):
        current=self.g;dt=.1
        for angle in (0,30,45,90,120,180,270,337):
            new=replace(current,x=current.x+.009*math.cos(math.radians(angle)),y=current.y+.009*math.sin(math.radians(angle)))
            old_phi=occupancy(self.grid,[current]);new_phi=occupancy(self.grid,[new])
            solid=swept_flux(self.grid,[current],[new],dt)
            liquid=self.grid.project(solid).liquid
            predicted=[1-a-dt*d for a,d in zip(old_phi,self.grid.divergence(liquid))]
            self.assertLess(max(abs(v-(1-b)) for v,b in zip(predicted,new_phi)),2e-11)
            self.assertAlmostEqual(sum(new_phi),sum(old_phi),places=11)
            current=new

    def test_touching_disks_bounded_and_overlap_rejected(self):
        a=replace(self.g,x=.4,y=.5,radius=.08)
        b=replace(a,x=.56,material=2)
        phi=occupancy(self.grid,[a,b]);self.assertLessEqual(max(phi),1+1e-12)
        with self.assertRaisesRegex(ValueError,'Overlapping'):occupancy(self.grid,[a,replace(b,x=.55)])
        with self.assertRaisesRegex(ValueError,'Overlapping'):DrainageResistance(self.grid,[a,replace(b,x=.55)],geometric=True)
        with self.assertRaises(ValueError):occupancy(self.grid,[replace(a,x=.04)])

    def test_geometric_drainage_energy_and_zero_step(self):
        model=DrainageResistance(self.grid,[self.g],geometric=True)
        f=[.02,-.03];v=[sum(a*b for a,b in zip(row,f)) for row in model.mobility]
        self.assertAlmostEqual(sum(a*b for a,b in zip(f,v)),model.dissipation(v),places=12)
        self.assertEqual(swept_flux(self.grid,[self.g],[self.g],.1),[0.]*len(self.grid.faces))

    def test_flux_reverses_exactly_and_rejects_material_change(self):
        new=replace(self.g,x=.491,y=.502)
        forward=swept_flux(self.grid,[self.g],[new],.1)
        backward=swept_flux(self.grid,[new],[self.g],.1)
        self.assertLess(max(abs(a+b) for a,b in zip(forward,backward)),1e-13)
        with self.assertRaises(ValueError):swept_flux(self.grid,[self.g],[replace(new,material=2)],.1)

    def test_near_tangent_cell_does_not_have_negative_area(self):
        area=disk_rectangle_area(.45,.5,.05,.5,7/16,9/16,.5)
        self.assertGreaterEqual(area,0.)
        self.assertLess(area,1e-15)
        phi=occupancy(DarcyGrid(16,circle_mask(16)),[replace(self.g,x=.45,y=.5,radius=.05)])
        self.assertAlmostEqual(sum(phi)/256,math.pi*.05**2,places=14)
