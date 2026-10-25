"""Face-paired neutral-boundary capillary stress for the existing PhaseFluid."""
import json
import math
from pathlib import Path
from wetting_reference import face_phase


def forces(c, material, side, sigma=.01, width=4., wetting_cosine=0.):
    directions = ((1, 0), (0, 1), (-1, 0), (0, -1))
    def neighbor(i, d):
        x, y = i % side+d[0], i // side+d[1]
        return y*side+x if 0 <= x < side and 0 <= y < side else None
    def gradient(i):
        values = []
        for d in directions:
            j = neighbor(i, d)
            values.append(c[i] if j is None else
                          2*face_phase(c[i],wetting_cosine if material[j]>=2 else 0.,width)-c[i]
                          if material[j] else c[j])
        return ((values[0]-values[2])/2, (values[1]-values[3])/2)
    def stress(i, normal=None, solid=None):
        g = list(gradient(i))
        phase=c[i]
        if normal is not None:
            phase=face_phase(c[i],wetting_cosine if material[solid]>=2 else 0.,width)
            projection = sum(a*b for a, b in zip(g, normal))
            g = [a-projection*b+2*(phase-c[i])*b for a, b in zip(g, normal)]
        kappa = 1.5*sigma*width
        bulk = 12*sigma/width*phase**2*(1-phase)**2
        diagonal = bulk+.5*kappa*sum(x*x for x in g)
        return [[(diagonal if a == b else 0)-kappa*g[a]*g[b]
                 for b in range(2)] for a in range(2)]
    result = [[0., 0.] for _ in c]
    # Visit each face once and distribute its equal/opposite traction.
    for i in range(len(c)):
        for normal in directions[:2]:
            j = neighbor(i, normal)
            if j is None or (material[i] and material[j]):
                continue
            if not material[i] and not material[j]:
                a, b = stress(i), stress(j)
                tensor = [[(a[x][y]+b[x][y])/2 for y in range(2)] for x in range(2)]
            else:
                tensor = stress(j if material[i] else i,
                                tuple(-v for v in normal) if material[i] else normal,
                                i if material[i] else j)
            for axis in range(2):
                value = sum(tensor[axis][k]*normal[k] for k in range(2))
                result[i][axis] += value
                result[j][axis] -= value
    return result


def fixtures():
    from phase_momentum_reference import advance, equilibrium
    from phase_field_reference import step
    from grain_volume_reference import geometry
    result = []
    for sigma, direction, cosine in ((0.,1,0.),(.01,1,0.),(.01,-1,0.),(.01,1,.5),(.01,1,-.5)):
        n = 12
        m = [int(x in (0,n-1) or y in (0,n-1)) for y in range(n) for x in range(n)]
        m[5*n+5] = 2
        c = [0. if m[i] else .5*(1+math.tanh(direction*(i//n-5.75)/2)) for i in range(n*n)]
        force = forces(c, m, n, sigma, wetting_cosine=cosine)
        post, velocity = advance(equilibrium(n), c, m, n, gravity=(0.,0.), sigma=sigma, interface_force=force)
        phase_after,_=step(c,n,velocity,m,dt=1.,wetting_cosine=cosine)
        grain_velocity=[[f[0]/3,f[1]/3] if m[i]>=2 else [0.,0.] for i,f in enumerate(force)]
        volume=geometry(m,[[0.,0.] for _ in m],grain_velocity,n)
        result.append(dict(side=n, sigma=sigma, wetting_cosine=cosine, material=m, phase=c,
                           phase_after=phase_after, force=force, populations=post,volume=volume))
    return result


if __name__ == '__main__':
    (Path(__file__).resolve().parents[1]/'reports/interface-stress-fixture.json').write_text(json.dumps(fixtures()))
