"""Save raw contact-bed profiles; no generated mountain is used by the app."""
from collections import Counter
import csv
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from experiments.deposition.model import ContactBed


def main():
    profiles = []
    reports = []
    for name, first, second in [('left_feed', 30, 30), ('right_feed', 70, 70), ('shifted_feed', 30, 70)]:
        bed = ContactBed([i//300 % 3+1 for i in range(2400)])
        original = Counter(bed.inventory())
        for batch in range(240):
            bed.release(first if batch < 120 else second, 10)
            bed.relax()
        assert Counter(bed.inventory()) == original
        stopped = bed.relax() == 0
        h = bed.heights()
        reports.append({'name': name, 'conserved': True, 'stopped_after_supply': stopped,
                        'peak_column': h.index(max(h)), 'peak_m': max(h),
                        'transfers': bed.transfers, 'reservoir_remaining': len(bed.reservoir)})
        profiles += [{'case': name, 'x_m': i*bed.dx, 'height_m': height,
                      'dark_count': column.count(1), 'gray_count': column.count(2),
                      'white_count': column.count(3)} for i, (height, column) in enumerate(zip(h, bed.columns))]
    with (ROOT/'reports/contact-bed-profiles.csv').open('w', newline='', encoding='utf-8') as file:
        writer = csv.DictWriter(file, fieldnames=profiles[0].keys())
        writer.writeheader()
        writer.writerows(profiles)
    report = {'scope': 'CPU isolated contact-bed height field; prescribed phenomenological hysteresis, not a full sand picture', 'cases': reports}
    (ROOT/'reports/contact-bed-validation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
