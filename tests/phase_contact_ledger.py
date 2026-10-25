"""Independent force ledger on saved, physically evolved GPU contact fixtures."""
from array import array
import json
import hashlib
import math
from pathlib import Path
from phase_momentum_reference import E, advance
from grain_traction_reference import traction

ROOT = Path(__file__).resolve().parents[1]


def read(prefix, suffix, kind='f'):
    values = array(kind)
    values.frombytes(Path(str(prefix)+'.'+suffix).read_bytes())
    return values.tolist()


def phase_forces(c, material, n, sigma=.01, gravity=(0., .00002)):
    """Sum the actual diffuse-interface and buoyancy forces, without clipping."""
    cap = [[], []]
    body = [[], []]
    for i, m in enumerate(material):
        if m:
            continue
        x, y = i % n, i // n
        neighbors = []
        for dx, dy in E[1:5]:
            nx, ny = x+dx, y+dy
            j = ny*n+nx if 0 <= nx < n and 0 <= ny < n else i
            neighbors.append(c[i if material[j] else j])
        east, south, west, north = neighbors
        lap = math.fsum(neighbors)-4*c[i]
        mu = 2*(12*sigma/4)*c[i]*(1-c[i])*(1-2*c[i])-1.5*sigma*4*lap
        for axis, grad in enumerate(((east-west)*.5, (south-north)*.5)):
            cap[axis].append(mu*grad)
            body[axis].append(-c[i]*gravity[axis])
    return [math.fsum(v) for v in cap], [math.fsum(v) for v in body]


def momentum(f, material):
    return [math.fsum(f[9*i+q]*e[a] for i, m in enumerate(material) if not m
                      for q, e in enumerate(E)) for a in range(2)]


def audit(name):
    prefix = ROOT/'reports'/('contact-'+name)
    c, m = read(prefix, 'phase'), read(prefix, 'materials', 'i')
    before, after = read(prefix, 'populations'), read(prefix, 'next')
    impulse = read(prefix, 'impulse')
    if len(c) != 128**2 or len(m) != len(c) or len(before) != 9*len(c) or len(after) != len(before) or len(impulse) != 2*len(c):
        raise ValueError('Invalid fixture size')
    if not all(math.isfinite(v) for seq in (c, before, after, impulse) for v in seq):
        raise ValueError('Nonfinite fixture')
    raw = traction(before, m, 128, raw_impulse=True)
    excess = traction(before, m, 128)
    expected, _ = advance(before, c, m, 128, gravity=(0., .00002), sigma=.01)
    cap, body = phase_forces(c, m, 128)
    p0, p1 = momentum(before, m), momentum(after, m)
    walls = [math.fsum(impulse[2*i+a] for i, v in enumerate(m) if v == 1) for a in range(2)]
    grains = [math.fsum(impulse[2*i+a] for i, v in enumerate(m) if v >= 2) for a in range(2)]
    old = [math.fsum(excess[i][a] for i, v in enumerate(m) if v >= 2) for a in range(2)]
    residual = [p1[a]-p0[a]+walls[a]+grains[a]-cap[a]-body[a] for a in range(2)]
    old_residual = [p1[a]-p0[a]+walls[a]+old[a]-cap[a]-body[a] for a in range(2)]
    pop_error = max(abs(a-b) for a, b in zip(expected, after))
    impulse_error = max(abs(impulse[2*i+a]-raw[i][a]) for i in range(len(c)) for a in range(2))
    inputs = {suffix: hashlib.sha256(Path(str(prefix)+'.'+suffix).read_bytes()).hexdigest()
              for suffix in ('phase', 'materials', 'populations', 'residual')}
    return dict(case=name, input_sha256=inputs, capillary_force=cap, buoyancy_force=body,
                wall_impulse=walls, grain_impulse=grains, excess_estimator=old,
                fluid_delta=[p1[a]-p0[a] for a in range(2)],
                raw_budget_residual=residual, excess_budget_residual=old_residual,
                cpu_gpu_population_error=pop_error, cpu_gpu_impulse_error=impulse_error,
                passed=pop_error < 2e-6 and impulse_error < 2e-7 and math.hypot(*residual) < 2e-5)


if __name__ == '__main__':
    cases = [audit(n) for n in ('water-4000', 'relaxed-bubble-8000',
                                'relaxed-bubble-9000', 'relaxed-bubble-12000')]
    result = dict(cases=cases, failures=sum(not c['passed'] for c in cases),
                  scope='One frozen-geometry step from evolved contact states. Raw impulses are already exchanged by bounce-back; do not add them twice. This does not integrate moving grains or validate capillary contact.')
    (ROOT/'reports/phase-contact-ledger.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))
    raise SystemExit(bool(result['failures']))
