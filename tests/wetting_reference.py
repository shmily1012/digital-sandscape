"""Neutral glass and optional cubic grain surface energy, gas fraction c.

h(c) = sigma * cosine * (3*c*c - 2*c*c*c).
Positive cosine prefers liquid. Normal points from fluid into solid.
"""
import math


def face_phase(fluid_phase, cosine, width=4.):
    if not math.isfinite(cosine) or abs(cosine) > .95 or width < 4.:
        raise ValueError('Unsupported wetting configuration')
    if not 0 <= fluid_phase <= 1:
        raise ValueError('Invalid phase')
    # Independent bounded root solve of midpoint Robin boundary condition.
    if cosine == 0:
        return fluid_phase
    lower, upper = 0., 1.
    for _ in range(52):
        midpoint = (lower+upper)/2
        residual = midpoint+2*cosine/width*midpoint*(1-midpoint)-fluid_phase
        if residual > 0:
            upper = midpoint
        else:
            lower = midpoint
    return (lower+upper)/2
