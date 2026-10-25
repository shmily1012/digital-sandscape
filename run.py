"""Project-local launcher. Does not change system settings or execution policy."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', nargs='?', default='app',
                        choices=['legacy-app', 'buoyant-continuation', 'buoyant-transaction', 'sandscape-cycle', 'sandscape', 'sandscape-session', 'sandscape-preview', 'sandscape-preview-smoke', 'energy-parameter-response', 'energy-material-response', 'bubble-demo', 'bubble-demo-smoke', 'app', 'gpu', 'scheduler', 'smoke', 'benchmark', 'import', 'settling', 'bubbles', 'liquid', 'multigrid', 'adaptive', 'adaptive-fused', 'async-pressure', 'geometric', 'pressure-transport', 'continuous-transport', 'buoyancy', 'curvature', 'capillary-feedback', 'live-lab', 'lab-smoke', 'coupled-benchmark', 'lab-rejection', 'grain-coupling', 'online-grains', 'batched-grains', 'fast-self', 'fast-grains', 'contacts', 'parallel-contacts', 'contact-serial-benchmark', 'contact-parallel-benchmark', 'interval-contacts', 'contact-cycle', 'active-svd', 'active-system', 'active-backtrack', 'refined-cycle', 'async-contacts', 'mobility-contacts', 'calibrated-contacts', 'feedback-contacts', 'coupled-cycle', 'mobility-packets', 'async-mobility', 'async-coupled', 'coupled-lab', 'coupled-smoke', 'spring-history', 'geometric-operator', 'drainage-chain', 'drainage-reuse', 'resistance-solve', 'liquid-gpu', 'session', 'phase-gpu', 'phase-coupled', 'phase-view', 'phase-smoke', 'phase-topology', 'phase-sand', 'phase-sand-smoke', 'phase-grains', 'phase-sand-benchmark', 'grain-traction', 'grain-load', 'phase-load-response', 'phase-static-work', 'boundary-impulse', 'moving-boundary', 'phase-session', 'phase-cycle', 'phase-barrier', 'phase-barrier-cycle', 'phase-initialization', 'phase-contact', 'phase-contact-ledger', 'grain-contact-impulse', 'cut-cell-gpu', 'cut-cell-precision', 'phase-contact-trace', 'grain-interface-work', 'grain-energy-gpu', 'grain-energy-benchmark', 'energy-bubbles', 'grain-collective-gpu', 'collective-activity'])
    parser.add_argument('--grain-drag', type=int, choices=[1,16,64,256], default=1)
    parser.add_argument('--persistent-sandscape', action='store_true', help='Restore and save the separate energy-model journal')
    parser.add_argument('--sandscape-layout', action='store_true', help='Seeded irregular multi-bubble initial state')
    parser.add_argument('--bubble-barrier', action='store_true', help='Temporary seeded multi-bubble artwork')
    parser.add_argument('--contact-bed', action='store_true', help='Temporary loaded-bubble scene; never reads or writes saved artwork')
    parser.add_argument('--without-traction', action='store_true', help='Diagnostic ablation, contact-bed smoke only')
    parser.add_argument('--buoyant-exchange', action='store_true', help='Temporary GPU mixed buoyancy-loop candidate')
    parser.add_argument('--collective-exchange', action='store_true', help='Bounded grain cluster and adjacent fluid return loop')
    parser.add_argument('--energy-exchange', action='store_true', help='Temporary overdamped exchange candidate; requires contact-bed')
    parser.add_argument('--paired-interface', action='store_true', help='Paired-stress candidate, contact-bed smoke only')
    parser.add_argument('--wetting-cosine', type=float, choices=[-.5,0.,.5], default=0., help='Diagnostic surface preference; requires paired interface')
    parser.add_argument('--barrier-air-scale', type=float, choices=[1.0, 1.25], default=1.0)
    parser.add_argument('--size', type=int, choices=[256, 512, 1024], default=256)
    parser.add_argument('--seed', type=int, default=20261024)
    parser.add_argument('--fresh-session', action='store_true', help='Temporary app session: do not restore or overwrite saved artwork')
    args = parser.parse_args()
    if args.mode in ('sandscape', 'sandscape-preview', 'sandscape-preview-smoke'):
        args.persistent_sandscape = args.mode == 'sandscape'
        args.mode = 'phase-sand-smoke' if args.mode == 'sandscape-preview-smoke' else 'phase-sand'
        args.bubble_barrier = True
        args.sandscape_layout = True
        args.energy_exchange = True
        args.wetting_cosine = 0.5
    if args.sandscape_layout:
        args.bubble_barrier = True
    if args.mode in ('bubble-demo', 'bubble-demo-smoke'):
        args.mode = 'phase-sand-smoke' if args.mode == 'bubble-demo-smoke' else 'phase-sand'
        args.contact_bed = True
        args.energy_exchange = True
        args.wetting_cosine = 0.5
    if args.contact_bed and args.bubble_barrier:
        parser.error('Choose one initial scene: contact-bed or bubble-barrier')
    if args.bubble_barrier and args.mode not in ('phase-sand', 'phase-sand-smoke', 'phase-cycle'):
        parser.error('--bubble-barrier requires phase-sand, phase-sand-smoke or phase-cycle')
    if args.sandscape_layout and args.barrier_air_scale != 1.0:
        parser.error('--barrier-air-scale applies only to the regular bubble-barrier fixture')
    if args.persistent_sandscape and not (args.sandscape_layout and args.energy_exchange):
        parser.error('--persistent-sandscape requires the sandscape energy profile')
    if args.collective_exchange and args.mode not in ('energy-bubbles', 'energy-material-response', 'energy-parameter-response', 'grain-energy-benchmark'):
        args.energy_exchange = True
    if args.energy_exchange:
        if args.mode not in ('phase-sand', 'phase-sand-smoke', 'phase-cycle') or not (args.contact_bed or args.bubble_barrier) or args.without_traction:
            parser.error('--energy-exchange requires phase-sand, phase-sand-smoke or phase-cycle with --contact-bed or --bubble-barrier')
        args.paired_interface = True
    if args.wetting_cosine != 0. and not args.paired_interface:
        parser.error('--wetting-cosine requires --paired-interface')
    if args.paired_interface and (args.without_traction or args.mode != 'phase-sand-smoke' and not args.energy_exchange or not (args.contact_bed or args.bubble_barrier)):
        parser.error('--paired-interface requires phase-sand-smoke --contact-bed and active traction')
    if args.without_traction and not (args.mode == 'phase-sand-smoke' and args.contact_bed):
        parser.error('--without-traction requires phase-sand-smoke --contact-bed')
    if args.buoyant_exchange and (args.persistent_sandscape or args.mode not in ('phase-sand', 'phase-sand-smoke') or not args.energy_exchange):
        parser.error('--buoyant-exchange requires a temporary energy preview')
    engine = ROOT / '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'
    if not engine.is_file():
        parser.error(f'Godot executable missing: {engine}')
    env = os.environ.copy()
    for key, folder in [('APPDATA', 'roaming'), ('LOCALAPPDATA', 'local')]:
        path = ROOT / '.tools/runtime' / folder
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    command = [str(engine), '--path', str(ROOT), '--log-file', str(ROOT / f'reports/{args.mode}.log')]
    if args.mode == 'import':
        command += ['--headless', '--editor', '--import']
    elif args.mode == 'phase-initialization':
        command += ['--headless', '--script', 'res://tests/phase_initialization.gd']
    elif args.mode == 'scheduler':
        command += ['--headless', '--script', 'res://tests/test_scheduler.gd']
    else:
        command += ['--rendering-method', 'mobile', '--rendering-driver', 'vulkan']
        if args.mode == 'legacy-app':
            command += ['res://main.tscn']
        scripts = {'gpu': 'gpu_test', 'smoke': 'app_smoke', 'benchmark': 'gpu_benchmark'}
        if args.mode in ('live-lab','lab-smoke'):
            command += ['--script', 'res://experiments/liquid/live_lab.gd']
        if args.mode == 'coupled-benchmark':
            command += ['--script', 'res://experiments/liquid/coupled_benchmark.gd', '--resolution', '64x64']
        if args.mode == 'lab-rejection':
            command += ['--script', 'res://experiments/liquid/live_rejection_validation.gd', '--resolution', '64x64']
        if args.mode == 'grain-coupling':
            command += ['--script', 'res://experiments/liquid/grain_validation.gd', '--resolution', '64x64']
        if args.mode in ('online-grains','batched-grains'):
            command += ['--script', 'res://experiments/liquid/online_grain_validation.gd', '--resolution', '64x64']
        if args.mode in ('contacts','parallel-contacts','contact-serial-benchmark','contact-parallel-benchmark','interval-contacts','contact-cycle'):
            command += ['--script', 'res://experiments/deposition/gpu_validation.gd', '--resolution', '64x64']
        if args.mode in ('mobility-contacts','calibrated-contacts','feedback-contacts'):
            command += ['--script', 'res://experiments/deposition/mobility_validation.gd', '--resolution', '64x64']
        if args.mode in ('coupled-lab','coupled-smoke'):
            command += ['--script', 'res://experiments/deposition/coupled_lab.gd']
        if args.mode == 'adaptive-fused':
            command += ['--script', 'res://experiments/liquid/adaptive_validation.gd', '--resolution', '64x64']
        if args.mode in ('phase-sand-benchmark', 'grain-energy-benchmark'):
            command += ['--script', 'res://tests/phase_sand_benchmark.gd', '--resolution', '64x64']
        if args.mode == 'phase-load-response':
            command += ['--script', 'res://tests/phase_load_response.gd', '--resolution', '64x64']
        if args.mode == 'energy-parameter-response':
            command += ['--script', 'res://tests/energy_parameter_response.gd', '--resolution', '64x64']
        if args.mode == 'energy-material-response':
            command += ['--script', 'res://tests/energy_material_response.gd', '--resolution', '64x64']
        if args.mode == 'energy-bubbles':
            command += ['--script', 'res://tests/energy_bubble_behavior.gd', '--resolution', '64x64']
        if args.mode == 'collective-activity':
            subprocess.run([sys.executable, str(ROOT / 'tests/grain_collective_reference.py')], cwd=ROOT, check=True)
            command += ['--script', 'res://tests/collective_activity_gpu.gd', '--resolution', '64x64']
        if args.mode == 'grain-collective-gpu':
            subprocess.run([sys.executable, str(ROOT / 'tests/grain_collective_reference.py')], cwd=ROOT, check=True)
            command += ['--script', 'res://tests/grain_collective_gpu.gd', '--resolution', '64x64']
        if args.mode == 'grain-energy-gpu':
            subprocess.run([sys.executable, str(ROOT / 'tests/grain_energy_reference.py')], cwd=ROOT, check=True)
            command += ['--script', 'res://tests/grain_energy_gpu.gd', '--resolution', '64x64']
        if args.mode == 'grain-interface-work':
            subprocess.run([sys.executable, str(ROOT / 'tests/grain_interface_work_reference.py')], cwd=ROOT, check=True)
            command += ['--script', 'res://tests/grain_interface_work_gpu.gd', '--resolution', '64x64']
        if args.mode == 'phase-contact-trace':
            command += ['--script', 'res://tests/phase_contact_trace.gd', '--resolution', '64x64']
        if args.mode == 'phase-contact-ledger':
            command += ['--script', 'res://tests/phase_contact_ledger.gd', '--resolution', '64x64']
        if args.mode == 'phase-contact':
            command += ['--script', 'res://tests/phase_contact_observation.gd', '--resolution', '64x64']
        if args.mode == 'phase-static-work':
            command += ['--script', 'res://tests/phase_static_work.gd', '--resolution', '64x64']
        if args.mode in ('cut-cell-gpu','cut-cell-precision'):
            subprocess.run([sys.executable, str(ROOT / 'tests/cut_cell_operator_reference.py')], cwd=ROOT, check=True)
            command += ['--script', 'res://tests/cut_cell_pressure_precision.gd' if args.mode == 'cut-cell-precision' else 'res://tests/cut_cell_operator_gpu.gd', '--resolution', '64x64']
        if args.mode == 'grain-contact-impulse':
            subprocess.run([sys.executable, str(ROOT / 'tests/grain_contact_impulse_reference.py')], cwd=ROOT, check=True)
            command += ['--script', 'res://tests/grain_contact_impulse_gpu.gd', '--resolution', '64x64']
        if args.mode == 'grain-load':
            subprocess.run([__import__('sys').executable, str(ROOT / 'tests/grain_load_reference.py')], cwd=ROOT, check=True)
            command += ['--script', 'res://tests/grain_load_gpu.gd', '--resolution', '64x64']
        if args.mode in ('phase-cycle','phase-barrier-cycle'):
            command += ['--script', 'res://tests/energy_rotation_cycle.gd' if args.energy_exchange else 'res://tests/phase_cycle.gd', '--resolution', '820x740']
        if args.mode == 'buoyant-continuation':
            subprocess.run([sys.executable, str(ROOT / 'tests/buoyant_transaction_fixture.py')], cwd=ROOT, check=True)
            command += ['--script', 'res://tests/buoyant_continuation.gd', '--resolution', '820x740']
        if args.mode == 'buoyant-transaction':
            subprocess.run([sys.executable, str(ROOT / 'tests/buoyant_transaction_fixture.py')], cwd=ROOT, check=True)
            command += ['--script', 'res://tests/buoyant_transaction_gpu.gd', '--resolution', '64x64']
        if args.mode == 'sandscape-cycle':
            command += ['--script', 'res://tests/sandscape_cycle.gd', '--resolution', '820x740']
        if args.mode == 'sandscape-session':
            command += ['--script', 'res://tests/energy_session_validation.gd', '--resolution', '820x740']
        if args.mode == 'phase-session':
            command += ['--script', 'res://tests/phase_session_validation.gd', '--resolution', '820x740']
        if args.mode == 'moving-boundary':
            subprocess.run([__import__('sys').executable, str(ROOT / 'tests/moving_boundary_reference.py')], cwd=ROOT, check=True)
            command += ['--script', 'res://tests/moving_boundary_gpu.gd', '--resolution', '64x64']
        if args.mode == 'boundary-impulse':
            subprocess.run([__import__('sys').executable, str(ROOT / 'tests/grain_traction_reference.py')], cwd=ROOT, check=True)
            command += ['--script', 'res://tests/boundary_impulse_gpu.gd', '--resolution', '64x64']
        if args.mode == 'grain-traction':
            subprocess.run([__import__('sys').executable, str(ROOT / 'tests/grain_traction_reference.py')], cwd=ROOT, check=True)
            command += ['--script', 'res://tests/grain_traction_gpu.gd', '--resolution', '64x64']
        if args.mode == 'phase-grains':
            subprocess.run([__import__('sys').executable, str(ROOT / 'tests/phase_grains_reference.py')], cwd=ROOT, check=True)
            command += ['--script', 'res://tests/phase_grains_gpu.gd', '--resolution', '64x64']
        if args.mode == 'phase-topology':
            command += ['--script', 'res://tests/phase_topology_gpu.gd', '--resolution', '64x64']
        if args.mode in ('phase-view','phase-smoke','phase-sand','phase-sand-smoke','phase-barrier'):
            command += ['--script', 'res://src/phase_preview_host.gd' if args.mode not in ('phase-smoke','phase-sand-smoke') else 'res://tests/phase_preview_smoke.gd']
        if args.mode == 'phase-coupled':
            subprocess.run([__import__('sys').executable, str(ROOT / 'tests/phase_momentum_reference.py')], cwd=ROOT, check=True)
            command += ['--script', 'res://tests/phase_coupled_gpu.gd', '--resolution', '64x64']
        if args.mode == 'phase-gpu':
            subprocess.run([__import__('sys').executable, str(ROOT / 'tests/phase_field_reference.py')], cwd=ROOT, check=True)
            command += ['--script', 'res://tests/phase_gpu_test.gd', '--resolution', '64x64']
        if args.mode == 'session':
            command += ['--script', 'res://tests/session_validation.gd', '--resolution', '820x740']
        if args.mode == 'liquid-gpu':
            command += ['--script', 'res://tests/liquid_gpu_test.gd', '--resolution', '64x64']
        if args.mode == 'resistance-solve':
            command += ['--script', 'res://experiments/deposition/resistance_solve_validation.gd', '--resolution', '64x64']
        if args.mode == 'drainage-reuse':
            command += ['--script', 'res://experiments/deposition/drainage_reuse_validation.gd', '--resolution', '64x64']
        if args.mode == 'drainage-chain':
            command += ['--script', 'res://experiments/deposition/drainage_chain_validation.gd', '--resolution', '64x64']
        if args.mode == 'geometric-operator':
            command += ['--script', 'res://experiments/deposition/geometric_operator_validation.gd', '--resolution', '64x64']
        if args.mode == 'spring-history':
            command += ['--script', 'res://experiments/deposition/tangential_history_validation.gd', '--resolution', '64x64']
        if args.mode == 'async-coupled':
            command += ['--script', 'res://experiments/deposition/async_coupled_validation.gd', '--resolution', '64x64']
        if args.mode == 'async-mobility':
            command += ['--script', 'res://experiments/deposition/async_mobility_validation.gd', '--resolution', '64x64']
        if args.mode == 'mobility-packets':
            command += ['--script', 'res://experiments/deposition/mobility_packets_validation.gd', '--resolution', '64x64']
        if args.mode == 'coupled-cycle':
            command += ['--script', 'res://experiments/deposition/coupled_cycle_validation.gd', '--resolution', '64x64']
        if args.mode == 'async-contacts':
            command += ['--script', 'res://experiments/deposition/async_contact_validation.gd', '--resolution', '64x64']
        if args.mode == 'refined-cycle':
            command += ['--script', 'res://experiments/deposition/refined_cycle_validation.gd', '--resolution', '64x64']
        if args.mode == 'active-backtrack':
            command += ['--script', 'res://experiments/deposition/active_backtrack_validation.gd', '--resolution', '64x64']
        if args.mode == 'active-system':
            command += ['--script', 'res://experiments/deposition/active_system_validation.gd', '--resolution', '64x64']
        if args.mode == 'active-svd':
            command += ['--script', 'res://experiments/deposition/active_svd_validation.gd', '--resolution', '64x64']
        if args.mode == 'fast-grains':
            command += ['--script', 'res://experiments/liquid/fast_grain_validation.gd', '--resolution', '64x64']
        if args.mode == 'fast-self':
            command += ['--script', 'res://experiments/liquid/fast_self_validation.gd', '--resolution', '64x64']

        if args.mode == 'settling':
            command += ['--script', 'res://experiments/settling/gpu_validation.gd']
        if args.mode == 'bubbles':
            command += ['--script', 'res://experiments/bubbles/gpu_validation.gd', '--resolution', '64x64']
        if args.mode in ('liquid', 'multigrid'):
            command += ['--script', 'res://experiments/liquid/gpu_validation.gd', '--resolution', '64x64']
        if args.mode == 'adaptive':
            command += ['--script', 'res://experiments/liquid/adaptive_validation.gd', '--resolution', '64x64']
        if args.mode == 'async-pressure':
            command += ['--script', 'res://experiments/liquid/async_validation.gd', '--resolution', '64x64']
        if args.mode == 'geometric':
            command += ['--script', 'res://experiments/liquid/geometric_validation.gd', '--resolution', '64x64']
        if args.mode == 'pressure-transport':
            command += ['--script', 'res://experiments/liquid/pressure_transport_validation.gd', '--resolution', '64x64']
        if args.mode == 'curvature':
            command += ['--script', 'res://experiments/liquid/curvature_validation.gd', '--resolution', '64x64']
        if args.mode in ('continuous-transport','buoyancy','capillary-feedback'):
            command += ['--script', 'res://experiments/liquid/continuous_transport_validation.gd', '--resolution', '64x64']
        if args.mode in scripts:
            command += ['--script', f'res://tests/{scripts[args.mode]}.gd']
        if args.mode in ('gpu', 'benchmark'):
            command += ['--resolution', '64x64']
        command += ['--', f'--size={args.size}', f'--seed={args.seed & 0xFFFFFFFF}']
        if args.mode == 'multigrid':
            command += ['--multigrid']
        if args.mode == 'buoyancy':
            command += ['--buoyancy']
        if args.mode == 'capillary-feedback':
            command += ['--capillary']
        if args.mode == 'lab-smoke':
            command += ['--lab-smoke']
        if args.mode in ('parallel-contacts','contact-parallel-benchmark'):
            command += ['--parallel']
        if args.mode in ('contact-serial-benchmark','contact-parallel-benchmark'):
            command += ['--contact-benchmark']
        if args.mode == 'interval-contacts':
            command += ['--contact-interval']
        if args.mode == 'contact-cycle':
            command += ['--contact-cycle']
        if args.mode == 'coupled-smoke':
            command += ['--coupled-smoke']
        if args.mode == 'feedback-contacts':
            command += ['--feedback']
        if args.mode == 'calibrated-contacts':
            command += ['--calibrated']
        if args.mode == 'batched-grains':
            command += ['--batched']
    if args.mode == 'grain-energy-benchmark':
        command += ['--benchmark-energy']
    if args.mode == 'adaptive-fused':
        command += ['--fused-pressure']
    if args.mode in ('phase-sand','phase-sand-smoke','phase-cycle','phase-barrier','phase-barrier-cycle'):
        command += ['--with-sand']
    if args.mode in ('phase-barrier','phase-barrier-cycle'):
        command += ['--bubble-barrier', '--fresh-session', f'--barrier-air-scale={args.barrier_air_scale}']
    if args.grain_drag != 1:
        command += [f'--grain-drag={args.grain_drag}']
    if args.fresh_session:
        command += ['--fresh-session']
    if args.mode == 'buoyant-continuation':
        command += ['--with-sand', '--sandscape-layout', '--bubble-barrier', '--energy-exchange', '--paired-interface', '--wetting-cosine=0.5', '--buoyant-exchange', '--fresh-session']
    if args.mode == 'sandscape-cycle':
        command += ['--with-sand', '--bubble-barrier', '--sandscape-layout', '--energy-exchange', '--paired-interface', '--wetting-cosine=0.5', '--fresh-session']
    if args.mode == 'sandscape-session':
        command += ['--with-sand', '--bubble-barrier', '--sandscape-layout', '--energy-exchange', '--paired-interface', '--wetting-cosine=0.5', '--persistent-sandscape']
    if args.persistent_sandscape:
        command += ['--persistent-sandscape']
    if args.sandscape_layout:
        command += ['--sandscape-layout']
    if args.bubble_barrier:
        command += ['--bubble-barrier', f'--barrier-air-scale={args.barrier_air_scale}']
        if not args.persistent_sandscape:command += ['--fresh-session']
    if args.contact_bed:
        command += ['--contact-bed', '--fresh-session']
    if args.without_traction:
        command += ['--without-traction']
    if args.buoyant_exchange:
        command += ['--buoyant-exchange']
    if args.collective_exchange:
        command += ['--collective-exchange']
    if args.energy_exchange:
        command += ['--energy-exchange']
    if args.paired_interface:
        command += ['--paired-interface', f'--wetting-cosine={args.wetting_cosine}']
    result = subprocess.call(command, cwd=ROOT, env=env)
    if result == 0 and args.mode == 'phase-contact-ledger':
        return subprocess.call([sys.executable, str(ROOT / 'tests/phase_contact_ledger.py')], cwd=ROOT, env=env)
    return result


if __name__ == '__main__':
    raise SystemExit(main())
