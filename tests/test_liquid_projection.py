import math
import unittest

from experiments.liquid.model import DarcyGrid, circle_mask


class LiquidProjectionTests(unittest.TestCase):
    def test_sealed_circle_local_and_global_volume_balance(self):
        grid = DarcyGrid(24, circle_mask(24))
        flux = grid.prescribed_patch()
        result = grid.project(flux)
        self.assertLess(result.residual, 1e-10)
        self.assertAlmostEqual(sum(grid.divergence(flux)), 0, places=12)
        for axis in (0, 1):
            # Sealed domain requires zero net mixture flux across every cut.
            for cut in range(23):
                crossing = [k for k, (i, _, _, a) in enumerate(grid.faces)
                            if a == axis and (i%24 if axis == 0 else i//24) == cut]
                self.assertAlmostEqual(sum(result.mixture[k] for k in crossing), 0, places=10)
        self.assertLess(sum(v for v, face in zip(result.liquid, grid.faces) if face[3] == 1), 0)

    def test_manufactured_pressure_removed_gradient(self):
        grid = DarcyGrid(16, mobility=[1+0.5*math.sin(i) for i in range(256)])
        expected = [math.cos((i%16+0.5)*math.pi/16)*math.cos((i//16+0.5)*math.pi/16) for i in range(256)]
        imposed = [-v for v in grid.liquid_flux(expected)]
        result = grid.project(imposed)
        difference = [a-b for a, b in zip(result.pressure, expected)]
        mean = sum(difference)/len(difference)
        self.assertLess(max(abs(v-mean) for v in difference), 1e-10)
        self.assertLess(max(map(abs, result.mixture)), 1e-10)

    def test_reversal_and_mobility_scaling(self):
        grid = DarcyGrid(16)
        flux = grid.prescribed_patch(velocity=(0.08, -0.04))
        forward, reverse = grid.project(flux), grid.project([-v for v in flux])
        slower = DarcyGrid(16, mobility=[0.5]*256).project(flux)
        for p, r, s in zip(forward.pressure, reverse.pressure, slower.pressure):
            self.assertAlmostEqual(p, -r, places=12)
            self.assertAlmostEqual(2*p, s, places=12)

    def test_projection_reduces_weighted_flux_energy(self):
        grid = DarcyGrid(20, circle_mask(20))
        flux = grid.prescribed_patch(velocity=(0.1, 0.07))
        result = grid.project(flux)
        energy = lambda values: sum(v*v/f[2] for v, f in zip(values, grid.faces))
        self.assertLess(energy(result.mixture), energy(flux))
        self.assertLess(abs(sum(a*b/f[2] for a, b, f in zip(result.liquid, result.mixture, grid.faces))), 1e-10)

    def test_zero_flux_and_disconnected_regions(self):
        active = [i%12 != 6 for i in range(144)]
        grid = DarcyGrid(12, active)
        self.assertEqual(grid.project([0]*len(grid.faces)).iterations, 0)
        self.assertLess(grid.project(grid.prescribed_patch(radius=0.35)).residual, 1e-10)

    def test_nonconvergence_and_invalid_inputs_are_reported(self):
        grid = DarcyGrid(16)
        with self.assertRaises(RuntimeError):
            grid.project(grid.prescribed_patch(), max_iterations=1)
        with self.assertRaises(ValueError):
            DarcyGrid(16, mobility=[0]*256)
        with self.assertRaises(ValueError):
            grid.project([float('nan')]*len(grid.faces))
