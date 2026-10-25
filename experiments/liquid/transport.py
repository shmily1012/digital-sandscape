"""Conservative multi-material drift/return-flow experiment.

All fractions share a pressure-induced carrier velocity, with prescribed
relative drifts. This closes volume continuity but not contact mechanics,
capillarity, drag feedback, or a calibrated concentrated suspension law.
"""
from dataclasses import dataclass
import math

from experiments.liquid.model import DarcyGrid
from experiments.liquid.reconstruction import reconstruct


@dataclass
class TransportReport:
    substeps: int
    max_divergence: float
    max_volume_error: float


class DriftMixture:
    def __init__(self, grid: DarcyGrid, fractions, slips, scheme='upwind'):
        if scheme not in ('upwind','muscl'):
            raise ValueError('Unknown transport scheme')
        self.scheme=scheme
        self.grid = grid
        self.fractions = [list(channel) for channel in fractions]
        self.slips = list(slips)
        self.time = 0.0
        if len(fractions) != len(slips) or not fractions:
            raise ValueError('One velocity per material required')
        if any(len(channel) != len(grid.active) for channel in fractions):
            raise ValueError('Fraction shape mismatch')
        if any(not math.isfinite(v) for slip in slips for v in slip):
            raise ValueError('Finite slip velocities required')
        for i, active in enumerate(grid.active):
            values = [channel[i] for channel in fractions]
            if any(not math.isfinite(v) or v < 0 for v in values):
                raise ValueError('Nonnegative finite fractions required')
            if abs(sum(values)-(1 if active else 0)) > 1e-12:
                raise ValueError('Each active cell must be filled exactly once')

    def inventory(self):
        return [sum(channel)*self.grid.h**2 for channel in self.fractions]

    def face_fluxes(self):
        grid, channels = self.grid, self.fractions
        if self.scheme == 'muscl':
            positive,negative=reconstruct(grid,channels)
        else:
            positive=[[c[i] for i,j,_,axis in grid.faces] for c in channels]
            negative=[[c[j] for i,j,_,axis in grid.faces] for c in channels]
        drift = []
        for k,slip in enumerate(self.slips):
            drift.append([slip[axis]*(positive[k][f] if slip[axis]>=0 else negative[k][f])
                          for f,(i,j,_,axis) in enumerate(grid.faces)])
        prescribed = [sum(channel[k] for channel in drift) for k in range(len(grid.faces))]
        projected = grid.project(prescribed)
        # Here projected.liquid is interpreted as the COMMON carrier velocity.
        # The actual liquid volume flux is its liquid-fraction-weighted part.
        fluxes=[]
        for k,relative in enumerate(drift):
            fluxes.append([r+u*(positive[k][f] if u>=0 else negative[k][f])
                           for f,(r,u) in enumerate(zip(relative,projected.liquid))])
        return fluxes, projected

    def stable_step(self, fluxes, requested):
        h=requested
        for channel,flux in zip(self.fractions,fluxes):
            outflow=[0.0]*len(channel)
            for q,(i,j,_,_) in zip(flux,self.grid.faces):
                outflow[i if q>0 else j] += abs(q)/self.grid.h
            for amount,rate in zip(channel,outflow):
                if rate>0:
                    h=min(h,0.9*amount/rate)
        return h

    def euler_state(self, fluxes, h):
        return [[v-h*d for v,d in zip(c,self.grid.divergence(f))]
                for c,f in zip(self.fractions,fluxes)]

    def advance(self, dt, max_substeps=128):
        if not math.isfinite(dt) or dt < 0:
            raise ValueError('Nonnegative finite time required')
        remaining, steps, peak_divergence = dt, 0, 0.0
        while remaining > 1e-14:
            if steps >= max_substeps:
                # Already completed substeps remain a valid, explicitly timed state.
                raise RuntimeError('Transport substep budget exhausted')
            fluxes, projection = self.face_fluxes()
            peak_divergence = max(peak_divergence,projection.residual)
            h = self.stable_step(fluxes,remaining)
            if h <= 1e-14:
                raise RuntimeError('Transport requires a smaller stable timestep')
            original=self.fractions
            if self.scheme == 'muscl':
                accepted=None
                try:
                    for retry in range(16):
                        self.fractions=original
                        self.fractions=self.euler_state(fluxes,h)
                        second,projection2=self.face_fluxes()
                        peak_divergence=max(peak_divergence,projection2.residual)
                        if self.stable_step(second,h) < h*(1-1e-12):
                            h*=0.5
                            continue
                        final=self.euler_state(second,h)
                        accepted=[[0.5*(a+b) for a,b in zip(c,d)] for c,d in zip(original,final)]
                        break
                    if accepted is None:
                        raise RuntimeError('SSP stage retry budget exhausted')
                finally:
                    self.fractions=original
                self.fractions=accepted
            else:
                self.fractions=self.euler_state(fluxes,h)
            remaining-=h
            self.time+=h
            steps+=1
        volume_error=max(abs(sum(c[i] for c in self.fractions)-(1 if a else 0))
                         for i,a in enumerate(self.grid.active))
        return TransportReport(steps,peak_divergence,volume_error)
