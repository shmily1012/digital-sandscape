import copy
import unittest
from grain_cut_cells import build, overlap_ledger, moving_box_gas


class RegionOverlapTests(unittest.TestCase):
    def test_moving_gas_reaches_exact_endpoint_geometry(self):
        n,m,o=self.fixture();old=build(m,o,n)
        moved=copy.deepcopy(o);moved[27][0]+=.02;moved[27][1]+=.01
        new=build(m,moved,n)
        gas=[node['area']*(.2 if node['center'][0]<3.2 else .8) for node in old['nodes']]
        snapshot=copy.deepcopy((old,new,gas));result=moving_box_gas(old,new,gas)
        self.assertLess(result['endpoint_area_error'],1e-12)
        self.assertLess(abs(result['gas_drift']),1e-10)
        self.assertLess(result['gas_residual'],1e-11)
        self.assertTrue(all(-1e-12<=g<=node['area']+1e-12 for node,g in zip(new['nodes'],result['gas'])))
        self.assertEqual((old,new,gas),snapshot)

    def test_kinematic_sealed_plug_cannot_displace_liquid(self):
        n=8;m=[1]*(n*n);o=[[0.,0.] for _ in m]
        for x in range(1,n-1):m[3*n+x]=0
        m[27]=2;old=build(m,o,n);o[27]=[.01,0.];new=build(m,o,n)
        with self.assertRaisesRegex(ValueError,'sealed liquid component'):
            moving_box_gas(old,new,[node['area']*.5 for node in old['nodes']])

    def fixture(self):
        n=8;m=[int(i%n in (0,n-1) or i//n in (0,n-1)) for i in range(n*n)]
        m[27]=2;o=[[0.,0.] for _ in m];o[27]=[.13,-.27]
        return n,m,o

    def test_identity_and_static_repartition(self):
        n,m,o=self.fixture();old=build(m,o,n)
        gas=[node['area']*.6 for node in old['nodes']]
        self.assertTrue(overlap_ledger(old,old,gas)['complete'])
        new=copy.deepcopy(old);node=new['nodes'].pop(0);mid=(node['x0']+node['x1'])*.5
        for a,b in ((node['x0'],mid),(mid,node['x1'])):
            part=dict(node,x0=a,x1=b,area=(b-a)*(node['hi'][0]-node['lo'][0]))
            new['nodes'].append(part)
        result=overlap_ledger(old,new,gas)
        self.assertTrue(result['complete'])
        self.assertLess(abs(sum(result['mapped_gas'])-sum(gas)),1e-12)

    def test_translation_keeps_displaced_gas_in_explicit_ledger(self):
        n,m,o=self.fixture();old=build(m,o,n);moved=copy.deepcopy(o)
        moved[27][0]+=.02;moved[27][1]+=.01;new=build(m,moved,n)
        gas=[node['area']*(.2 if node['center'][0]<3.2 else .8) for node in old['nodes']]
        snapshot=copy.deepcopy((old,new,gas));result=overlap_ledger(old,new,gas)
        self.assertFalse(result['complete'])
        self.assertAlmostEqual(sum(result['covered_volume']),.02+.01-.02*.01,places=12)
        self.assertAlmostEqual(sum(result['opened_volume']),.02+.01-.02*.01,places=12)
        self.assertGreater(sum(result['held_gas']),0.)
        self.assertLess(abs(result['gas_balance']),1e-12)
        self.assertTrue(all(old['nodes'][i]['cell']==new['nodes'][j]['cell'] for i,j,_ in result['overlaps']))
        self.assertEqual((old,new,gas),snapshot)

    def test_sealed_sides_do_not_mix_during_repartition(self):
        n,m,o=self.fixture()
        m[27]=0
        for y in range(1,n-1):m[y*n+4]=2
        old=build(m,o,n);gas=[node['area'] if node['center'][0]<4 else 0. for node in old['nodes']]
        result=overlap_ledger(old,old,gas)
        self.assertTrue(all(g==0. for node,g in zip(old['nodes'],result['mapped_gas']) if node['center'][0]>4))

    def test_identity_changes_and_large_steps_reject(self):
        n,m,o=self.fixture();old=build(m,o,n);gas=[0.]*len(old['nodes'])
        changed=m.copy();changed[27]=3
        with self.assertRaisesRegex(ValueError,'identity'):overlap_ledger(old,build(changed,o,n),gas)
        moved=copy.deepcopy(o);moved[27][0]+=.3
        with self.assertRaisesRegex(ValueError,'bound'):overlap_ledger(old,build(m,moved,n),gas)
