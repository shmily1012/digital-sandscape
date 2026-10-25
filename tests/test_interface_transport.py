import math
from types import SimpleNamespace
import unittest

from experiments.liquid.reconstruction import reconstruct
from test_mixture_transport import initial_mixture


def translated_wave(n, muscl=True, square=False):
    grid=SimpleNamespace(active=[True]*n,faces=[(i,(i+1)%n,1,0) for i in range(n)])
    initial=[float(0.25<(i+0.5)/n<0.5) if square else 0.5+0.25*math.sin(2*math.pi*(i+0.5)/n) for i in range(n)]
    state=[initial,[1-v for v in initial]]
    def rhs(fields):
        faces=reconstruct(grid,fields)[0] if muscl else fields
        return [[-n*(f[i]-f[(i-1)%n]) for i in range(n)] for f in faces]
    steps=4*n
    dt=1/steps
    for _ in range(steps):
        first=rhs(state)
        stage=[[v+dt*d for v,d in zip(c,r)] for c,r in zip(state,first)]
        second=rhs(stage)
        state=[[0.5*(v+w+dt*d) for v,w,d in zip(c,s,r)] for c,s,r in zip(state,stage,second)]
    return initial,state


class InterfaceTransportTests(unittest.TestCase):
    def test_face_simplex_and_local_bounds(self):
        mixture=initial_mixture()
        positive,negative=reconstruct(mixture.grid,mixture.fractions)
        for side in (positive,negative):
            for f in range(len(mixture.grid.faces)):
                self.assertAlmostEqual(sum(c[f] for c in side),1,places=12)
                self.assertGreaterEqual(min(c[f] for c in side),0)
                self.assertLessEqual(max(c[f] for c in side),1)

    def test_smooth_translation_accuracy_and_grid_convergence(self):
        errors=[]
        for n in (32,64):
            initial,high=translated_wave(n)
            _,low=translated_wave(n,muscl=False)
            high_error=sum(abs(a-b) for a,b in zip(initial,high[0]))/n
            low_error=sum(abs(a-b) for a,b in zip(initial,low[0]))/n
            self.assertLess(high_error,low_error*0.3)
            errors.append(high_error)
        self.assertLess(errors[1],errors[0]/3)

    def test_sharp_translation_bounds_inventory_and_less_mixing(self):
        initial,high=translated_wave(64,square=True)
        _,low=translated_wave(64,muscl=False,square=True)
        self.assertGreaterEqual(min(high[0]),-1e-12)
        self.assertLessEqual(max(high[0]),1+1e-12)
        self.assertAlmostEqual(sum(high[0]),sum(initial),places=11)
        mixing=lambda c: sum(v*(1-v) for v in c)
        self.assertLess(mixing(high[0]),mixing(low[0])*0.6)

    def test_pressure_coupled_muscl_preserves_all_materials(self):
        mixture=initial_mixture()
        mixture.scheme='muscl'
        inventory=mixture.inventory()
        for step in range(30):
            a=step*0.31
            mixture.slips=[(v*math.sin(a),v*math.cos(a)) for v in (0,0.07,0.05,0.03,-0.08)]
            report=mixture.advance(0.05)
            self.assertLess(report.max_volume_error,1e-9)
            self.assertGreaterEqual(min(min(c) for c in mixture.fractions),0)
        for a,b in zip(inventory,mixture.inventory()):
            self.assertAlmostEqual(a,b,places=12)
