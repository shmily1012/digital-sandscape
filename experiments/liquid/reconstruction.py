"""Limited linear face reconstruction with a shared multi-material limiter.

Using one limiter per cell/axis preserves sum of fractions: the centered
slopes sum to zero and share the same scale. No normalization or clipping
of the conserved cell inventories is performed.
"""


def reconstruct(grid, channels):
    count=len(grid.active)
    neighbors=[[[None,None] for _ in range(count)] for _ in range(2)]
    for i,j,_,axis in grid.faces:
        neighbors[axis][i][1]=j
        neighbors[axis][j][0]=i
    slopes=[[[0.0]*count for _ in channels] for _ in range(2)]
    for axis in range(2):
        for i,(left,right) in enumerate(neighbors[axis]):
            if left is None or right is None:
                continue
            raw=[0.5*(c[right]-c[left]) for c in channels]
            limiter=1.0
            for c,s in zip(channels,raw):
                if s == 0:
                    continue
                low=min(c[left],c[i],c[right])
                high=max(c[left],c[i],c[right])
                allowance=2*min(c[i]-low,high-c[i])
                limiter=min(limiter,max(0.0,allowance/abs(s)))
            for k,s in enumerate(raw):
                # Stay just inside the bounds: a rounded negative face trace
                # would otherwise create outflow from an exactly empty phase.
                slopes[axis][k][i]=(limiter*(1-1e-14))*s
    positive,negative=[],[]
    for k,c in enumerate(channels):
        positive.append([c[i]+0.5*slopes[axis][k][i] for i,j,_,axis in grid.faces])
        negative.append([c[j]-0.5*slopes[axis][k][j] for i,j,_,axis in grid.faces])
    return positive,negative
