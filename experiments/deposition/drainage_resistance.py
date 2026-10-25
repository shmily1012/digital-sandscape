"""Variational drainage reference, not a calibrated suspension model.

Minimize 1/2 v.D.v + 1/2 sum(h^2*q^2/m) - F.v subject to
Divergence(q + Bv)=0. D is positive background particle resistance;
it is NOT slip drag relative to sampled liquid velocity. B spreads solid
area flux. Eliminating q adds a positive drainage resistance, never a
replacement of mobility diagonal blocks. Geometry is frozen per step.
"""
import math
from experiments.liquid.grain_coupling import face_weights


def inverse_spd(matrix):
    n=len(matrix)
    lower=[[0.]*n for _ in range(n)]
    for i in range(n):
        for j in range(i+1):
            value=matrix[i][j]-sum(lower[i][k]*lower[j][k] for k in range(j))
            if i==j:
                if not math.isfinite(value) or value<=0:raise ValueError('Nonpositive resistance')
                lower[i][j]=math.sqrt(value)
            else:lower[i][j]=value/lower[j][j]
    result=[[0.]*n for _ in range(n)]
    for col in range(n):
        y=[0.]*n;x=[0.]*n
        for i in range(n):y[i]=((1. if i==col else 0.)-sum(lower[i][k]*y[k] for k in range(i)))/lower[i][i]
        for i in reversed(range(n)):x[i]=(y[i]-sum(lower[k][i]*x[k] for k in range(i+1,n)))/lower[i][i]
        for i in range(n):result[i][col]=x[i]
    return result


class DrainageResistance:
    def __init__(self,grid,grains,geometric=False):
        if not grains:raise ValueError('At least one grain required')
        self.grid=grid
        self.grains=list(grains)
        if geometric:
            from experiments.deposition.disk_volume import occupancy
            occupancy(grid,self.grains)
        self.columns=[]
        self.liquid_columns=[]
        for g in grains:
            weights=face_weights(grid,g)
            if geometric:
                from experiments.deposition.disk_volume import face_apertures
                weights=face_apertures(grid,g)
            for axis in range(2):
                column=[(w if geometric else math.pi*g.radius**2*w/grid.h**2) if a==axis else 0.
                        for w,(_,_,_,a) in zip(weights,grid.faces)]
                self.columns.append(column)
                self.liquid_columns.append(grid.project(column).liquid)
        n=2*len(grains)
        self.resistance=[[sum(grid.h**2*a*b/m for a,b,(_,_,m,_) in
                              zip(self.liquid_columns[i],self.liquid_columns[j],grid.faces))
                          +(grains[i//2].drag if i==j else 0.) for j in range(n)] for i in range(n)]
        self.mobility=inverse_spd(self.resistance)

    def flux(self,velocity):
        if len(velocity)!=len(self.columns) or any(not math.isfinite(v) for v in velocity):
            raise ValueError('Invalid velocity')
        solid=[sum(c[f]*v for c,v in zip(self.columns,velocity)) for f in range(len(self.grid.faces))]
        liquid=[sum(c[f]*v for c,v in zip(self.liquid_columns,velocity)) for f in range(len(self.grid.faces))]
        return solid,liquid

    def dissipation(self,velocity):
        _,q=self.flux(velocity)
        return sum(g.drag*(velocity[2*i]**2+velocity[2*i+1]**2) for i,g in enumerate(self.grains))+sum(self.grid.h**2*u*u/m for u,(_,_,m,_) in zip(q,self.grid.faces))
