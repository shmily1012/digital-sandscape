"""Discrete interface energy for the existing phase/wetting parameters.

This measures work for a conservative voxel exchange. It does not supply fluid
pressure work, kinetic momentum, contacts, or a complete grain integrator.
"""
import json
import math
from pathlib import Path
from wetting_reference import face_phase

DIRECTIONS = ((1, 0), (0, 1), (-1, 0), (0, -1))


def bond(ca, ma, cb, mb, sigma=.01, width=4., cosine=0.):
    kappa = 1.5*sigma*width
    if ma and mb:
        return 0.
    if not ma and not mb:
        return .5*kappa*(ca-cb)**2
    cf, solid = (cb, ma) if ma else (ca, mb)
    preference = cosine if solid >= 2 else 0.
    surface = face_phase(cf, preference, width)
    # Minimize a half-cell gradient energy plus cubic solid surface energy.
    # Stationarity gives the same midpoint Robin boundary as phase_transport.
    return kappa*(surface-cf)**2 + sigma*preference*(3*surface**2-2*surface**3)


def neighbor(i, direction, n):
    x, y = i % n+direction[0], i//n+direction[1]
    return y*n+x if 0 <= x < n and 0 <= y < n else None


def energy(c, m, n, sigma=.01, width=4., cosine=0.):
    terms = [12*sigma/width*v*v*(1-v)**2 for v, material in zip(c, m) if not material]
    for i in range(n*n):
        for d in DIRECTIONS[:2]:
            j = neighbor(i, d, n)
            if j is not None:
                terms.append(bond(c[i], m[i], c[j], m[j], sigma, width, cosine))
    return math.fsum(terms)


def exchange_work(c, m, n, a, b, sigma=.01, width=4., cosine=0., allow_diagonal=False):
    directions = DIRECTIONS+((1,1),(-1,1),(-1,-1),(1,-1)) if allow_diagonal else DIRECTIONS
    if m[a] < 2 or m[b] != 0 or b not in [neighbor(a, d, n) for d in directions]:
        raise ValueError('Expected adjacent grain and fluid')
    edges = {tuple(sorted((i, j))) for i in (a, b) for d in DIRECTIONS
             if (j := neighbor(i, d, n)) is not None}
    swapped = lambda i: b if i == a else a if i == b else i
    # Bulk energy cancels exactly: the fluid packet and grain exchange positions.
    return math.fsum(bond(c[swapped(i)], m[swapped(i)], c[swapped(j)], m[swapped(j)], sigma, width, cosine)
                     - bond(c[i], m[i], c[j], m[j], sigma, width, cosine) for i, j in edges)


def fixtures():
    cases = []
    n = 12
    for cosine in (0., .5, -.5):
        m = [int(x in (0,n-1) or y in (0,n-1)) for y in range(n) for x in range(n)]
        for i in (5*n+5, 6*n+5, n+1):
            m[i] = 2+i%3
        c = [0. if m[i] else .5*(1+math.tanh((i//n-5.75)/2)) for i in range(n*n)]
        # Encode actual float32 inputs before computing the independent oracle.
        import struct
        c = list(struct.unpack('<%df' % len(c), struct.pack('<%df' % len(c), *c)))
        work = [0.]*(4*n*n)
        mask = [0]*(n*n)
        for a in range(n*n):
            if m[a] < 2:
                continue
            for q, d in enumerate(DIRECTIONS):
                b = neighbor(a, d, n)
                if b is not None and m[b] == 0:
                    mask[a] |= 1 << q
                    work[4*a+q] = exchange_work(c, m, n, a, b, cosine=cosine)
        cases.append(dict(side=n, cosine=cosine, phase=c, materials=m, work=work, mask=mask))
    return cases


if __name__ == '__main__':
    (Path(__file__).resolve().parents[1]/'reports/grain-interface-work-fixture.json').write_text(json.dumps(fixtures()))
