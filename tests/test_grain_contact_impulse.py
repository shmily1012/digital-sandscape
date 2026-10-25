import unittest
from grain_contact_impulse_reference import fixtures, metrics, solve, guarded_solve, closing_speed, projected_fixtures, diagonal_fixtures


class GrainContactImpulseTests(unittest.TestCase):
    def test_diagonal_response_prevents_corner_crossing(self):
        from grain_displacement_reference import step
        for data in diagonal_fixtures():
            self.assertTrue(data['accepted'])
            self.assertIsNotNone(step(data['materials'],data['expected'],data['offset'],data['side']))
            result=metrics(data['materials'],data['velocity'],data['expected'],data['reaction'])
            self.assertLess(result['momentum_residual'],1e-12)
            self.assertLessEqual(result['final_energy'],result['initial_energy']+result['wall_work']+1e-8)

    def test_projected_impulses_balance_and_dissipate(self):
        for data in projected_fixtures():
            result=metrics(data['materials'],data['velocity'],data['expected'],data['reaction'])
            self.assertLess(result['momentum_residual'],1e-12)
            self.assertLessEqual(result['final_energy'],result['initial_energy']+result['wall_work']+1e-8)
            if data['name']=='separating':self.assertEqual(data['expected'],[list(v) for v in data['velocity']])

    def test_failed_chain_is_not_committed_and_can_recover(self):
        for data in fixtures():
            if data['name']!='chain':continue
            original=[list(v) for v in data['velocity']]
            accepted,v,r=guarded_solve(data['materials'],original,data['side'],32,data['friction'])
            self.assertFalse(accepted)
            self.assertEqual(v,original)
            self.assertTrue(all(j==[0.,0.] for j in r))
            accepted,v,r=guarded_solve(data['materials'],original,data['side'],128,data['friction'])
            self.assertTrue(accepted)
            self.assertLessEqual(closing_speed(data['materials'],v,data['side']),1e-7)
            self.assertEqual(original,[list(v) for v in data['velocity']])

    def test_reaction_balance_and_dissipation(self):
        for data in fixtures():
            result=metrics(data['materials'],data['velocity'],data['expected'],data['reaction'])
            self.assertLess(result['momentum_residual'],1e-14)
            self.assertLessEqual(result['final_energy'],result['initial_energy']+result['wall_work']+1e-14)

    def test_separating_contacts_are_not_attractive(self):
        for data in fixtures():
            if data['name']=='separating':
                self.assertEqual(data['expected'],[list(v) for v in data['velocity']])
                self.assertTrue(all(v==[0.,0.] for v in data['reaction']))

    def test_normal_contact_and_coulomb_bound(self):
        for data in fixtures():
            if data['orientation']!=0 or data['name'] not in ('pair','wall','moving-wall'):continue
            n=data['side'];a=3*n+3;b=a+1
            self.assertLessEqual(data['expected'][a][0]-data['expected'][b][0],1e-14)
            j=data['reaction'][a]
            self.assertLessEqual(abs(j[1]),data['friction']*abs(j[0])+1e-14)

    def test_more_sweeps_reduce_chain_closing_error(self):
        data=next(d for d in fixtures() if d['name']=='chain' and d['friction']==0.)
        n=data['side'];m=data['materials']
        def closing(v):return max(v[3*n+x][0]-v[3*n+x+1][0] for x in range(1,6))
        short,_=solve(m,data['velocity'],n,1,0.)
        long,_=solve(m,data['velocity'],n,32,0.)
        self.assertLess(closing(long),closing(short))
