import unittest
import copy
from grain_volume_reference import fixtures
from drainage_reaction_reference import reaction, work, dissipation, feedback
from grain_contact_impulse_reference import MASS


class DrainageReactionTests(unittest.TestCase):
    def test_secant_feedback_retains_true_residual_gate(self):
        case=fixtures()[8]
        aligned=feedback(case,accelerate=True)
        self.assertFalse(aligned['accepted'])
        for i,m in enumerate(case['material']):
            if m>=2:case['offset'][i][0]=.01
        original=copy.deepcopy(case)
        result=feedback(case,accelerate=True)
        self.assertTrue(result['accepted'])
        self.assertLessEqual(result['residual'],1e-8)
        self.assertLessEqual(result['contact_residual'],1e-8)
        self.assertEqual(case,original)
        for i,m in enumerate(case['material']):
            if m<2:continue
            for axis in range(2):
                balance=MASS[m]*(result['velocity'][i][axis]-case['velocity'][i][axis])-.1*result['pressure_reaction'][i][axis]-result['contact_impulse'][i][axis]
                self.assertLess(abs(balance),MASS[m]*1e-8)

    def test_same_step_feedback_balance_and_dissipation(self):
        for case in fixtures()[:8]:
            original=copy.deepcopy(case)
            result=feedback(case)
            self.assertTrue(result['accepted'],case['name'])
            self.assertEqual(case,original)
            before=after=0.
            for i,m in enumerate(case['material']):
                if m<2:continue
                for axis in range(2):
                    old=case['velocity'][i][axis];new=result['velocity'][i][axis]
                    balance=MASS[m]*(new-old)-.1*result['pressure_reaction'][i][axis]-result['contact_impulse'][i][axis]
                    self.assertLess(abs(balance),MASS[m]*1e-8)
                    before+=.5*MASS[m]*old*old
                    after+=.5*MASS[m]*new*new
            self.assertLess(after,before)
            self.assertLess(abs(work(result,result['pressure_reaction'])+dissipation(result)),1e-10)

    def test_feedback_rejects_insufficient_budget_and_dense_chain(self):
        cases=fixtures()
        for case,budget in ((cases[0],1),(cases[8],16)):
            original=copy.deepcopy(case)
            result=feedback(case,iterations=budget)
            self.assertFalse(result['accepted'])
            self.assertEqual(result['reason'],'feedback budget exhausted')
            self.assertEqual(result['iterations'],budget)
            self.assertEqual(case,original)

    def test_pressure_work_matches_drainage_loss(self):
        for case in fixtures():
            if not case['valid']:continue
            power=work(case,case['pressure_reaction'])
            self.assertLess(power,0.)
            self.assertLess(abs(power+dissipation(case)),1e-10,case['name'])

    def test_pressure_gauge_does_not_change_reaction(self):
        case=fixtures()[2]
        shifted=reaction(case,[p+3.25 for p in case['pressure']])
        self.assertLess(max(abs(x-y) for a,b in zip(shifted,case['pressure_reaction']) for x,y in zip(a,b)),1e-12)
