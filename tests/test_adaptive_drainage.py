import unittest
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.adaptive_drainage import advance_drainage,DrainageBudgetError

class AdaptiveDrainageTests(unittest.TestCase):
    def setUp(self):
        self.grid=DarcyGrid(16,circle_mask(16))
        self.grains=[Grain(.473,.517,.071,.04,2.65,1)]

    def test_subdivides_with_fixed_elapsed_time_and_volume(self):
        result=advance_drainage(self.grid,self.grains,(0,1),.04,flux_tolerance=.005,max_substeps=32)
        self.assertGreater(result.substeps,1)
        self.assertEqual(result.resistance_builds,result.substeps)
        self.assertLess(result.resistance_builds,result.attempts)
        self.assertLessEqual(result.attempts,2*32-1)
        self.assertAlmostEqual(result.elapsed,.04,places=15)
        self.assertLessEqual(result.maximum_flux_error,.005)
        self.assertLess(result.volume_residual,1e-9)
        self.assertEqual(result.grains[0].material,self.grains[0].material)
        self.assertGreater(result.grains[0].y,self.grains[0].y)

    def test_budget_failure_keeps_input(self):
        original=list(self.grains)
        with self.assertRaises(DrainageBudgetError):
            advance_drainage(self.grid,self.grains,(0,1),.04,flux_tolerance=1e-9,max_substeps=1)
        self.assertEqual(self.grains,original)

    def test_zero_force_and_invalid_budget(self):
        result=advance_drainage(self.grid,self.grains,(0,0),.04)
        self.assertEqual(result.grains,self.grains)
        self.assertEqual(result.substeps,1)
        self.assertEqual(result.maximum_flux_error,0)
        for budget in (0,65):
            with self.assertRaises(ValueError):advance_drainage(self.grid,self.grains,(0,1),.04,max_substeps=budget)

    def test_failure_after_accepted_half_is_transactional(self):
        from unittest.mock import patch
        from experiments.deposition import adaptive_drainage as module
        real_contacts=module.advance_contacts
        real_flux=module.DrainageResistance.flux
        calls=[]
        flux_calls=[]
        original=list(self.grains)
        def contact(*args,**kwargs):
            calls.append(args[2])
            if len(calls)==3:raise module.ContactConvergenceError('Injected second-half failure')
            return real_contacts(*args,**kwargs)
        def flux(model,velocity):
            solid,liquid=real_flux(model,velocity)
            flux_calls.append(1)
            if len(flux_calls)==1:liquid=[v+1000 for v in liquid]
            return solid,liquid
        with patch.object(module,'advance_contacts',side_effect=contact), patch.object(module.DrainageResistance,'flux',flux):
            with self.assertRaises(DrainageBudgetError):
                module.advance_drainage(self.grid,self.grains,(0,1),.04,flux_tolerance=10,max_substeps=2)
        self.assertEqual(calls,[.04,.02,.02])
        self.assertEqual(len(flux_calls),2)
        self.assertEqual(self.grains,original)
