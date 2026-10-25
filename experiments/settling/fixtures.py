"""Generate GPU fixtures independently from the CPU SI-unit solver."""
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from experiments.settling.model import Grain, Mineral, advance, reynolds


def main():
    scenarios = []
    specs = [dict(angle=a, dt=1/60, steps=60, viscosity=0.001, flow=[0, 0])
             for a in (0, 13.7, 30, 45, 90, 120, 180, 270)]
    specs += [dict(angle=0, dt=dt, steps=steps, viscosity=mu, flow=flow)
              for dt, steps, mu, flow in ((1/30, 30, 0.001, [0, 0]),
                                           (1/120, 120, 0.001, [0, 0]),
                                           (1/60, 60, 0.002, [0, 0]),
                                           (1/60, 60, 0.001, [0.001, 0]),
                                           (1e-8, 100, 0.001, [0, 0]))]
    for spec in specs:
        radians = math.radians(spec['angle'])
        gravity = [9.81*math.sin(radians), 9.81*math.cos(radians)]
        initial, expected = [], []
        for index, (diameter, density) in enumerate(((10e-6, 2650), (20e-6, 2650),
                                                   (40e-6, 2650), (20e-6, 1000), (20e-6, 900))):
            grain = Grain(0.01, 0.02, 0, 0, Mineral(diameter, density, index+1))
            initial += [grain.x, grain.y, grain.vx, grain.vy, diameter, density, index+1, 0, 0, 0, 0, 0]
            for _ in range(spec['steps']):
                grain = advance(grain, spec['dt'], gravity, spec['flow'], viscosity=spec['viscosity'])
            assert reynolds(grain, spec['flow'], viscosity=spec['viscosity']) < 0.1
            expected += [grain.x, grain.y, grain.vx, grain.vy, diameter, density, index+1, 0, 0, 0, 0, 0]
        scenarios.append(dict(spec, gravity=gravity, initial=initial, expected=expected))
    output = ROOT / 'reports/settling-fixtures.json'
    output.write_text(json.dumps(scenarios, indent=2), encoding='utf-8')
    print(f'Generated {len(scenarios)} scenarios, 5 particles each; SI units, Re < 0.1')


if __name__ == '__main__':
    main()
