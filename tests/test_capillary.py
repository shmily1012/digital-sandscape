import unittest
import math

from experiments.liquid.model import DarcyGrid
from experiments.liquid.capillary import circle_fractions,height_curvature,capillary_flux,split_capillary_pressure,extend_curvature


class CapillaryTests(unittest.TestCase):
    def test_extension_uses_only_original_donors_and_rejects_conflicts(self):
        n=12
        fraction=[0.5]*(n*n)
        raw=[None]*(n*n)
        raw[5*n+4]=4.9
        raw[5*n+6]=5.1
        result=extend_curvature(n,fraction,raw)
        self.assertAlmostEqual(result[5*n+5],5)
        self.assertIsNone(result[9*n+5])
        self.assertIsNone(raw[5*n+5])
        raw[5*n+6]=-5.1
        self.assertIsNone(extend_curvature(n,fraction,raw)[5*n+5])

    def test_near_pure_noise_does_not_destroy_height_or_change_state(self):
        n=32
        field=[min(1,max(0,y-15.3)) for y in range(n) for x in range(n)]
        for x in range(n):
            field[19*n+x]=1-5.96e-8
        original=list(field)
        curvature=height_curvature(n,field)
        self.assertIsNotNone(curvature[16*n+16])
        self.assertLess(abs(curvature[16*n+16]),1e-10)
        self.assertEqual(field,original)

    def test_substantial_second_interface_is_rejected(self):
        n=32
        field=[min(1,max(0,y-15.3)) for y in range(n) for x in range(n)]
        for x in range(n):
            field[19*n+x]=0.9
        self.assertIsNone(height_curvature(n,field)[16*n+16])

    def test_pressure_split_preserves_original_equation(self):
        grid=DarcyGrid(32)
        fraction=circle_fractions(32,center=(0.493,0.507))
        curvature=height_curvature(32,fraction)
        full=grid.project(capillary_flux(grid,fraction,curvature,0.01))
        base,residual=split_capillary_pressure(grid,fraction,curvature,0.01)
        split=grid.project(residual)
        self.assertLess(max(abs(a-b) for a,b in zip(full.mixture,split.mixture)),1e-10)
        difference=[p-b-d for p,b,d in zip(full.pressure,base,split.pressure)]
        gauge=sum(difference)/len(difference)
        self.assertLess(max(abs(v-gauge) for v in difference),1e-10)

    def test_circle_initial_area_is_analytic(self):
        for n in (16,32,64):
            values=circle_fractions(n,center=(0.493,0.507))
            self.assertAlmostEqual(sum(values)/(n*n),math.pi*0.2**2,places=12)

    def test_estimated_curvature_spurious_flow_decreases(self):
        speeds=[]
        errors=[]
        for n in (32,64):
            grid=DarcyGrid(n)
            fraction=circle_fractions(n,center=(0.493,0.507))
            curvature=height_curvature(n,fraction)
            solution=grid.project(capillary_flux(grid,fraction,curvature,0.01))
            speeds.append(max(map(abs,solution.mixture)))
            inside=[p for p,c in zip(solution.pressure,fraction) if c>0.999]
            outside=[p for p,c in zip(solution.pressure,fraction) if c<0.001]
            jump=sum(inside)/len(inside)-sum(outside)/len(outside)
            errors.append(abs(jump-0.05)/0.05)
        self.assertLess(speeds[1],speeds[0]*0.4)
        self.assertLess(errors[1],0.01)
        self.assertLess(errors[1],errors[0]*0.4)

    def test_constant_curvature_laplace_balance(self):
        grid=DarcyGrid(24)
        fraction=circle_fractions(24)
        tension,radius=0.01,0.2
        imposed=capillary_flux(grid,fraction,[1/radius]*576,tension)
        solution=grid.project(imposed)
        inside=[p for p,c in zip(solution.pressure,fraction) if c>0.999]
        outside=[p for p,c in zip(solution.pressure,fraction) if c<0.001]
        jump=sum(inside)/len(inside)-sum(outside)/len(outside)
        self.assertAlmostEqual(jump,tension/radius,places=9)
        self.assertLess(max(map(abs,solution.mixture)),1e-10)

    def test_planar_height_curvature(self):
        n=24
        fraction=[min(1,max(0,(y+1)-11.3)) for y in range(n) for x in range(n)]
        curvature=height_curvature(n,fraction)
        resolved=[v for v in curvature if v is not None]
        self.assertTrue(resolved)
        self.assertLess(max(map(abs,resolved)),1e-10)

    def test_circle_height_error_decreases_with_resolution(self):
        errors=[]
        for n in (32,64):
            fraction=circle_fractions(n,center=(0.493,0.507))
            curvature=height_curvature(n,fraction)
            interface=[k for k,c in zip(curvature,fraction) if 1e-5<c<1-1e-5]
            self.assertTrue(all(k is not None for k in interface))
            errors.append(sum(abs(k-5) for k in interface)/len(interface))
        self.assertLess(errors[1],errors[0]*0.5)

    def test_unresolved_geometry_is_not_silently_zero_force(self):
        grid=DarcyGrid(8)
        fraction=[0.0]*64
        fraction[27]=1
        with self.assertRaises(ValueError):
            capillary_flux(grid,fraction,[None]*64,0.01)
        self.assertEqual(capillary_flux(grid,fraction,[None]*64,0),[0.0]*len(grid.faces))
