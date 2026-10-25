import unittest
from buoyant_loop_probe import paths
from grain_collective_reference import work


class BuoyantLoopProbeTests(unittest.TestCase):
    def test_mixed_column_can_lift_only_with_available_return_fluid(self):
        n=16;c=[0.]*(n*n)
        m=[int(x in (0,n-1) or y in (0,n-1)) for y in range(n) for x in range(n)]
        a=4*n+7;m[a]=2
        for y in range(5,10):c[y*n+7]=1.
        candidates=list(paths(c,m,n,a))
        self.assertTrue(candidates)
        for path in candidates:
            self.assertEqual(len(path),len(set(path)))
            self.assertNotIn(1,[m[i] for i in path])
            for i,j in zip(path,path[1:]+path[:1]):
                self.assertEqual(abs(i%n-j%n)+abs(i//n-j//n),1)
            self.assertLess(work(c,m,n,path,(0.,.00002),0.,0.),0.)
        # Sealing the top row blocks the return routes without removing gas.
        for x in range(1,n-1):
            if x!=7:m[3*n+x]=1
        self.assertEqual(list(paths(c,m,n,a)),[])

    def test_no_lift_candidate_without_gas(self):
        n=16;c=[0.]*(n*n);m=[0]*(n*n);m[4*n+7]=2
        self.assertEqual(list(paths(c,m,n,4*n+7)),[])
