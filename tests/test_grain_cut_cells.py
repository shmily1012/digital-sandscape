import unittest
import copy
from grain_cut_cells import build, pressure, boundary_source, boundary_reaction, coupled_pressure, coupled_contacts, moving_box_gas
from grain_volume_reference import occupancy


class CutCellTests(unittest.TestCase):
    def test_equal_local_offsets_do_not_open_internal_contact_faces(self):
        n=16;m=[int(i%n in (0,n-1) or i//n in (0,n-1)) for i in range(n*n)]
        offsets=[[0.,0.] for _ in m]
        for y in range(3,11):m[y*n+8]=2;offsets[y*n+8]=[0.,.49195]
        graph=build(m,offsets,n)
        interior={y*n+8 for y in range(4,11)}
        self.assertFalse(any(node['cell'] in interior for node in graph['nodes']))
        self.assertAlmostEqual(sum(node['area'] for node in graph['nodes']),14*14-8,places=12)
        self.assertEqual(graph['offsets'],offsets)
        offsets[3*n+8][1]=.4
        self.assertEqual(graph['offsets'][3*n+8][1],.49195)

    def check_joint_balance(self,result,velocity,mass,dt=.1):
        for i,m in enumerate(mass):
            if not m:continue
            for k in range(2):
                error=m*(result['velocity'][i][k]-velocity[i][k])-dt*result['force'][i][k]-result['contact_impulse'][i][k]
                self.assertLess(abs(error),1e-10)
        before=sum(.5*m*sum(x*x for x in v) for m,v in zip(mass,velocity))
        after=sum(.5*m*sum(x*x for x in v) for m,v in zip(mass,result['velocity']))
        defect=sum(.5*m*sum((a-b)**2 for a,b in zip(v,w)) for m,v,w in zip(mass,velocity,result['velocity']))
        contact_work=sum(j*v for impulse,vel in zip(result['contact_impulse'],result['velocity']) for j,v in zip(impulse,vel))
        self.assertLessEqual(contact_work,1e-10)
        self.assertLess(abs(after-before+defect+dt*result['dissipation']-contact_work),1e-10)

    def test_twenty_grain_joint_pressure_contact(self):
        from grain_volume_reference import fixtures
        from grain_contact_impulse_reference import MASS
        case=fixtures()[8];graph=build(case['material'],case['offset'],32)
        original=copy.deepcopy(graph);mass=[MASS.get(m,0.) for m in case['material']]
        contacts=[(y*32+16,(y+1)*32+16,0.,1.,0.) for y in range(3,22)]
        result=coupled_contacts(graph,case['velocity'],mass,contacts)
        self.assertLess(result['contact_residual'],1e-8)
        self.assertLess(result['continuity'],1e-10)
        self.assertTrue(result['uniform_pressure_contact_null'])
        self.assertTrue(all(b<=a for a,b in zip(result['polish_merits'],result['polish_merits'][1:])))
        self.check_joint_balance(result,case['velocity'],mass)
        endpoint=[[p+.1*v for p,v in zip(pos,vel)] if material>=2 else list(pos)
                  for pos,vel,material in zip(case['offset'],result['velocity'],case['material'])]
        new_graph=build(case['material'],endpoint,32)
        gas=[node['area']*(.8 if node['center'][1]>16 else .2) for node in graph['nodes']]
        remap=moving_box_gas(graph,new_graph,gas)
        self.assertLess(remap['pressure_residual'],1e-12)
        self.assertLess(remap['endpoint_area_error'],1e-12)
        self.assertLess(abs(remap['gas_drift']),1e-10)
        self.assertTrue(remap['kinematic_only'])
        self.assertEqual(graph,original)

    def test_joint_contact_friction_cone(self):
        n,m,o=self.fixture();m[53]=2;m[65]=2
        v=[[0.,0.] for _ in m];v[53]=[.01,.02]
        graph=build(m,o,n);mass=[3. if material>=2 else 0. for material in m]
        for friction in (0.,.5):
            result=coupled_contacts(graph,v,mass,[(53,65,0.,1.,0.)],friction=friction)
            normal,tangent=result['contact_lambdas'][0]
            self.assertGreaterEqual(normal,-1e-10)
            self.assertLessEqual(abs(tangent),friction*normal+1e-10)
            self.assertLess(result['contact_residual'],1e-8)
            self.check_joint_balance(result,v,mass)

    def test_coupled_pressure_stops_sealed_plug(self):
        n=12;m=[1]*(n*n);o=[[0.,0.] for _ in m];v=copy.deepcopy(o)
        for x in range(1,n-1):m[6*n+x]=0
        grain=6*n+6;m[grain]=2;v[grain]=[.02,0.]
        graph=build(m,o,n);mass=[3. if material>=2 else 0. for material in m]
        source,_=boundary_source(graph,v)
        with self.assertRaises(ValueError):pressure(graph,source)
        result=coupled_pressure(graph,v,mass)
        self.assertLess(abs(result['velocity'][grain][0]),1e-10)
        self.assertAlmostEqual(result['force'][grain][0],-.6,places=9)
        self.assertLess(max(abs(q) for q in result['flux']),1e-10)
        self.assertEqual(v[grain],[.02,0.])

    def test_coupled_pressure_energy_and_budget(self):
        for shape in ('box','disk'):
            n,m,o=self.fixture();m[65]=2;o[65]=[.13,-.27]
            v=[[0.,0.] for _ in m];v[65]=[.02,-.01]
            graph=build(m,o,n,shape);mass=[3. if material>=2 else 0. for material in m]
            original=copy.deepcopy(graph)
            result=coupled_pressure(graph,v,mass)
            before=sum(.5*mass[i]*sum(x*x for x in vel) for i,vel in enumerate(v))
            after=sum(.5*mass[i]*sum(x*x for x in vel) for i,vel in enumerate(result['velocity']))
            defect=sum(.5*mass[i]*sum((a-b)**2 for a,b in zip(old,new)) for i,(old,new) in enumerate(zip(v,result['velocity'])))
            self.assertLess(after,before)
            self.assertLess(abs(after-before+defect+.1*result['dissipation']),1e-10)
            self.assertLess(result['continuity'],1e-10)
            with self.assertRaises(RuntimeError):coupled_pressure(graph,v,mass,max_iterations=1)
            self.assertEqual(graph,original)

    def test_boundary_source_matches_area_derivative(self):
        for shape in ('box','disk'):
            n,m,o=self.fixture();m[65]=2;o[65]=[.13,-.27]
            v=[[0.,0.] for _ in m];v[65]=[.02,-.01]
            graph=build(m,o,n,shape);source,weights=boundary_source(graph,v)
            aggregate=[0.]*(n*n)
            for node,s in zip(graph['nodes'],source):aggregate[node['cell']]+=s
            epsilon=1e-5
            before=[[x-epsilon*u for x,u in zip(pos,vel)] for pos,vel in zip(o,v)]
            after=[[x+epsilon*u for x,u in zip(pos,vel)] for pos,vel in zip(o,v)]
            area0,area1=occupancy(m,before,n,shape),occupancy(m,after,n,shape)
            self.assertLess(max(abs(s-(b-a)/(2*epsilon)) for s,a,b in zip(aggregate,area0,area1)),1e-9)
            self.assertLess(abs(sum(source)),1e-12)
            force=boundary_reaction(graph,weights,[3.25]*len(source))
            self.assertLess(max(abs(x) for row in force for x in row),1e-12)

    def test_boundary_reaction_matches_network_work(self):
        for shape in ('box','disk'):
            n,m,o=self.fixture();m[65]=2;o[65]=[.13,-.27]
            v=[[0.,0.] for _ in m];v[65]=[.02,-.01]
            graph=build(m,o,n,shape);source,weights=boundary_source(graph,v)
            result=pressure(graph,source)
            force=boundary_reaction(graph,weights,result['pressure'])
            power=sum(f*u for row,vel in zip(force,v) for f,u in zip(row,vel))
            self.assertLess(power,0.)
            self.assertLess(abs(power+result['dissipation']),1e-10)

    def test_boundary_cannot_compress_sealed_sides(self):
        n,m,o=self.fixture();v=[[0.,0.] for _ in m]
        for y in range(1,n-1):m[y*n+6]=2;v[y*n+6]=[.01,0.]
        for shape in ('box','disk'):
            graph=build(m,o,n,shape);source,_=boundary_source(graph,v)
            self.assertLess(abs(sum(source)),1e-12)
            with self.assertRaisesRegex(ValueError,'sealed liquid component'):pressure(graph,source)

    def test_region_pressure_preserves_sealed_components(self):
        n,m,o=self.fixture()
        for y in range(1,n-1):m[y*n+6]=2
        graph=build(m,o,n,'disk');original=copy.deepcopy(graph)
        left=[i for i,node in enumerate(graph['nodes']) if node['cell']%n<5]
        right=[i for i,node in enumerate(graph['nodes']) if node['cell']%n>7]
        source=[0.]*len(graph['nodes']);source[left[0]]=1.;source[right[-1]]=-1.
        with self.assertRaisesRegex(ValueError,'sealed liquid component'):pressure(graph,source)
        source[right[-1]]=0.;source[left[-1]]=-1.
        result=pressure(graph,source)
        self.assertLess(result['residual'],1e-10)
        self.assertTrue(all(result['pressure'][i]==0. for i in right))
        self.assertAlmostEqual(result['source_work'],result['dissipation'],places=9)
        self.assertEqual(graph,original)
        with self.assertRaises(RuntimeError):pressure(graph,source,max_iterations=1)

    def test_real_gap_allows_balanced_cross_barrier_source(self):
        n,m,o=self.fixture()
        for y in range(1,n-1):m[y*n+6]=2
        o[6*n+6]=[.01,0.]
        graph=build(m,o,n,'disk')
        source=[0.]*len(graph['nodes'])
        left=next(i for i,node in enumerate(graph['nodes']) if node['cell']==2*n+2)
        right=next(i for i,node in enumerate(graph['nodes']) if node['cell']==9*n+9)
        source[left]=.01;source[right]=-.01
        result=pressure(graph,source)
        self.assertLess(result['residual'],1e-10)
        self.assertGreater(result['dissipation'],0.)
        self.assertAlmostEqual(result['source_work'],result['dissipation'],places=9)

    def test_empty_grid_pressure_matches_cartesian_operator(self):
        graph=build([0]*9,[[0.,0.]]*9,3)
        expected=[2*node['center'][0]-3*node['center'][1] for node in graph['nodes']]
        source=[0.]*9
        for i,j,_ in graph['edges']:
            source[i]+=expected[i]-expected[j];source[j]-=expected[i]-expected[j]
        result=pressure(graph,source)
        mean=sum(expected)/9
        self.assertLess(max(abs(a-(b-mean)) for a,b in zip(result['pressure'],expected)),1e-10)

    def fixture(self):
        n=12;m=[int(i%n in (0,n-1) or i//n in (0,n-1)) for i in range(n*n)]
        return n,m,[[0.,0.] for _ in m]

    def test_touching_barrier_separates_both_shapes(self):
        for shape in ('box','disk'):
            n,m,o=self.fixture()
            for y in range(1,n-1):m[y*n+6]=2
            graph=build(m,o,n,shape)
            left={label for node,label in zip(graph['nodes'],graph['labels']) if node['cell']%n<5}
            right={label for node,label in zip(graph['nodes'],graph['labels']) if node['cell']%n>7}
            self.assertFalse(left & right,shape)
            self.assertEqual(graph['components'],2,shape)
            m[6*n+6]=0
            self.assertEqual(build(m,o,n,shape)['components'],1,shape)

    def test_subcell_area_matches_independent_integral(self):
        for shape in ('box','disk'):
            n,m,o=self.fixture();m[65]=2;o[65]=[.13,-.27]
            graph=build(m,o,n,shape);area=[0.]*(n*n)
            for node in graph['nodes']:area[node['cell']]+=node['area']
            solid=occupancy(m,o,n,shape)
            self.assertLess(max(abs(a+s-1.) for a,s in zip(area,solid)),1e-12)

    def test_centered_disk_keeps_four_local_regions(self):
        graph=build([2],[[0.,0.]],1,'disk')
        self.assertEqual(graph['components'],4)

    def test_horizontal_barrier_and_real_side_gap(self):
        n,m,o=self.fixture()
        for x in range(1,n-1):m[6*n+x]=2
        self.assertEqual(build(m,o,n,'disk')['components'],2)
        for displacement in (-.01,.01):
            o[6*n+6]=[0.,displacement]
            self.assertEqual(build(m,o,n,'disk')['components'],1)
