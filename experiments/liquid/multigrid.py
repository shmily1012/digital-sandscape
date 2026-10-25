"""Aggregation multigrid for the existing sealed graph pressure operator.

Coarsening is algebraic P^T A P with piecewise-constant 2x2 injection.
It coarsens pressure corrections, NEVER particle/material state.
"""
from dataclasses import dataclass


@dataclass
class Level:
    size: int
    edges: list

    def __post_init__(self):
        self.neighbors=[[] for _ in range(self.size*self.size)]
        for i,j,w in self.edges:
            self.neighbors[i].append((j,w))
            self.neighbors[j].append((i,w))

    def apply(self,p):
        return [sum(w*(p[i]-p[j]) for j,w in row) for i,row in enumerate(self.neighbors)]

    def smooth(self,p,rhs,steps=3):
        for _ in range(steps):
            p=[p[i]+0.8*(rhs[i]-sum(w*(p[i]-p[j]) for j,w in row))/sum(w for _,w in row)
               if row else 0.0 for i,row in enumerate(self.neighbors)]
        return p


class Multigrid:
    def __init__(self,grid):
        if grid.size<4 or grid.size & (grid.size-1):
            raise ValueError('Power-of-two grid of at least four cells required')
        self.levels=[Level(grid.size,[(i,j,m/grid.h**2) for i,j,m,_ in grid.faces])]
        while self.levels[-1].size>4:
            fine=self.levels[-1]
            n=fine.size//2
            parent=lambda i: (i//fine.size//2)*n+(i%fine.size//2)
            edges={}
            for i,j,w in fine.edges:
                a,b=parent(i),parent(j)
                if a!=b:
                    key=(min(a,b),max(a,b))
                    edges[key]=edges.get(key,0)+w
            self.levels.append(Level(n,[(i,j,w) for (i,j),w in sorted(edges.items())]))

    def cycle(self,p,rhs,level=0):
        current=self.levels[level]
        if level==len(self.levels)-1:
            return current.smooth(p,rhs,32)
        p=current.smooth(p,rhs)
        residual=[a-b for a,b in zip(rhs,current.apply(p))]
        n=current.size//2
        coarse_rhs=[0.0]*(n*n)
        for i,r in enumerate(residual):
            coarse_rhs[(i//current.size//2)*n+i%current.size//2]+=r
        coarse=self.cycle([0.0]*(n*n),coarse_rhs,level+1)
        p=[v+coarse[(i//current.size//2)*n+i%current.size//2] for i,v in enumerate(p)]
        return current.smooth(p,rhs)

    def solve(self,rhs,tolerance=1e-8,max_cycles=256,initial=None):
        p=[0.0]*len(rhs) if initial is None else list(initial)
        if len(p)!=len(rhs):
            raise ValueError('Initial pressure shape mismatch')
        for cycle in range(max_cycles+1):
            residual=max(abs(a-b) for a,b in zip(rhs,self.levels[0].apply(p)))
            if residual<=tolerance:
                return p,cycle,residual
            if cycle<max_cycles:
                p=self.cycle(p,rhs)
        raise RuntimeError(f'Multigrid budget exhausted: residual={residual}')
