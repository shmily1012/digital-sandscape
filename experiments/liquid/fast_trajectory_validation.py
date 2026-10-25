"""Compare independently evolved fast and exact dilute trajectories."""
import json
import math
from dataclasses import asdict
from pathlib import Path
import sys
import time
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from experiments.liquid.fast_grains import advance_fast
from experiments.liquid.grain_coupling import Grain, advance
from experiments.liquid.model import DarcyGrid, circle_mask


def main():
    kernel = json.loads((ROOT/'reports/self-response-kernel.json').read_text())
    grid = DarcyGrid(32, circle_mask(32))
    initial = [Grain(.42, .43, .012, .01, 2.65, 1),
               Grain(.58, .43, .011, .01, 2.2, 2),
               Grain(.5, .6, .01, .01, 1.8, 3)]
    fast, exact = list(initial), list(initial)
    rows = []
    for step in range(30):
        gravity = ((0, 1), (.6, .8), (-.6, -.8))[step//10]
        start = time.perf_counter()
        fast, projection, margins = advance_fast(grid, fast, gravity, .02, kernel)
        fast_seconds = time.perf_counter()-start
        start = time.perf_counter()
        exact, _, _ = advance(grid, exact, gravity, .02)
        rows.append(dict(step=step+1, gravity=gravity,
                         dt=.02, expected=[asdict(g) for g in fast],
                         position_error=max(math.hypot(a.x-b.x, a.y-b.y) for a, b in zip(fast, exact)),
                         minimum_work_margin=min(margins), residual=projection.residual,
                         fast_cpu_seconds=fast_seconds, exact_cpu_seconds=time.perf_counter()-start))
    base = json.loads((ROOT/'reports/online-grain-fixtures.json').read_text())['base']
    (ROOT/'reports/fast-grain-fixtures.json').write_text(json.dumps(dict(base=base, initial=[asdict(g) for g in initial], sequence=rows)), encoding='utf-8')
    maximum = max(r['position_error'] for r in rows)
    report = dict(scope='CPU only, 3 dilute grains, 32 squared, dt .02, 30 steps; no bubble or contact dynamics',
                  initial=[asdict(g) for g in initial], fast_final=[asdict(g) for g in fast],
                  exact_final=[asdict(g) for g in exact], rows=rows,
                  maximum_position_error=maximum, threshold=1e-4, failures=int(maximum > 1e-4))
    (ROOT/'reports/fast-trajectory-validation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k not in ('rows', 'initial', 'fast_final', 'exact_final')}))
    if report['failures']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
