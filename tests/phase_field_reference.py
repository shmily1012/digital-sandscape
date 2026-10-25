"""Finite-volume reference for the candidate gas fraction transport operator.

This is not a fluid solver. Face velocities are inputs from the future LBM pass.
Each face has one signed transfer; limiting preserves that shared transfer.
"""
import math


def step(c, side, velocity, solid, dt=0.1, mobility=0.02, width=4.0, wetting_cosine=0.):
    if (side < 3 or len(c) != side * side or len(solid) != len(c)
            or len(velocity) != len(c) or not math.isfinite(dt) or dt <= 0
            or not math.isfinite(mobility) or mobility < 0
            or not math.isfinite(width) or width <= 0):
        raise ValueError('Invalid phase configuration')
    if any(not math.isfinite(v) or not 0 <= v <= 1 for v in c):
        raise ValueError('Invalid gas fraction')
    if any(len(v) != 2 or not all(math.isfinite(x) for x in v) for v in velocity):
        raise ValueError('Invalid face velocity input')
    if any(w and c[i] != 0 for i, w in enumerate(solid)):
        raise ValueError('Gas inside solid')

    def neighbor(i, dx, dy):
        x, y = i % side + dx, i // side + dy
        if not (0 <= x < side and 0 <= y < side):
            return i
        j = y * side + x
        return i if solid[j] else j

    if not math.isfinite(wetting_cosine) or abs(wetting_cosine)>.95:
        raise ValueError('Unsupported wetting configuration')
    def sample(i,dx,dy):
        x,y=i%side+dx,i//side+dy
        if not (0<=x<side and 0<=y<side):return c[i]
        j=y*side+x
        if not solid[j]:return c[j]
        if solid[j]<2 or wetting_cosine==0:return c[i]
        from wetting_reference import face_phase
        return 2*face_phase(c[i],wetting_cosine,width)-c[i]
    grad = [((sample(i, 1, 0) - sample(i, -1, 0)) * 0.5,
             (sample(i, 0, 1) - sample(i, 0, -1)) * 0.5)
            for i in range(len(c))]
    faces = []
    incoming, outgoing = [0.] * len(c), [0.] * len(c)
    for i in range(len(c)):
        if solid[i]:
            continue
        for axis, (dx, dy) in enumerate(((1, 0), (0, 1))):
            j = neighbor(i, dx, dy)
            if j == i:
                continue
            speed = (velocity[i][axis] + velocity[j][axis]) * 0.5
            face_c = (c[i] + c[j]) * 0.5
            gx, gy = (grad[i][0] + grad[j][0]) * 0.5, (grad[i][1] + grad[j][1]) * 0.5
            # Reconstruct orientation from neighboring centered gradients.
            # Keep the raw face difference only in the diffusive flux.
            magnitude = math.hypot(gx, gy)
            normal = (gx if axis == 0 else gy) / math.sqrt(magnitude*magnitude + (0.08/width)**2)
            sharpening = 4 * face_c * (1 - face_c) / width * normal
            flux = speed * (c[i] if speed >= 0 else c[j]) - mobility * (c[j] - c[i] - sharpening)
            amount = dt * flux
            donor, receiver = (i, j) if amount >= 0 else (j, i)
            amount = abs(amount)
            outgoing[donor] += amount
            incoming[receiver] += amount
            faces.append((donor, receiver, amount))
    # A donor cannot export more gas than it owns, nor can a receiver overfill.
    # Both sides use one limited flux; never clip individual output fractions.
    donor_scale = [min(1., c[i] / q) if q > 0 else 1. for i, q in enumerate(outgoing)]
    receiver_scale = [min(1., (1 - c[i]) / q) if q > 0 else 1. for i, q in enumerate(incoming)]
    result = c.copy()
    limited = 0
    for donor, receiver, amount in faces:
        factor = min(donor_scale[donor], receiver_scale[receiver])
        limited += factor < 1.
        transfer = amount * factor
        result[donor] -= transfer
        result[receiver] += transfer
    return result, limited


def circle(side, center, radius, width=4.):
    solid = [math.hypot(x - (side - 1) / 2, y - (side - 1) / 2) >= side / 2 - 2
             for y in range(side) for x in range(side)]
    c = [0. if solid[y * side + x] else
         0.5 * (1 - math.tanh(2 * (math.hypot(x - center[0], y - center[1]) - radius) / width))
         for y in range(side) for x in range(side)]
    return c, solid


if __name__ == '__main__':
    import json
    from pathlib import Path
    n = 24
    initial, wall = circle(n, (11., 12.), 4.)
    c = initial.copy()
    for _ in range(80):
        c, _ = step(c, n, [(0.04, -0.07)] * (n*n), wall)
    target = Path(__file__).resolve().parents[1] / 'reports/phase-fixture.json'
    target.write_text(json.dumps(dict(side=n, steps=80, initial=initial,
                                    wall=[int(w) for w in wall], expected=c,
                                    mass=math.fsum(initial))), encoding='utf-8')
