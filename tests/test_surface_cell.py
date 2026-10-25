import unittest

from experiments.liquid.model import DarcyGrid
from experiments.liquid.capillary import circle_fractions
from experiments.liquid.surface_cell import SurfaceCell


class SurfaceCellTests(unittest.TestCase):
    def test_capillary_evolution_is_conservative_and_bounded(self):
        cell=SurfaceCell(DarcyGrid(32),circle_fractions(32,center=(0.493,0.507)))
        area=sum(cell.fraction)
        speeds=[]
        for _ in range(12):
            result=cell.step(0.01)
            self.assertLessEqual(result['dt'],cell.capillary_step_limit())
            self.assertLess(result['divergence'],1e-10)
            speeds.append(result['max_speed'])
        self.assertLess(speeds[-1],speeds[0])
        self.assertAlmostEqual(sum(cell.fraction),area,places=10)
        self.assertGreaterEqual(min(cell.fraction),-1e-10)
        self.assertLessEqual(max(cell.fraction),1+1e-10)

    def test_failed_geometry_leaves_state_and_time_unchanged(self):
        field=[0.0]*256
        field[8*16+8]=1
        cell=SurfaceCell(DarcyGrid(16),field)
        with self.assertRaises(ValueError):
            cell.step(0.01)
        self.assertEqual(cell.fraction,field)
        self.assertEqual(cell.time,0)

    def test_budget_and_time_scale_are_explicit(self):
        cell=SurfaceCell(DarcyGrid(32),circle_fractions(32))
        with self.assertRaises(RuntimeError):
            cell.advance(1,max_substeps=1)
        self.assertEqual(cell.steps,1)
        self.assertAlmostEqual(cell.time,cell.capillary_step_limit())
        refined=SurfaceCell(DarcyGrid(64),circle_fractions(64))
        self.assertAlmostEqual(refined.capillary_step_limit(),cell.capillary_step_limit()/8)
