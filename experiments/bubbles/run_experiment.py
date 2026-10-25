"""Dynamic gas-release candidate versus no-gas and fixed-obstacle controls."""
from collections import Counter
import csv
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from experiments.bubbles.model import Bubble, BubbleCell, Grain


def make_case(name):
    grains = [Grain(0.284+col*0.048, 0.18+row*0.045, 0.02, 1+(row+col)%3)
              for row in range(3) for col in range(10)]
    bubbles = []
    if name == 'single':
        bubbles = [Bubble(0.5, 0.46, math.sqrt(2)*0.1)]
    elif name != 'no_gas':
        bubbles = [Bubble(0.37, 0.46, 0.1), Bubble(0.63, 0.46, 0.1)]
    return BubbleCell(grains, bubbles, shape_mobility=30, contact_stiffness=10)


def main():
    summaries, rows, frames = [], [], []
    for name in ('no_gas', 'single', 'two', 'fixed_control'):
        cell = make_case(name)
        inventory, initial_area = Counter(cell.inventory()), cell.gas_area()
        start_positions = [(bubble.x, bubble.y) for bubble in cell.bubbles]
        first_crossing = None
        ever_crossed = set()
        peak_penetration = 0.0
        for frame in range(241):
            if frame:
                cell.step(0.05, fixed_bubbles=name == 'fixed_control')
            assert Counter(cell.inventory()) == inventory
            assert abs(cell.gas_area()-initial_area) < 1e-12
            crossing = {i for i, grain in enumerate(cell.grains) if grain.y > 0.65}
            if crossing and first_crossing is None:
                first_crossing = cell.time
            newly_crossed = crossing-ever_crossed
            ever_crossed |= crossing
            peak_penetration = max(peak_penetration, cell.forces()[3])
            rows.append({'case': name, 'time': cell.time, 'below_line': len(crossing),
                         'new_crossings': len(newly_crossed), 'gas_area': cell.gas_area()})
            if frame in (0, 80, 160, 240):
                frames.append({'case': name, 'time': cell.time,
                               'grains': [vars(grain).copy() for grain in cell.grains],
                               'bubbles': [dict(vars(bubble), axes=bubble.axes) for bubble in cell.bubbles]})
        movement = sum(math.dist(start, (bubble.x, bubble.y))
                       for start, bubble in zip(start_positions, cell.bubbles))
        result = {'case': name, 'first_crossing_time': first_crossing,
                  'crossed_by_end': len(ever_crossed), 'gas_area_initial': initial_area,
                  'gas_area_final': cell.gas_area(), 'bubble_center_travel': movement,
                  'max_penetration_world_units': peak_penetration,
                  'substeps': cell.substeps, 'conserved': True}
        summaries.append(result)
        print(json.dumps(result), flush=True)
    with (ROOT/'reports/bubble-release.csv').open('w', newline='', encoding='utf-8') as file:
        writer = csv.DictWriter(file, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    report = {'scope': 'CPU dimensionless deformable-ellipse candidate, not calibrated fluid solver',
              'summaries': summaries, 'snapshots': frames}
    (ROOT/'reports/bubble-release.json').write_text(json.dumps(report, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
