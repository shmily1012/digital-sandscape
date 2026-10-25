import itertools
import math
import unittest
from grain_energy_reference import step, encoded_work, F
from grain_interface_work_reference import energy, fixtures, exchange_work, neighbor, DIRECTIONS


class GrainEnergyTests(unittest.TestCase):
    def test_encoded_work_matches_independent_global_energy(self):
        for case in fixtures():
            c,m,n=case['phase'],case['materials'],case['side']
            for a in range(n*n):
                if m[a]<2:continue
                for d in DIRECTIONS:
                    b=neighbor(a,d,n)
                    if b is None or m[b]:continue
                    actual=encoded_work(c,m,n,a,b,F(.01),F(case['cosine']))
                    expected=exchange_work(c,m,n,a,b,cosine=case['cosine'])
                    self.assertLess(abs(actual-expected),1e-8)

    def test_exchange_decreases_total_potential_and_preserves_inventory(self):
        for angle,(weight_scale,mobility_scale) in itertools.product((0,30,45,90,120,180,270),((1.,1.),(.7,1.),(1.4,1.),(1.,.5),(1.,2.))):
            case=fixtures()[0];c=case['phase'];m=case['materials'];n=case['side']
            f=[float(i) for i in range(n*n*9)];r=[float(i) for i in range(n*n)];stamps=[-1]*(n*n)
            inventory=sorted(m),sorted(c),sorted(f),sorted(r)
            gravity=(math.sin(math.radians(angle))*.00002,math.cos(math.radians(angle))*.00002)
            def potential():
                masses=[{0:0.,1:0.,2:2.,3:1.7,4:1.4}[material]*weight_scale-v for material,v in zip(m,c)]
                return energy(c,m,n)-sum(mass*(gravity[0]*(i%n)+gravity[1]*(i//n)) for i,mass in enumerate(masses))
            previous=potential()
            for tick in range(40):
                step(c,m,f,r,stamps,n,tick,20261024,gravity,weight_scale=weight_scale,mobility_scale=mobility_scale)
                current=potential();self.assertLessEqual(current,previous+1e-8);previous=current
            self.assertEqual((sorted(m),sorted(c),sorted(f),sorted(r)),inventory)

    def test_color_neighborhoods_have_no_cross_invocation_read_write_overlap(self):
        sources=[(4*x,4*y) for y in range(3) for x in range(3)]
        for a in sources:
            writes={(a[0]+dx,a[1]+dy) for dx in (-1,0,1) for dy in (-1,0,1)}
            for b in sources:
                if a==b:continue
                reads={(b[0]+dx,b[1]+dy) for dx in range(-2,3) for dy in range(-2,3)}
                self.assertFalse(writes & reads)
