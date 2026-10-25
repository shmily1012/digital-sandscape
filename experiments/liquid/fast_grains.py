"""Restricted dilute trajectory experiment; not a contact or bubble solver."""
from dataclasses import replace
import math
from experiments.liquid.grain_coupling import spread, sample
from experiments.liquid.kernel_self_response import estimate
from experiments.liquid.model import circle_mask


def dissipation_margin(block, drag):
    """Smallest eigenvalue of sym(I/drag - K).

    The carrier mobility is positive semidefinite by reciprocal transfer.
    A positive residual block is a sufficient, conservative work certificate
    for any particle forces; it does not certify accuracy or resolve contacts.
    """
    if len(block) != 4 or not all(math.isfinite(v) for v in block):
        raise ValueError('Finite self response required')
    if not math.isfinite(drag) or drag <= 0:
        raise ValueError('Positive finite drag required')
    a, d = 1/drag-block[0], 1/drag-block[3]
    b = -(block[1]+block[2])/2
    return (a+d)/2-math.hypot((a-d)/2, b)


def advance_fast(grid, grains, gravity, dt, kernel):
    if not math.isfinite(dt) or dt <= 0:
        raise ValueError('Positive finite dt required')
    if grid.active != circle_mask(grid.size):
        raise ValueError('Kernel requires the prescribed circular geometry')
    blocks = [estimate(grid, g, kernel) for g in grains]
    margins = [dissipation_margin(k, g.drag) for k, g in zip(blocks, grains)]
    if any(m <= 1e-8 for m in margins):
        raise ValueError('Fast path lacks sufficient dissipation margin')
    source, weights, force = spread(grid, grains, gravity)
    projection = grid.project(source)
    carrier = sample(grid, weights, projection.mixture)
    candidate = []
    for g, u, f, k in zip(grains, carrier, force, blocks):
        x = g.x+dt*(u[0]-k[0]*f[0]-k[1]*f[1]+f[0]/g.drag)
        y = g.y+dt*(u[1]-k[2]*f[0]-k[3]*f[1]+f[1]/g.drag)
        if not all(math.isfinite(v) for v in (x, y)) or math.hypot(x-.5, y-.5)+max(g.radius, 4*grid.h) >= .46:
            raise ValueError('Candidate leaves supported interior; contact model required')
        candidate.append(replace(g, x=x, y=y))
    # Reject even swept overlaps: endpoint-only tests can miss crossing grains.
    for i, g in enumerate(grains):
        for j in range(i):
            other = grains[j]
            dx, dy = g.x-other.x, g.y-other.y
            vx = candidate[i].x-candidate[j].x-dx
            vy = candidate[i].y-candidate[j].y-dy
            norm = vx*vx+vy*vy
            t = min(1, max(0, -(dx*vx+dy*vy)/norm)) if norm else 0
            if math.hypot(dx+t*vx, dy+t*vy) <= g.radius+other.radius:
                raise ValueError('Swept grain contact requires a contact solver')
    return candidate, projection, margins
