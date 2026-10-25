"""Sealed finite-volume Darcy projection, independent of phase advection.

Given prescribed inclusion volume flux j, find liquid flux -M grad(p) such
that div(j - M grad(p)) = 0. This is an instantaneous mixture constraint,
not a complete particle/fluid/interface coupling law. Units are consistent
if j is m/s, spacing m, and M m^2/(Pa s); examples are dimensionless.
"""
from dataclasses import dataclass
import math


def add_compensated(high,low,increment):
    """TwoSum accumulation, retaining updates below the pressure datum ULP."""
    total=high+increment;virtual=total-high
    error=(high-(total-virtual))+(increment-virtual)
    tail=math.fsum((low,error));result=total+tail;virtual=result-total
    return result,(total-(result-virtual))+(tail-virtual)


def incomplete_cholesky(rows):
    """Bounded shifted IC(0) preconditioner; shifts never change the operator.

    Symmetric sparse rows are scaled to unit diagonal. Failed pivots try four
    fixed shifts, then reject; no dense fill, dropped geometry or RHS edits.
    """
    n=len(rows)
    scale=[1/math.sqrt(row.get(i,0.) or 1.) for i,row in enumerate(rows)]
    for shift in (1e-6,1e-3,.1,1.):
        lower=[{} for _ in rows];diag=[];valid=True
        for i,row in enumerate(rows):
            for j in sorted(k for k in row if k<i):
                value=row[j]*scale[i]*scale[j]
                value-=math.fsum(v*lower[j].get(k,0.) for k,v in lower[i].items() if k<j)
                lower[i][j]=value/diag[j]
            pivot=1.+shift-math.fsum(v*v for v in lower[i].values())
            if not math.isfinite(pivot) or pivot<=1e-14:
                valid=False;break
            diag.append(math.sqrt(pivot))
        if not valid:continue
        upper=[[] for _ in rows]
        for i,row in enumerate(lower):
            for j,value in row.items():upper[j].append((i,value))
        def apply(rhs):
            y=[0.]*n
            for i in range(n):
                y[i]=(rhs[i]*scale[i]-math.fsum(v*y[j] for j,v in lower[i].items()))/diag[i]
            z=[0.]*n
            for i in reversed(range(n)):
                z[i]=(y[i]-math.fsum(v*z[j] for j,v in upper[i]))/diag[i]
            return [a*b for a,b in zip(z,scale)]
        return apply,shift
    raise RuntimeError('Incomplete Cholesky pivot budget exhausted')


@dataclass
class Projection:
    pressure: list
    liquid: list
    mixture: list
    iterations: int
    residual: float


class DarcyGrid:
    """One oriented face per active cell pair; absent faces are sealed walls."""
    def __init__(self, size, active=None, mobility=None):
        if size < 2:
            raise ValueError('Grid must have at least two cells per axis')
        self.size, self.h = size, 1/size
        count = size*size
        self.active = list(active) if active is not None else [True]*count
        m = list(mobility) if mobility is not None else [1.0]*count
        if len(self.active) != count or len(m) != count:
            raise ValueError('Grid field size mismatch')
        if not any(self.active) or any(not math.isfinite(v) or v <= 0 for v in m):
            raise ValueError('Positive finite mobility and nonempty domain required')
        self.faces = []  # (left/top cell, right/bottom cell, mobility, axis)
        self.neighbors = [[] for _ in range(count)]
        for y in range(size):
            for x in range(size):
                i = y*size+x
                if not self.active[i]:
                    continue
                for axis, j, allowed in ((0, i+1, x+1<size), (1, i+size, y+1<size)):
                    if allowed and self.active[j]:
                        coefficient = 2*m[i]*m[j]/(m[i]+m[j])
                        self.faces.append((i, j, coefficient, axis))
                        weight = coefficient/self.h**2
                        self.neighbors[i].append((j, weight))
                        self.neighbors[j].append((i, weight))

    def divergence(self, flux):
        if len(flux) != len(self.faces) or any(not math.isfinite(v) for v in flux):
            raise ValueError('Invalid face flux')
        result = [0.0]*len(self.active)
        for value, (i, j, _, _) in zip(flux, self.faces):
            result[i] += value/self.h
            result[j] -= value/self.h
        return result

    def operator(self, pressure, low=None):
        if low is not None:
            contributions=[[] for _ in self.active]
            for q,(i,j,_,_) in zip(self.liquid_flux(pressure,low),self.faces):
                contributions[i].append(q/self.h);contributions[j].append(-q/self.h)
            return [math.fsum(values) for values in contributions]
        result = [0.0]*len(self.active)
        for i, j, mobility, _ in self.faces:
            transfer = mobility*(pressure[i]-pressure[j])/self.h**2
            result[i] += transfer
            result[j] -= transfer
        return result

    def liquid_flux(self, pressure, low=None):
        if low is not None:
            return [m*math.fsum((pressure[i],-pressure[j],low[i],-low[j]))/self.h for i,j,m,_ in self.faces]
        return [-m*(pressure[j]-pressure[i])/self.h for i, j, m, _ in self.faces]

    @classmethod
    def from_graph(cls, count, edges):
        """Reuse the pressure operator on a non-Cartesian reference network.

        Edges are (i,j,positive conductance). Geometry-specific grid helpers
        do not apply; each network flux is an oriented volume rate.
        """
        if not isinstance(count,int) or count<1:raise ValueError('Empty network')
        grid=cls.__new__(cls)
        grid.size=None;grid.h=1.;grid.active=[True]*count
        grid.faces=[];grid.neighbors=[[] for _ in range(count)]
        for i,j,weight in edges:
            if not (0<=i<count and 0<=j<count) or i==j or not math.isfinite(weight) or weight<=0:
                raise ValueError('Invalid pressure edge')
            grid.faces.append((i,j,weight,0))
            grid.neighbors[i].append((j,weight));grid.neighbors[j].append((i,weight))
        return grid

    def pressure_for_source(self, rhs, tolerance=1e-10, max_iterations=2048, apply=None, diagonal=None, compensated=False, apply_compensated=None, precondition=None):
        self.last_pressure_low=None
        if not math.isfinite(tolerance) or tolerance <= 0 or not isinstance(max_iterations,int) or max_iterations < 1:
            raise ValueError('Positive tolerance and bounded iteration count required')
        if len(rhs)!=len(self.active) or any(not math.isfinite(v) for v in rhs):
            raise ValueError('Invalid pressure source')
        rhs=list(rhs)
        if compensated and apply is not None and apply_compensated is None:raise ValueError('Compensated custom operator requires a low-part implementation')
        apply=self.operator if apply is None else apply
        if diagonal is not None and (len(diagonal)!=len(rhs) or any(not math.isfinite(x) or x<=0 for x in diagonal)):
            raise ValueError('Invalid pressure preconditioner')
        if precondition is not None and diagonal is not None:raise ValueError('Choose one preconditioner')
        def conditioned(values):
            if precondition is not None:return precondition(values)
            return [v/d for v,d in zip(values,diagonal)] if diagonal is not None else values.copy()
        p = [0.0]*len(rhs)
        low=[0.]*len(rhs)
        def actual_operator():
            if not compensated:return apply(p)
            return apply_compensated(p,low) if apply_compensated is not None else self.operator(p,low)
        r=rhs.copy()
        z=conditioned(r)
        direction=z.copy();norm=sum(a*b for a,b in zip(r,z))
        iteration = 0
        while iteration<=max_iterations:
            if max(map(abs,r),default=0)<=tolerance:
                # Recurrence convergence is not a certificate on thin cells.
                # Refresh and restart within the original iteration budget.
                actual=[b-a for a,b in zip(actual_operator(),rhs)]
                if max(map(abs,actual),default=0)<=tolerance:break
                r=actual
                z=conditioned(r)
                direction=z.copy();norm=sum(a*b for a,b in zip(r,z))
            if iteration==max_iterations:break
            applied = apply(direction)
            denominator = sum(a*b for a, b in zip(direction, applied))
            if denominator <= 0:
                raise RuntimeError('Pressure system lost positive semidefiniteness')
            alpha = norm/denominator
            if compensated:
                pairs=[add_compensated(a,c,alpha*b) for a,b,c in zip(p,direction,low)]
                p=[a for a,_ in pairs];low=[b for _,b in pairs]
            else:p = [a+alpha*b for a, b in zip(p, direction)]
            r = [a-alpha*b for a, b in zip(r, applied)]
            z=conditioned(r)
            new_norm = sum(a*b for a,b in zip(r,z))
            beta = new_norm/norm
            direction = [a+beta*b for a, b in zip(z, direction)]
            norm = new_norm
            iteration += 1
        residual=max((abs(a-b) for a,b in zip(actual_operator(),rhs)),default=0.)
        if not math.isfinite(residual) or residual>tolerance*1.1:
            error=RuntimeError(f'Pressure solve did not converge: residual={residual}')
            # Diagnostic candidates live only on the exception, never in an
            # accepted solution or last_pressure_low.
            error.pressure_diagnostic=dict(pressure=p,low=low,iterations=iteration,residual=residual)
            raise error
        self.last_pressure_low=low if compensated else None
        return p,iteration,residual

    def project(self, prescribed, tolerance=1e-10, max_iterations=2048):
        rhs = [-v for v in self.divergence(prescribed)]
        p,iteration,_=self.pressure_for_source(rhs,tolerance,max_iterations)
        liquid = self.liquid_flux(p)
        mixture = [a+b for a, b in zip(prescribed, liquid)]
        residual = max(map(abs, self.divergence(mixture)), default=0)
        if residual > tolerance*1.1:
            raise RuntimeError(f'Pressure solve did not converge: residual={residual}')
        return Projection(p, liquid, mixture, iteration, residual)

    def jacobi(self, prescribed, steps, relaxation=0.8):
        """Bounded GPU reference; convergence is measured, never assumed."""
        rhs = [-v for v in self.divergence(prescribed)]
        p = [0.0]*len(rhs)
        for _ in range(steps):
            updated = p.copy()
            for i, neighbors in enumerate(self.neighbors):
                diagonal = sum(weight for _, weight in neighbors)
                if diagonal:
                    target = (rhs[i]+sum(weight*p[j] for j, weight in neighbors))/diagonal
                    updated[i] += relaxation*(target-p[i])
            p = updated
        return p

    def prescribed_patch(self, center=(0.5, 0.5), radius=0.2, velocity=(0, 0.1)):
        """Smooth prescribed inclusion flux, not a rasterized physical bubble."""
        flux = []
        for i, j, _, axis in self.faces:
            x = ((i%self.size+j%self.size)/2+0.5)*self.h
            y = ((i//self.size+j//self.size)/2+0.5)*self.h
            distance2 = ((x-center[0])**2+(y-center[1])**2)/radius**2
            fraction = max(0.0, 1-distance2)**2
            flux.append(fraction*velocity[axis])
        return flux


def circle_mask(size):
    return [((x+0.5)/size-0.5)**2+((y+0.5)/size-0.5)**2 < 0.46**2
            for y in range(size) for x in range(size)]
