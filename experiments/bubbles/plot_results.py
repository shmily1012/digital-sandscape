"""Plot measured experiment snapshots/curves, not product imagery."""
import csv
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'.tools/plot-libs'))
os.environ.setdefault('MPLCONFIGDIR', str(ROOT/'.tools/matplotlib'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Ellipse


def main():
    report = json.loads((ROOT/'reports/bubble-release.json').read_text(encoding='utf-8'))
    cases = ['no_gas', 'single', 'two', 'fixed_control']
    fig, axes = plt.subplots(4, 4, figsize=(12, 12), constrained_layout=True)
    for snapshot in report['snapshots']:
        row = cases.index(snapshot['case'])
        col = min(3, round(snapshot['time']/4))
        ax = axes[row, col]
        ax.set(xlim=(0, 1), ylim=(1, 0), aspect='equal')
        ax.set_facecolor('#dce7eb')
        for bubble in snapshot['bubbles']:
            a, b = bubble['axes']
            ax.add_patch(Ellipse((bubble['x'], bubble['y']), 2*a, 2*b,
                                 facecolor='white', edgecolor='#43718b', linewidth=1))
        for grain in snapshot['grains']:
            color = ['#202020', '#888888', '#ddd4b8'][grain['material']-1]
            ax.add_patch(Circle((grain['x'], grain['y']), grain['radius'], facecolor=color, edgecolor='#444', linewidth=0.3))
        ax.axhline(0.65, color='#ac3838', linestyle=':', linewidth=0.7)
        ax.set_title(f"{snapshot['case']}, t={snapshot['time']:.0f}", fontsize=9)
    fig.suptitle('E2 candidate: actual CPU state snapshots (dimensionless, uncalibrated)', fontsize=13)
    fig.savefig(ROOT/'reports/bubble-states.png', dpi=130)
    plt.close(fig)
    with (ROOT/'reports/bubble-release.csv').open(encoding='utf-8') as file:
        rows = list(csv.DictReader(file))
    fig, ax = plt.subplots(figsize=(8, 4), constrained_layout=True)
    for name in cases:
        samples = [r for r in rows if r['case'] == name]
        ax.plot([float(r['time']) for r in samples], [int(r['below_line']) for r in samples], label=name)
    ax.set(xlabel='Dimensionless time', ylabel='Grains below y=0.65', ylim=(0, 31),
           title='Release response: dynamic bubbles vs fixed-obstacle control')
    ax.legend()
    ax.grid(alpha=0.2)
    fig.savefig(ROOT/'reports/bubble-release-curve.png', dpi=150)
    plt.close(fig)


if __name__ == '__main__':
    main()
