"""Read-only local contact geometry; neither adjacency nor force proves support."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


def classify(gas, materials, side, gravity=(0., 1.), threshold=.05):
    if len(gas) != side*side or len(materials) != len(gas):
        raise ValueError('Inconsistent grid')
    length = math.hypot(*gravity)
    if not math.isfinite(length) or length == 0:
        raise ValueError('Nonzero finite gravity required')
    if any(not math.isfinite(c) or not 0 <= c <= 1 for c in gas):
        raise ValueError('Invalid gas fraction')
    if any(m not in range(5) for m in materials):
        raise ValueError('Invalid material')
    gx, gy = (v/length for v in gravity)
    groups = {name: [] for name in ('gas_downstream', 'gas_upstream',
                                   'lateral_or_ambiguous', 'no_adjacent_gas')}
    for i, material in enumerate(materials):
        if material < 2:
            continue
        vx = vy = weight = 0.
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                x, y = i % side + dx, i // side + dy
                if not (dx or dy) or not (0 <= x < side and 0 <= y < side):
                    continue
                j = y*side+x
                if materials[j] != 0 or gas[j] <= threshold:
                    continue
                w = gas[j]
                distance = math.hypot(dx, dy)
                vx += w*dx/distance
                vy += w*dy/distance
                weight += w
        if weight == 0:
            name = 'no_adjacent_gas'
        else:
            # Normalize by total weight, not resultant length: surrounding gas
            # and opposing contacts must remain ambiguous rather than amplify noise.
            alignment = (vx*gx+vy*gy)/weight
            name = ('gas_downstream' if alignment > .5 else
                    'gas_upstream' if alignment < -.5 else 'lateral_or_ambiguous')
        groups[name].append(i)
    return groups


def inspect(stem, gravity):
    paths = [Path(str(stem)+suffix) for suffix in ('.f32', '.materials.u32')]
    raw = [path.read_bytes() for path in paths]
    gas = struct.unpack('<%df' % (len(raw[0])//4), raw[0])
    materials = struct.unpack('<%dI' % (len(raw[1])//4), raw[1])
    groups = classify(gas, materials, math.isqrt(len(gas)), gravity)
    return {'source': str(stem), 'sha256': [hashlib.sha256(b).hexdigest() for b in raw],
            'gravity': gravity, 'counts': {k: len(v) for k, v in groups.items()},
            'indices': groups, 'physical_acceptance': False,
            'scope': 'Local 8-neighbor geometry only. Downstream gas may support a grain; '
                     'upstream gas identifies underside adjacency, not proven adhesion. '
                     'No contact force, particle trajectory or load balance is inferred.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stem', type=Path)
    parser.add_argument('--gravity', type=float, nargs=2, default=(0., 1.))
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = inspect(args.stem, args.gravity)
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result['counts']))
