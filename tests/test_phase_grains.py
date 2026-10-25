from collections import Counter
import unittest
from phase_grains_reference import fixture, step, GRAVITIES, interface_slide_fixture


class PhaseGrainTests(unittest.TestCase):
    def test_sealed_corner_cannot_be_crossed_in_any_quarter_turn(self):
        for turns in range(4):
            n,c,f,m,g,source,gas,target=interface_slide_fixture(turns,sealed=True)
            before=(c.copy(),f.copy(),m.copy())
            for tick in range(180):step(c,f,m,n,709,tick,g)
            self.assertEqual((c,f,m),before)

    def test_sampled_force_follows_material_through_displacement(self):
        n,c,f,m=fixture()
        forces=[((i%3-1)*2**-16,-2**-14) if v>=2 else (0.,0.) for i,v in enumerate(m)]
        inventory=Counter((v,forces[i]) for i,v in enumerate(m) if v>=2)
        initial=m.copy()
        for tick in range(180):step(c,f,m,n,709,tick,GRAVITIES[tick//30],forces=forces)
        self.assertNotEqual(m,initial)
        self.assertEqual(Counter((v,forces[i]) for i,v in enumerate(m) if v>=2),inventory)
        self.assertTrue(all(forces[i]==(0.,0.) for i,v in enumerate(m) if v<2))

    def test_interface_obstruction_releases_sideways_without_crossing_gas(self):
        for turns in range(4):
            n,c,f,m,g,source,gas,target=interface_slide_fixture(turns)
            counts=Counter(m)
            for tick in range(180):step(c,f,m,n,709,tick,g)
            self.assertEqual(m[target],2)
            self.assertEqual(m[source],0)
            self.assertEqual(m[gas],0)
            self.assertEqual(c[gas],.75)
            self.assertEqual(Counter(m),counts)

    def test_displacement_preserves_material_and_fluid_packets(self):
        n,c,f,m=fixture()
        before=m.copy();counts=Counter(m)
        residual=[(i%17-8)*2**-32 for i in range(n*n)]
        fluid_packets=lambda:Counter((c[i],tuple(f[9*i:9*i+9]),residual[i]) for i,v in enumerate(m) if v==0)
        inventory=fluid_packets()
        for tick in range(180):step(c,f,m,n,709,tick,GRAVITIES[tick//30],mass_residual=residual)
        self.assertNotEqual(m,before)
        self.assertEqual(Counter(m),counts)
        self.assertEqual(fluid_packets(),inventory)
        self.assertTrue(all(m[i]==1 for i,v in enumerate(before) if v==1))
        self.assertTrue(all(c[i]==0 for i,v in enumerate(m) if v!=0))

    def test_zero_gravity_preserves_all_state(self):
        n,c,f,m=fixture();before=(c.copy(),f.copy(),m.copy())
        step(c,f,m,n,709,1,(0,0))
        self.assertEqual((c,f,m),before)

    def test_high_drag_continues_evolving_without_losing_material(self):
        moved=0
        for seed in range(256):
            n=4;m=[1 if x in (0,3) or y in (0,3) else 0 for y in range(n) for x in range(n)]
            m[5]=2;c=[0.]*(n*n);f=[0.]*(n*n*9);before=Counter(m)
            for tick in range(256):step(c,f,m,n,seed,tick,(0,32767),drag_divisor=256)
            moved+=m[9]==2
            self.assertEqual(Counter(m),before)
        # Rare, reproducible transitions must remain possible; 8-bit truncation
        # would incorrectly freeze every seed at this resistance.
        self.assertGreater(moved,0)
        self.assertLess(moved,64)
