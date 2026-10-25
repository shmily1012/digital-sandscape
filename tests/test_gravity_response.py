"""Statistical force-response checks; no fluid collision or physical-unit calibration."""
from collections import Counter
import json
from pathlib import Path
import unittest
from phase_grains_reference import step


def settling_rates():
    n=8;results=[]
    for strength in (.00001,.00002,.00004):
        displacement={2:0.,3:0.,4:0.}
        for seed in range(512):
            m=[int(x in (0,n-1) or y in (0,n-1)) for y in range(n) for x in range(n)]
            for x,kind in ((1,2),(3,3),(5,4)):m[2*n+x]=kind
            c=[0.]*(n*n);f=[0.]*(n*n*9)
            for tick in range(6):step(c,f,m,n,seed,tick,(0,32767),gravity_scale=strength)
            for kind in displacement:displacement[kind]+=m.index(kind)//n-2
        results.append({'gravity':strength,'mean_displacement':{k:v/512 for k,v in displacement.items()}})
    return results


class GravityResponseTests(unittest.TestCase):
    def test_reducing_force_reduces_free_settling(self):
        rates=settling_rates()
        for kind in (2,3,4):
            weak,normal,strong=[r['mean_displacement'][kind] for r in rates]
            self.assertGreater(normal,0.)
            self.assertGreater(weak/normal,.3)
            self.assertLess(weak/normal,.8)
            self.assertGreater(strong/normal,1.5)
            self.assertLess(strong/normal,2.6)
        normal=rates[1]['mean_displacement']
        self.assertGreater(normal[2],normal[3]);self.assertGreater(normal[3],normal[4])

    def test_zero_strength_overrides_nonzero_direction(self):
        n=8;m=[0]*(n*n);m[4*n+4]=2;c=[0.]*(n*n);f=[0.]*(n*n*9)
        before=m.copy()
        for tick in range(100):step(c,f,m,n,709,tick,(0,32767),gravity_scale=0.)
        self.assertEqual(m,before)
        # A genuine fluid traction remains effective even when gravity vanishes.
        forces=[(0.,-.00008)]*(n*n)
        for tick in range(100):step(c,f,m,n,709,tick,(0,0),forces,gravity_scale=0.)
        self.assertLess(m.index(2)//n,4);self.assertEqual(Counter(m),Counter(before))


if __name__=='__main__':
    rates=settling_rates()
    (Path(__file__).resolve().parents[1]/'reports/gravity-response.json').write_text(json.dumps(rates,indent=2),encoding='utf-8')
    print(json.dumps(rates))
