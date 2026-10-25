import math
import unittest
from phase_field_reference import circle, step
from phase_momentum_reference import advance, equilibrium


class PhaseMomentumTests(unittest.TestCase):
    def test_unforced_equilibrium(self):
        n=9
        f=equilibrium(n)
        result,velocity=advance(f,[0.]*(n*n),[False]*(n*n),n,gravity=(0.,0.))
        self.assertLess(max(abs(a-b) for a,b in zip(f,result)),1e-15)
        self.assertEqual(max(math.hypot(*u) for u in velocity),0.)

    def test_static_circle_laplace_pressure_and_parasitic_flow(self):
        # Fixed interface isolates force/pressure balance, not full equilibrium.
        n=24;c,wall=circle(n,(11.5,11.5),4.);f=equilibrium(n)
        initial_mass=math.fsum(f[i*9+q] for i in range(n*n) if not wall[i] for q in range(9))
        for _ in range(400):f,v=advance(f,c,wall,n,gravity=(0.,0.))
        inside=[sum(f[i*9:i*9+9])/3 for i,q in enumerate(c) if q>.9]
        outside=[sum(f[i*9:i*9+9])/3 for i,q in enumerate(c) if q<.01 and not wall[i]]
        jump=sum(inside)/len(inside)-sum(outside)/len(outside)
        self.assertLess(abs(jump-.002/4)/(.002/4),.10)
        self.assertLess(max(math.hypot(*u) for u in v),2e-5)
        self.assertAlmostEqual(math.fsum(f[i*9+q] for i in range(n*n) if not wall[i] for q in range(9)),initial_mass,places=9)

    def test_coupled_buoyant_motion_preserves_gas(self):
        n=24;c,wall=circle(n,(11.5,12.),4.);f=equilibrium(n)
        mass=math.fsum(c)
        start=sum(i//n*q for i,q in enumerate(c))/mass
        for _ in range(200):
            f,v=advance(f,c,wall,n)
            c,_=step(c,n,v,wall,dt=1.)
        end=sum(i//n*q for i,q in enumerate(c))/math.fsum(c)
        self.assertGreater(start-end,.05)
        self.assertLess(max(math.hypot(*u) for u in v),.01)
        self.assertAlmostEqual(math.fsum(c),mass,places=10)
        self.assertTrue(all(math.isfinite(q) and -1e-14<=q<=1+1e-14 for q in c))

    def test_invalid_relaxation_time_rejected(self):
        with self.assertRaises(ValueError):
            advance(equilibrium(3),[0.]*9,[False]*9,3,tau=.5)
