import unittest
from unittest.mock import patch
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.contact_particles import Plane,ContactConvergenceError
from experiments.deposition.operator_history import advance_operator_history
from experiments.deposition.adaptive_history import advance_history_interval
from experiments.deposition.adaptive_drainage import DrainageBudgetError
from experiments.deposition.tangential_history import snapshot

class AdaptiveHistoryTests(unittest.TestCase):
    def setUp(self):
        self.grid=DarcyGrid(16,circle_mask(16));self.ids=[10]
        g=[Grain(.473,.517,.071,.04,2.65,1)]
        self.kw=dict(planes=[Plane(0,-1,-.588)],plane_ids=[-1],stiffness=.1)
        a=advance_operator_history(self.grid,g,self.ids,{},(.4,1),.01,**self.kw).candidate
        self.grains=a.contact.grains;self.history=a.history

    def test_subdivision_matches_explicit_replay_of_accepted_steps(self):
        result=advance_history_interval(self.grid,self.grains,self.ids,self.history,(1,1),.04,flux_tolerance=.005,max_substeps=64,**self.kw)
        self.assertGreater(len(result.accepted_steps),1)
        grains=self.grains;history=self.history
        for dt in result.accepted_steps:
            a=advance_operator_history(self.grid,grains,self.ids,history,(1,1),dt,**self.kw).candidate
            grains=a.contact.grains;history=a.history
        self.assertEqual(result.grains,grains);self.assertEqual(result.history,history)
        self.assertAlmostEqual(result.elapsed,.04,places=15)
        self.assertLessEqual(result.attempts,127)
        self.assertLess(result.volume_error,1e-9);self.assertLess(result.energy_error,1e-9)

    def test_failure_after_partial_progress_preserves_all_inputs(self):
        from experiments.deposition import adaptive_history as module
        real=module.advance_operator_history;calls=[];saved=snapshot(self.history);original=list(self.grains)
        def injected(*args,**kwargs):
            calls.append(args[5])
            if len(calls) in (1,3):raise ContactConvergenceError('Injected refusal')
            return real(*args,**kwargs)
        with patch.object(module,'advance_operator_history',side_effect=injected):
            with self.assertRaises(DrainageBudgetError):
                module.advance_history_interval(self.grid,self.grains,self.ids,self.history,(1,1),.04,max_substeps=2,flux_tolerance=10,**self.kw)
        self.assertEqual(calls,[.04,.02,.02]);self.assertEqual(snapshot(self.history),saved);self.assertEqual(self.grains,original)
