"""Compare exact runtime snapshots; interface adjacency is not force balance."""
import json
import math
import struct
from pathlib import Path
from grain_traction_reference import traction, traction_components
from interface_stress_reference import forces as interface_forces

ROOT = Path(__file__).resolve().parents[1] / 'reports'


def measure(tick, suffix):
    metadata=json.loads((ROOT / f'phase-contact-bed-smoke{suffix}.json').read_text())
    cosine=float(metadata.get('wetting_cosine',0.))
    paired=bool(metadata.get('paired_interface',False))
    stem = ROOT / f'phase-contact-bed-tick-{tick}{suffix}'
    raw = Path(str(stem)+'.f32').read_bytes()
    gas = struct.unpack('<' + 'f' * (len(raw) // 4), raw)
    raw = Path(str(stem) + '.materials.u32').read_bytes()
    materials = struct.unpack('<' + 'I' * (len(raw) // 4), raw)
    n = math.isqrt(len(gas))
    assert n*n == len(gas) == len(materials)
    cy = sum((i // n)*g for i, g in enumerate(gas))/sum(gas)
    upper = lower = released = grains = 0
    for i, material in enumerate(materials):
        if material < 2:
            continue
        grains += 1
        x, y = i % n, i // n
        released += y >= .72*n
        adjacent = any(gas[(y+dy)*n+x+dx] > .05
                       for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                       if (dx or dy) and 0 <= x+dx < n and 0 <= y+dy < n)
        if adjacent:
            upper += y < cy
            lower += y >= cy
    result = dict(grains=grains, gas_center_y=cy,
                upper_half_interface_adjacent=upper,
                lower_half_interface_adjacent=lower,
                grains_below_72_percent_height=released)
    population_path = Path(str(stem) + '.populations.f32')
    if population_path.exists():
        raw = population_path.read_bytes()
        f = struct.unpack('<' + 'f' * (len(raw)//4), raw)
        assert len(f) == 9*len(materials)
        components = traction_components(f, materials, n)
        total = traction(f, materials, n)
        error = max(abs(total[i][a]-sum(v[i][a] for v in components.values()))
                    for i in range(len(materials)) for a in (0,1))
        assert error < 1e-12
        result['force_reconstruction_error'] = error
        # Only the paired run evolves its pressure with this stress.
        capillary = interface_forces(gas, materials, n,wetting_cosine=cosine)
        result['candidate_interface_force_sum'] = [sum(v[a] for v in capillary) for a in (0,1)]
        groups = {'upper': [], 'lower': []}
        for i,m in enumerate(materials):
            if m < 2:
                continue
            x,y = i%n,i//n
            if any(gas[(y+dy)*n+x+dx] > .05
                   for dy in (-1,0,1) for dx in (-1,0,1)
                   if (dx or dy) and 0<=x+dx<n and 0<=y+dy<n):
                groups['upper' if y<cy else 'lower'].append(i)
        result['frozen_estimator'] = {}
        for name,indices in groups.items():
            entry = {'count':len(indices)}
            driving = ([[0.,0.] for _ in materials] if suffix=='-without-traction' else
                       [[total[i][a]+capillary[i][a] for a in (0,1)] for i in range(len(materials))]
                       if paired else total)
            for part,force in dict(components,old_estimator=total,
                                   interface_candidate=capillary,active_force=driving).items():
                ratios = [force[i][1]/({2:2.,3:1.7,4:1.4}[materials[i]]*.00002)
                          for i in indices]
                entry[part] = {'mean_vertical_force_over_weight':sum(ratios)/max(1,len(ratios)),
                               'upward_exceeds_weight':sum(v < -1. for v in ratios)}
            result['frozen_estimator'][name] = entry
    return result


if __name__ == '__main__':
    variants = [('baseline', ''), ('without_traction', '-without-traction')]
    if (ROOT / 'phase-contact-bed-initial-paired-interface.f32').exists():
        variants.append(('paired_interface', '-paired-interface'))
    for cosine in (.5,-.5):
        suffix=f'-paired-interface-wetting-{cosine:.1f}'
        if (ROOT / f'phase-contact-bed-initial{suffix}.f32').exists():
            variants.append((f'wetting_{cosine:.1f}',suffix))
    for _,suffix in variants:
        for extension in ('.f32', '.materials.u32'):
            assert (ROOT / ('phase-contact-bed-initial'+extension)).read_bytes() == (
                ROOT / ('phase-contact-bed-initial'+suffix+extension)).read_bytes()
    revisions={json.loads((ROOT / f'phase-contact-bed-smoke{suffix}.json').read_text()).get('grain_rule_revision',1)
               for _,suffix in variants}
    if len(revisions)!=1:
        raise ValueError('Mixed grain rule revisions: rerun all compared smoke variants with the current shader')
    report = dict(initial_states_identical=True, physical_acceptance=False,
                  definition='8-neighbor gas fraction > .05; upper/lower relative to gas centroid; adjacency is not a contact force')
    report['samples'] = {str(t): {label: measure(t, suffix) for label, suffix in variants}
                         for t in (2000, 5000, 10000)}
    (ROOT / 'contact-traction-ablation.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
