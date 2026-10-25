"""Reversible ablation of the gas-entry veto; never a product physics mode.

Runs the existing real-GPU suite and restores source/report bytes in finally.
Results are archived separately so a probe cannot replace baseline evidence.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def probe_chain_locality():
    from grain_displacement_reference import step
    n = 40
    material = [0] * (n*n)
    velocity = [[0., 0.] for _ in material]
    offset = [[0., 0.] for _ in material]
    for y in range(3, 23):
        i = y*n+20
        material[i] = 2
        velocity[i] = [0., .02]
        offset[i] = [0., .49]
    moved = step(material, velocity, offset, n)
    assert moved is not None
    source = moved[0][3*n+20]
    return {'scope': 'Existing remap operator; not full physical evolution',
            'vacated_head_xy': [20, 3],
            'fluid_source_xy': [source % n, source // n],
            'packet_distance_cells': abs(source // n-3),
            'grain_displacement_cells': .02}


def main():
    shader = ROOT / 'shaders/grain_displacement.glsl'
    original = shader.read_bytes()
    needle = b'if(m[b]==0u&&uintBitsToFloat(p.reserved==2u?fluid_c[b]:c[b])>.05)'
    assert original.count(needle) == 1
    reports = ROOT / 'reports'
    (reports / 'remap-chain-locality.json').write_text(
        json.dumps(probe_chain_locality(), indent=2))
    saved = {p: p.read_bytes() for p in reports.iterdir() if p.is_file()}
    result = {'scope': 'Gas-entry veto ablation only; not bubble support acceptance',
              'baseline_shader_sha256': hashlib.sha256(original).hexdigest()}
    try:
        shader.write_bytes(original.replace(needle, b'if(p.reserved!=2u&&m[b]==0u&&uintBitsToFloat(c[b])>.05)'))
        with (reports / 'gas-exclusion-probe.log').open('w') as log:
            run = subprocess.run([sys.executable, 'run.py', 'grain-contact-impulse'],
                                 cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        result['exit_code'] = run.returncode
        result['gpu_report'] = json.loads((reports / 'grain-coupled.json').read_text())
        with zipfile.ZipFile(reports / 'gas-exclusion-probe.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('grain_displacement.glsl', shader.read_bytes())
            for path in reports.iterdir():
                if path.is_file() and path.suffix != '.zip' and path.name != 'gas-exclusion-probe.json':
                    data = path.read_bytes()
                    if saved.get(path) != data:
                        archive.writestr(path.name, data)
    finally:
        shader.write_bytes(original)
        for path, data in saved.items():
            if not path.name.startswith('gas-exclusion-probe.') and path.read_bytes() != data:
                path.write_bytes(data)
        result['shader_restored'] = shader.read_bytes() == original
        (reports / 'gas-exclusion-probe.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
