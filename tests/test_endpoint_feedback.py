import copy
import unittest
from grain_cut_cells import build,moving_contact_candidate,contact_prediction


class EndpointFeedbackTests(unittest.TestCase):
    def test_twenty_grain_endpoint_preserves_material_and_gas(self):
        from grain_contact_impulse_reference import MASS
        n=32;material=[int(i%n in (0,n-1) or i//n in (0,n-1)) for i in range(n*n)]
        offset=[[0.,0.] for _ in material];velocity=copy.deepcopy(offset)
        for y in range(3,23):
            i=y*n+16;material[i]=2+y%3;offset[i]=[0.,.49];velocity[i]=[0.,.02]
        graph=build(material,offset,n);original=copy.deepcopy(graph)
        mass=[MASS.get(m,0.) for m in material]
        gas=[node['area']*(.8 if node['center'][1]>16 else .2) for node in graph['nodes']]
        result=moving_contact_candidate(graph,velocity,mass,
            [(y*n+16,(y+1)*n+16,0.,1.,0.) for y in range(3,22)],gas)
        self.assertTrue(result['accepted'])
        self.assertLessEqual(result['residual'],1e-8)
        self.assertLessEqual(result['remap']['capacity_residual'],1.1e-12)
        self.assertLessEqual(result['remap']['geometric_contact_residual'],1e-8)
        self.assertLessEqual(result['remap']['work_error'],1e-10)
        self.assertEqual(result['graph']['materials'],material)
        self.assertEqual([g[0] for g in result['graph']['grains']],[g[0] for g in graph['grains']])
        self.assertLess(abs(sum(result['gas'])-sum(gas)),1e-10)
        self.assertTrue(all(0<=g<=node['area']*(1+1e-14) for g,node in zip(result['gas'],result['graph']['nodes'])))
        self.assertEqual(graph,original)
        self.assertEqual(graph['offsets'],offset)

    def fixture(self):
        n=8;m=[int(i%n in (0,n-1) or i//n in (0,n-1)) for i in range(n*n)]
        m[27]=2;o=[[0.,0.] for _ in m];o[27]=[.13,-.27]
        graph=build(m,o,n);v=[[0.,0.] for _ in m];v[27]=[.02,-.01]
        return graph,v,[3. if x>=2 else 0. for x in m],[node['area']*.6 for node in graph['nodes']]

    def test_endpoint_pressure_closes_original_momentum(self):
        graph,v,mass,gas=self.fixture();original=copy.deepcopy((graph,v,mass,gas))
        result=moving_contact_candidate(graph,v,mass,[],gas)
        self.assertTrue(result['accepted'])
        self.assertLess(result['residual'],1e-8)
        self.assertLess(result['remap']['work_error'],1e-10)
        self.assertLess(result['remap']['endpoint_area_error'],1e-12)
        self.assertLessEqual(result['remap']['capacity_residual'],1.1e-12)
        self.assertEqual(result['remap']['pressure_reaction'],result['contact']['force'])
        self.assertLess(abs(sum(result['gas'])-sum(gas)),1e-10)
        self.assertNotEqual(result['graph']['grains'],graph['grains'])
        for axis in (0,1):
            self.assertEqual(result['velocity'][27][axis],
                (result['graph']['offsets'][27][axis]-graph['offsets'][27][axis])/.1)
        self.assertEqual((graph,v,mass,gas),original)

    def test_sticking_chain_closes_capacity_without_changing_inventory(self):
        graph,v,mass,gas=self.fixture()
        n=8;material=list(graph['materials']);offset=[[0.,0.] for _ in material]
        for i in (19,27,35):
            material[i]=2;offset[i]=[.13,-.27];mass[i]=3.;v[i]=[0.,.02]
        graph=build(material,offset,n)
        gas=[node['area']*.6 for node in graph['nodes']]
        original=copy.deepcopy((graph,v,mass,gas))
        result=moving_contact_candidate(graph,v,mass,[(19,27,0.,1.,0.),(27,35,0.,1.,0.)],gas)
        self.assertTrue(result['accepted'])
        self.assertLessEqual(result['capacity_history'][-1],1.1e-12)
        self.assertLessEqual(result['remap']['geometric_contact_residual'],1e-8)
        self.assertLessEqual(result['residual'],1e-8)
        self.assertLessEqual(result['remap']['work_error'],1e-10)
        self.assertEqual(result['remap']['pressure_reaction'],result['contact']['force'])
        self.assertLess(abs(sum(result['gas'])-sum(gas)),1e-10)
        self.assertEqual(result['graph']['materials'],graph['materials'])
        self.assertEqual((graph,v,mass,gas),original)
        inventory=sum(gas)
        for _ in range(4):
            free=copy.deepcopy(result['velocity'])
            for i in (19,27,35):free[i][1]+=.002
            result=moving_contact_candidate(result['graph'],free,mass,
                [(19,27,0.,1.,0.),(27,35,0.,1.,0.)],result['gas'])
            self.assertTrue(result['accepted'])
            self.assertLessEqual(result['capacity_history'][-1],1.1e-12)
            self.assertLessEqual(result['remap']['geometric_contact_residual'],1e-8)
            self.assertLessEqual(result['residual'],1e-8)
            self.assertLess(abs(sum(result['gas'])-inventory),1e-10)

    def test_prediction_preserves_momentum_and_does_not_lock_sliding_or_opening(self):
        v=[[.01,.02],[.01+1e-14,.02-1e-14]];mass=[1.,3.]
        joint=dict(velocity=v,contact_lambdas=[[1.,0.]])
        contact=[(0,1,0.,1.,0.)]
        prediction=contact_prediction(joint,mass,contact)
        self.assertEqual(prediction[0],prediction[1])
        for axis in (0,1):
            self.assertAlmostEqual(sum(mass[i]*v[i][axis] for i in (0,1)),
                                   sum(mass[i]*prediction[i][axis] for i in (0,1)),places=15)
        self.assertEqual(joint['velocity'],v)
        joint['contact_lambdas']=[[1.,.5]]
        sliding=contact_prediction(joint,mass,contact)
        self.assertEqual([p[0] for p in sliding],[p[0] for p in v])
        self.assertEqual(sliding[0][1],sliding[1][1])
        joint['contact_lambdas']=[[0.,0.]]
        self.assertEqual(contact_prediction(joint,mass,contact),v)
        joint['contact_lambdas']=[[1.,0.]]
        self.assertEqual(contact_prediction(joint,mass,[(0,1,0.,1.,1e-8)]),v)
        joint['velocity']=[[0.,.01],[.02,.03]]
        self.assertEqual(contact_prediction(joint,mass,contact),joint['velocity'])

    def test_failed_feedback_exposes_no_partial_state(self):
        graph,v,mass,gas=self.fixture();original=copy.deepcopy((graph,v,mass,gas))
        result=moving_contact_candidate(graph,v,mass,[],gas,iterations=1)
        self.assertFalse(result['accepted'])
        self.assertNotIn('graph',result)
        self.assertNotIn('gas',result)
        self.assertEqual((graph,v,mass,gas),original)

    def test_zero_motion_retains_pressure_support(self):
        n=8;m=[1]*(n*n);o=[[0.,0.] for _ in m];v=copy.deepcopy(o)
        for x in range(1,n-1):m[3*n+x]=0
        m[27]=2;v[27]=[.02,0.]
        graph=build(m,o,n);gas=[node['area']*.5 for node in graph['nodes']]
        result=moving_contact_candidate(graph,v,[3. if x>=2 else 0. for x in m],[],gas)
        self.assertTrue(result['accepted'])
        self.assertTrue(result['remap']['fixed_geometry_pressure_retained'])
        self.assertLess(abs(result['velocity'][27][0]),1e-10)
        self.assertAlmostEqual(result['remap']['pressure_reaction'][27][0],-.6,places=9)
