import math
import unittest

from experiments.liquid.model import DarcyGrid
from experiments.liquid.capillary import circle_fractions
from experiments.liquid.geometric_transport import advect,reconstruct_polygons,polygon_area


def periodic_grid(n):
    grid=DarcyGrid(n)
    grid.faces=[]
    for y in range(n):
        for x in range(n):
            i=y*n+x
            grid.faces.extend(((i,y*n+(x+1)%n,1,0),(i,((y+1)%n)*n+x,1,1)))
    return grid


class GeometricTransportTests(unittest.TestCase):
    def test_reconstruction_preserves_cell_areas(self):
        grid=DarcyGrid(24)
        values=circle_fractions(24,center=(0.493,0.507))
        polygons=reconstruct_polygons(grid,values)
        self.assertLess(max(abs(c-polygon_area(p)) for c,p in zip(values,polygons)),1e-12)

    def test_diagonal_transport_conserves_area_and_bounds(self):
        grid=periodic_grid(20)
        values=circle_fractions(20,radius=0.15,center=(0.43,0.47))
        area=sum(values)
        velocity=[0.2 if f[3]==0 else 0.15 for f in grid.faces]
        for _ in range(25):
            values,dt=advect(grid,values,velocity,0.05)
            self.assertGreater(dt,0)
            self.assertGreaterEqual(min(values),-1e-12)
            self.assertLessEqual(max(values),1+1e-12)
        self.assertAlmostEqual(sum(values),area,places=10)

    def test_exact_translation_less_diffusive_than_upwind(self):
        grid=periodic_grid(20)
        initial=circle_fractions(20,radius=0.15,center=(0.3,0.5))
        expected=circle_fractions(20,radius=0.15,center=(0.5,0.5))
        velocity=[0.2 if f[3]==0 else 0 for f in grid.faces]
        errors=[]
        for geometric in (False,True):
            values=initial.copy()
            for _ in range(20):
                values,dt=advect(grid,values,velocity,0.05,geometric)
                self.assertAlmostEqual(dt,0.05)
            errors.append(sum(abs(a-b) for a,b in zip(values,expected))/400)
        self.assertLess(errors[1],errors[0]*0.5)

    def test_sealed_zero_flow_is_identity(self):
        grid=DarcyGrid(16)
        values=circle_fractions(16)
        actual,dt=advect(grid,values,[0]*len(grid.faces),1)
        self.assertEqual(actual,values)
        self.assertEqual(dt,1)

    def test_invalid_volume_velocity_is_rejected(self):
        grid=DarcyGrid(16)
        values=circle_fractions(16)
        with self.assertRaises(ValueError):
            advect(grid,values,[0.1]*len(grid.faces),0.1)
