import math
import unittest
from cut_cell_operator_reference import fixtures,evaluate


class CutCellOperatorTests(unittest.TestCase):
    def test_pressure_solution_closes_encoded_equation(self):
        for data in fixtures():
            if 'solve' in data:
                force,applied=evaluate(data,data['solve']['pressure'])
                self.assertLessEqual(max(abs(a-b) for a,b in zip(applied,data['expected'][1::2])),1.1e-10)
                self.assertEqual([x for v in force for x in v],data['solve']['force'])
            else:
                self.assertEqual(data['dt'],0.)
                self.assertLess(abs(sum(data['source_component_sum'])),1e-12)
                self.assertGreater(max(map(abs,data['source_component_sum'])),1e-6)
            if data['name']=='inertial-sealed-components':
                self.assertIn('solve',data)
                self.assertGreater(max(map(abs,data['source_component_sum'])),1e-6)

    def test_encoded_operator_preserves_energy_and_pressure_work(self):
        for data in fixtures():
            p=data['pressure'];force=data['expected_force'];v=data['velocity'];out=data['expected']
            quadratic=math.fsum(p[i]*out[2*i] for i in range(data['nodes']))
            edge_energy=.5*math.fsum(w*(p[i]-p[j])**2 for i in range(data['nodes'])
                for j,w in data['edges'][data['edge_rows'][i]:data['edge_rows'][i+1]])
            inertia=data['dt']*math.fsum((force[2*i]**2+force[2*i+1]**2)/m for i,m in enumerate(data['mass']))
            self.assertAlmostEqual(quadratic,edge_energy+inertia,places=12)
            self.assertGreaterEqual(quadratic,-1e-14)
            self.assertAlmostEqual(math.fsum(p[i]*out[2*i+1] for i in range(data['nodes'])),
                                   -math.fsum(a*b for a,b in zip(force,v)),places=12)
            if data['components']==2 and data['dt']==0.:
                self.assertEqual(out[::2],[0.]*data['nodes'])
