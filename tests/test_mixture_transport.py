import math
import unittest

from experiments.liquid.model import DarcyGrid, circle_mask
from experiments.liquid.transport import DriftMixture


def initial_mixture(n=16):
    grid=DarcyGrid(n,circle_mask(n))
    fields=[[0.0]*(n*n) for _ in range(5)]
    for i,active in enumerate(grid.active):
        if not active:
            continue
        x,y=(i%n+0.5)/n,(i//n+0.5)/n
        sand=0.45 if 0.2<y<0.4 else 0
        gas=0.6 if (x-0.5)**2+(y-0.6)**2<0.1**2 else 0
        for k in (1,2,3):
            fields[k][i]=sand/3
        fields[4][i]=gas
        fields[0][i]=1-sand-gas
    return DriftMixture(grid,fields,[(0,0),(0,0.07),(0,0.05),(0,0.03),(0,-0.08)])


class MixtureTransportTests(unittest.TestCase):
    def test_material_and_local_volume_conservation_after_rotation(self):
        mixture=initial_mixture()
        original=mixture.inventory()
        for step in range(25):
            angle=step*0.2
            mixture.slips=[(speed*math.sin(angle),speed*math.cos(angle)) for speed in (0,0.07,0.05,0.03,-0.08)]
            result=mixture.advance(0.05)
            self.assertLess(result.max_volume_error,1e-9)
            self.assertGreaterEqual(min(min(c) for c in mixture.fractions),0)
            self.assertLessEqual(max(max(c) for c in mixture.fractions),1+1e-9)
        for before,after in zip(original,mixture.inventory()):
            self.assertAlmostEqual(before,after,places=12)

    def test_gas_rises_sand_sinks_with_returnflow(self):
        mixture=initial_mixture()
        center=lambda k: sum(v*(i//16+0.5)/16 for i,v in enumerate(mixture.fractions[k]))/sum(mixture.fractions[k])
        sand,gas=center(1),center(4)
        mixture.advance(0.3)
        self.assertGreater(center(1),sand)
        self.assertLess(center(4),gas)

    def test_time_partition_converges(self):
        states=[]
        for steps in (1,2,4):
            mixture=initial_mixture()
            for _ in range(steps):
                mixture.advance(0.1/steps)
            states.append(mixture.fractions)
        distance=lambda a,b: sum(abs(x-y) for ca,cb in zip(a,b) for x,y in zip(ca,cb))
        self.assertLess(distance(states[1],states[2]),distance(states[0],states[1]))

    def test_budget_stops_with_consistent_simulation_time(self):
        mixture=initial_mixture()
        with self.assertRaises(RuntimeError):
            mixture.advance(100,max_substeps=1)
        self.assertGreater(mixture.time,0)
        self.assertLess(mixture.time,100)
        self.assertGreaterEqual(min(min(c) for c in mixture.fractions),0)
