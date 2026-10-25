"""Bounded CPU coupling of two-phase geometry, capillarity and Darcy pressure."""
import math

from experiments.liquid.capillary import height_curvature,split_capillary_pressure
from experiments.liquid.geometric_transport import advect


class SurfaceCell:
    def __init__(self,grid,fraction,tension=0.01):
        if not math.isfinite(tension) or tension<0:
            raise ValueError('Nonnegative finite tension required')
        if len(fraction)!=len(grid.active) or any(not math.isfinite(v) or v<0 or v>1 for v in fraction):
            raise ValueError('Invalid initial phase fraction')
        self.grid=grid
        self.fraction=list(fraction)
        self.tension=tension
        self.time=0.0
        self.steps=0

    def capillary_step_limit(self):
        mobility=max((f[2] for f in self.grid.faces),default=0)
        # Darcy capillary relaxation scales as M*sigma*k^3, unlike inertial CFD.
        # Safety factor is an experimental choice, not a proof for all geometry.
        return 0.02*self.grid.h**3/(mobility*self.tension) if mobility*self.tension>0 else math.inf

    def step(self,requested_dt):
        if not math.isfinite(requested_dt) or requested_dt<=0:
            raise ValueError('Positive finite timestep required')
        curvature=height_curvature(self.grid.size,self.fraction)
        base,forcing=split_capillary_pressure(self.grid,self.fraction,curvature,self.tension)
        pressure=self.grid.project(forcing)
        proposed=min(requested_dt,self.capillary_step_limit())
        updated,dt=advect(self.grid,self.fraction,pressure.mixture,proposed)
        # Commit only a completed substep; geometry/pressure errors leave state intact.
        self.fraction=updated
        self.time+=dt
        self.steps+=1
        return dict(dt=dt,max_speed=max(map(abs,pressure.mixture),default=0),
                    divergence=pressure.residual,pressure_iterations=pressure.iterations,
                    base_pressure=base,residual_pressure=pressure.pressure)

    def advance(self,requested_dt,max_substeps=128):
        if not math.isfinite(requested_dt) or requested_dt<0 or max_substeps<1:
            raise ValueError('Invalid bounded advancement request')
        remaining=requested_dt
        count=0
        while remaining>1e-14:
            if count>=max_substeps:
                raise RuntimeError('Capillary substep budget exhausted; time reflects accepted steps')
            result=self.step(remaining)
            remaining-=result['dt']
            count+=1
        return count
