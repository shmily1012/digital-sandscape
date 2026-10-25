import copy
import unittest
from grain_cut_cells import build, pressure
from local_gas_reference import transport_regions


class RegionGasTests(unittest.TestCase):
    def test_disappearing_capacity_transfers_inventory_without_clipping(self):
        graph=dict(nodes=[dict(area=1.),dict(area=1.)],edges=[(0,1,1.)],labels=[0,0],components=1)
        old=[.75,.25];original=copy.deepcopy(graph)
        result=transport_regions(graph,old,[0.,2.],[10.])
        self.assertEqual(result['gas'],[0.,1.])
        self.assertEqual(graph,original)
        self.assertEqual(old,[.75,.25])

    def test_new_capacity_receives_only_local_incoming_gas(self):
        graph=dict(nodes=[dict(area=1.),dict(area=0.)],edges=[(0,1,1.)],labels=[0,0],components=1)
        result=transport_regions(graph,[.6,0.],[.8,.2],[2.])
        self.assertAlmostEqual(result['gas'][0],.48)
        self.assertAlmostEqual(result['gas'][1],.12)

    def test_sealed_barrier_retains_each_gas_inventory(self):
        n=12;m=[int(i%n in (0,n-1) or i//n in (0,n-1)) for i in range(n*n)]
        for y in range(1,n-1):m[y*n+6]=2
        graph=build(m,[[0.,0.]]*(n*n),n,'disk')
        left=[i for i,node in enumerate(graph['nodes']) if node['cell']%n<5]
        label=graph['labels'][left[0]]
        source=[0.]*len(graph['nodes']);source[left[0]]=.01;source[left[-1]]=-.01
        solution=pressure(graph,source)
        capacity=[node['area'] for node in graph['nodes']]
        new=capacity.copy()
        for (i,j,_),q in zip(graph['edges'],solution['flux']):new[i]-=.1*q;new[j]+=.1*q
        old=[.6*v if group==label else 0. for v,group in zip(capacity,graph['labels'])]
        original=copy.deepcopy(graph)
        result=transport_regions(graph,old,new,solution['flux'])
        self.assertTrue(all(g==0. for g,group in zip(result['gas'],graph['labels']) if group!=label))
        self.assertLess(max(abs(x) for x in result['component_inventory_drift']),1e-10)
        self.assertEqual(graph,original)

    def test_inconsistent_geometry_and_short_budget_reject(self):
        graph=dict(nodes=[dict(area=1.) for _ in range(3)],edges=[(0,1,1.),(1,2,1.),(2,0,1.)],labels=[0]*3,components=1)
        with self.assertRaisesRegex(ValueError,'disagree'):transport_regions(graph,[1.,0.,0.],[1.1,1.,1.],[1.,1.,1.])
        with self.assertRaisesRegex(RuntimeError,'budget'):transport_regions(graph,[1.,0.,0.],[1.,1.,1.],[1.,1.,1.],max_iterations=1)
        result=transport_regions(graph,[1.,0.,0.],[1.,1.,1.],[1.,1.,1.])
        self.assertLess(abs(sum(result['gas'])-1.),1e-11)
