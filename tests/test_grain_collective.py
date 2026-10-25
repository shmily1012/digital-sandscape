import itertools
import unittest
from grain_collective_reference import paths,work,apply,fixtures,WEIGHT
from grain_interface_work_reference import energy,exchange_work


class GrainCollectiveTests(unittest.TestCase):
    def test_upper_obstruction_does_not_pin_legal_lower_loop(self):
        case=fixtures()[7];n=case['side'];m=case['materials'];stamps=[-1]*(n*n)
        candidates=paths(m,stamps,n,9*n+12,0,(0.,.00002))
        self.assertEqual(len(candidates),2)
        for path in candidates:
            self.assertEqual(path[:2],[8*n+12,9*n+12])
            self.assertEqual(len(path),6)
            self.assertTrue(all(m[i]==0 for i in path[2:]))
            for i,j in zip(path,path[1:]+path[:1]):
                self.assertEqual(abs(i%n-j%n)+abs(i//n-j//n),1)
        for y in (6,7):
            self.assertEqual(case['expected_materials'][y*n+12],m[y*n+12])
        self.assertNotEqual(case['expected_materials'][9*n+12],m[9*n+12])
        self.assertEqual(sorted(case['expected_materials']),sorted(m))
        self.assertEqual(sorted(case['expected_phase']),sorted(case['phase']))
        self.assertEqual(sorted(case['expected_populations']),sorted(case['populations']))
        # An upper particle already moved this tick cannot freeze lower neighbors.
        stamps[7*n+12]=0
        self.assertEqual(paths(m,stamps,n,9*n+12,0,(0.,.00002)),candidates)
        stamps[8*n+12]=0
        self.assertEqual(paths(m,stamps,n,9*n+12,0,(0.,.00002)),[])

    def test_collective_weight_can_cross_a_single_grain_energy_barrier(self):
        case=fixtures()[5];c,m,n=case['phase'],case['materials'],case['side'];a=13*n+12
        path=paths(m,[-1]*(n*n),n,a,0,(0.,.00002))[0]
        single=exchange_work(c,m,n,a,a+n,cosine=.5)-(2+c[a+n])*.00002
        self.assertGreater(single,1e-5)
        self.assertLess(work(c,m,n,path,(0.,.00002),.01,.5),-1e-5)
        self.assertNotEqual(case['materials'],case['expected_materials'])

    def test_local_loop_work_equals_full_energy_change(self):
        case=fixtures()[2];n=case['side'];c=case['phase'];m=case['materials']
        f=case['populations'];r=case['residual'];stamps=[-1]*(n*n)
        gravity=(0.,.00002)
        candidates=paths(m,stamps,n,9*n+12,0,gravity)
        self.assertEqual(len(candidates),2)
        for path in candidates:
            for cosine,weight_scale in itertools.product((-.5,0.,.5),(.7,1.,1.4)):
                def potential(gas,material):
                    return energy(gas,material,n,cosine=cosine)-sum(
                        (WEIGHT.get(v,0.)*weight_scale-gas[i])*.00002*(i//n) for i,v in enumerate(material))
                before=potential(c,m)
                cc,mm,ff,rr,ss=c.copy(),m.copy(),f.copy(),r.copy(),stamps.copy()
                apply(cc,mm,ff,rr,ss,path,0)
                self.assertAlmostEqual(potential(cc,mm)-before,work(c,m,n,path,gravity,.01,cosine,weight_scale),delta=2e-8)
                self.assertEqual((sorted(cc),sorted(mm),sorted(ff),sorted(rr)),(sorted(c),sorted(m),sorted(f),sorted(r)))
                for k,i in enumerate(path):
                    j=path[(k+1)%len(path)]
                    self.assertEqual(abs(i%n-j%n)+abs(i//n-j//n),1)
                for i in path:
                    if mm[i]>=2:self.assertEqual(ss[i],0)

    def test_blocked_return_path_rejects_without_moving(self):
        case=fixtures()[1]
        self.assertEqual(case['materials'],case['expected_materials'])
        self.assertEqual(case['phase'],case['expected_phase'])
        self.assertEqual(case['populations'],case['expected_populations'])
        self.assertEqual(case['expected_moved'],[-1]*(case['side']**2))
        self.assertNotEqual(fixtures()[0]['materials'],fixtures()[0]['expected_materials'])

    def test_collective_color_footprints_are_disjoint(self):
        for sign in (-1,1):
            origins=[(4*x,12*y) for x in range(3) for y in range(3)]
            for a in origins:
                writes={(a[0]+dx,a[1]+sign*dy) for dx in (-1,0,1) for dy in range(-7,2)}
                for b in origins:
                    if a==b:continue
                    reads={(b[0]+dx,b[1]+sign*dy) for dx in range(-2,3) for dy in range(-8,3)}
                    self.assertFalse(writes & reads)
