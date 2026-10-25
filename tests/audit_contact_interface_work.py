"""Compare GPU finite work on the recorded contact bed with the CPU energy."""
import json
import struct
from pathlib import Path
from contact_interface_geometry import classify
from grain_interface_work_reference import exchange_work, neighbor, DIRECTIONS

ROOT = Path(__file__).resolve().parents[1]/'reports'


def audit():
    c = struct.unpack('<65536f', (ROOT/'phase-contact-bed-tick-10000.f32').read_bytes())
    m = struct.unpack('<65536I', (ROOT/'phase-contact-bed-tick-10000.materials.u32').read_bytes())
    work = struct.unpack('<262144f', (ROOT/'contact-interface-work.bin').read_bytes())
    masks = struct.unpack('<65536I', (ROOT/'contact-interface-mask.bin').read_bytes())
    groups = classify(c, m, 256)
    report = {}
    error = 0.
    for name in ('gas_upstream', 'gas_downstream', 'lateral_or_ambiguous'):
        rows = []
        for i in groups[name]:
            row = dict(cell=i, work=list(work[4*i:4*i+4]), mask=masks[i])
            for q, d in enumerate(DIRECTIONS):
                if masks[i] & (1 << q):
                    j = neighbor(i, d, 256)
                    error = max(error, abs(work[4*i+q]-exchange_work(c, m, 256, i, j)))
            rows.append(row)
        down = [row['work'][1] for row in rows if row['mask'] & 2]
        report[name] = dict(grains=len(rows), downward_fluid_neighbors=len(down),
                            downward_energy_decrease=sum(x < 0 for x in down),
                            mean_downward_work=sum(down)/max(len(down), 1), rows=rows)
    report['max_cpu_gpu_error'] = error
    report['physical_acceptance'] = False
    report['scope'] = ('Finite interface energy only; negative work is not a complete motion '
                       'acceptance condition. No pressure, viscous or contact work included.')
    (ROOT/'contact-interface-work-audit.json').write_text(json.dumps(report, indent=2))
    if error > 1e-8:
        raise AssertionError(f'CPU/GPU finite-work mismatch: {error}')
    print(f'CONTACT_INTERFACE_WORK max_cpu_gpu_error={error:.8g}')


if __name__ == '__main__':
    audit()
