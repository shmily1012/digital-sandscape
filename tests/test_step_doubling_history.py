import unittest
from unittest.mock import patch
from experiments.liquid.model import DarcyGrid,circle_mask
from experiments.liquid.grain_coupling import Grain
from experiments.deposition.contact_particles import Plane,ContactConvergenceError
from experiments.deposition.operator_history import advance_operator_history
from experiments.deposition.step_doubling_history import advance_doubled
from experiments.deposition.adaptive_drainage import DrainageBudgetError
from experiments.deposition.tangential_history import snapshot

class StepDoublingTests(unittest.TestCase):
    def setUp(self):
        self.grid=DarcyGrid(16,circle_mask(16));self.ids=[10]
        self.kw=dict(planes=[Plane(0,-1,-.588)],plane_ids=[-1],stiffness=.1)
        a=advance_operator_history(self.grid,[Grain(.473,.517,.071,.04,2.65,1)],self.ids,{},(.4,1),.01,**self.kw).candidate
        self.grains=a.contact.grains;self.history=a.history

    def test_accepted_half_steps_replay_and_budgets(self):
        r=advance_doubled(self.grid,self.grains,self.ids,self.history,(1,1),.01,**self.kw)
        g=self.grains;h=self.history
        for dt in r.accepted_steps:
            a=advance_operator_history(self.grid,g,self.ids,h,(1,1),dt,**self.kw).candidate
            g=a.contact.grains;h=a.history
        self.assertEqual(r.grains,g);self.assertEqual(r.history,h)
        self.assertAlmostEqual(r.elapsed,.01,places=15)
        self.assertLessEqual(r.position_estimate_sum,1e-5)
        self.assertLessEqual(r.history_estimate_sum,1e-5)
        self.assertLessEqual(r.solver_calls,189)
        self.assertLess(r.volume_error,1e-9);self.assertLess(r.energy_error,1e-9)

    def test_second_half_failure_retains_old_state(self):
        from experiments.deposition import step_doubling_history as module
        real=module.advance_operator_history;calls=[];saved=snapshot(self.history);original=list(self.grains)
        def fail(*args,**kwargs):
            calls.append(args[5])
            if len(calls)==3:raise ContactConvergenceError('Injected second half failure')
            return real(*args,**kwargs)
        with patch.object(module,'advance_operator_history',side_effect=fail):
            with self.assertRaises(DrainageBudgetError):advance_doubled(self.grid,self.grains,self.ids,self.history,(1,1),.01,max_leaves=1,**self.kw)
        self.assertEqual(calls,[.01,.005,.005]);self.assertEqual(snapshot(self.history),saved);self.assertEqual(self.grains,original)

    def test_accuracy_budget_refuses_without_mutation(self):
        before=snapshot(self.history)
        with self.assertRaises(DrainageBudgetError):advance_doubled(self.grid,self.grains,self.ids,self.history,(1,1),.01,position_tolerance=1e-12,history_tolerance=1e-12,max_leaves=1,**self.kw)
        self.assertEqual(snapshot(self.history),before)

    def test_bounded_cache_preserves_exact_accepted_state_and_schedule(self):
        from dataclasses import asdict
        a=advance_doubled(self.grid,self.grains,self.ids,self.history,(1,1),.01,reuse=True,**self.kw)
        b=advance_doubled(self.grid,self.grains,self.ids,self.history,(1,1),.01,reuse=False,**self.kw)
        self.assertGreater(a.cache_hits,0)
        self.assertLess(a.solver_calls,b.solver_calls)
        self.assertLessEqual(a.cache_peak,8)
        da,db=asdict(a),asdict(b)
        for key in ('cache_hits','cache_peak','solver_calls'):
            da.pop(key);db.pop(key)
        self.assertEqual(da,db)
