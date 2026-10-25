"""Sparse geometric drainage operator; identical frozen-geometry quadratic law.

For q = -P_gradient Bv, H v = Dv - B^T Wq. One pressure solve per
application replaces stored 2N pressure response columns and dense H.
This is not yet a matrix-free contact solver.
"""
from dataclasses import dataclass
import math
from experiments.deposition.disk_volume import occupancy,face_apertures


@dataclass
class ResistanceSolution:
    velocity: list
    iterations: int
    pressure_solves: int
    residual: float


class MatrixFreeDrainage:
    def __init__(self,grid,grains):
        if not grains:raise ValueError('At least one grain required')
        occupancy(grid,grains)
        if any(not math.isfinite(g.drag) or g.drag<=0 for g in grains):raise ValueError('Positive resistance required')
        self.grid=grid
        self.drag=[g.drag for g in grains for _ in range(2)]
        self.columns=[]
        self.weight=[grid.h**2/m for _,_,m,_ in grid.faces]
        for g in grains:
            apertures=face_apertures(grid,g)
            for axis in range(2):
                self.columns.append([(f,w) for f,(w,(_,_,_,a)) in enumerate(zip(apertures,grid.faces)) if a==axis and w>0])
        self.pressure_solves=0
        self.last_liquid=[0.]*len(grid.faces)

    def apply(self,velocity):
        if len(velocity)!=len(self.drag) or any(not math.isfinite(v) for v in velocity):raise ValueError('Invalid vector')
        source=[0.]*len(self.grid.faces)
        for column,v in zip(self.columns,velocity):
            for f,w in column:source[f]+=w*v
        scale=max(map(abs,source),default=0.)
        if not scale:
            self.last_liquid=[0.]*len(self.grid.faces)
            return [d*v for d,v in zip(self.drag,velocity)]
        # Keep the inner pressure tolerance independent of the Krylov magnitude.
        q=[v*scale for v in self.grid.project([v/scale for v in source]).liquid]
        self.pressure_solves+=1
        self.last_liquid=q
        return [d*v-sum(w*self.weight[f]*q[f] for f,w in column)
                for d,v,column in zip(self.drag,velocity,self.columns)]

    def solve(self,force,tolerance=1e-10,max_iterations=128):
        if len(force)!=len(self.drag) or any(not math.isfinite(f) for f in force):raise ValueError('Invalid force')
        if not math.isfinite(tolerance) or tolerance<=0 or not isinstance(max_iterations,int) or not 1<=max_iterations<=1024:
            raise ValueError('Invalid solve budget')
        before=self.pressure_solves
        velocity=[0.]*len(force);residual=list(force)
        z=[r/d for r,d in zip(residual,self.drag)];direction=z.copy()
        rz=sum(a*b for a,b in zip(residual,z))
        for iteration in range(max_iterations+1):
            if max(map(abs,residual))<=tolerance:
                # Recompute the true residual; a recurrence alone is not a certificate.
                actual=[f-h for f,h in zip(force,self.apply(velocity))]
                error=max(map(abs,actual))
                if error<=tolerance:return ResistanceSolution(velocity,iteration,self.pressure_solves-before,error)
                residual=actual;z=[r/d for r,d in zip(residual,self.drag)]
                direction=z.copy();rz=sum(a*b for a,b in zip(residual,z))
            if iteration==max_iterations:break
            applied=self.apply(direction)
            denominator=sum(a*b for a,b in zip(direction,applied))
            if not math.isfinite(denominator) or denominator<=0:raise ValueError('Operator lost positive work')
            alpha=rz/denominator
            velocity=[v+alpha*p for v,p in zip(velocity,direction)]
            residual=[r-alpha*h for r,h in zip(residual,applied)]
            z=[r/d for r,d in zip(residual,self.drag)]
            new_rz=sum(a*b for a,b in zip(residual,z));beta=new_rz/rz
            direction=[a+beta*b for a,b in zip(z,direction)];rz=new_rz
        raise ValueError('Resistance solve budget exhausted; no candidate returned')
