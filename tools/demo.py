#!/usr/bin/env python3
"""Portable runner. Python standard library only; installs nothing."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def find_godot(explicit):
    candidate = explicit or os.environ.get('GODOT_BIN')
    if candidate:
        resolved = shutil.which(candidate) or str(Path(candidate).expanduser())
        if Path(resolved).is_file():
            return resolved
        raise SystemExit(f'Godot executable not found: {candidate}')
    for name in ('godot', 'godot4', 'Godot'):
        found = shutil.which(name)
        if found:
            return found
    for path in (Path('/Applications/Godot.app/Contents/MacOS/Godot'),
                 Path.home() / 'Applications/Godot.app/Contents/MacOS/Godot'):
        if path.is_file():
            return str(path)
    raise SystemExit('Install standard Godot 4.7.2, then pass --godot /path/to/executable. '
                     'On Windows pass the Godot .exe; no .NET build is required.')


def run(command):
    print('+', ' '.join(str(part) for part in command), flush=True)
    subprocess.run(command, cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('run', 'verify', 'verify-wheels', 'verify-driving', 'verify-adaptive', 'verify-ramps', 'verify-retention', 'verify-baked', 'verify-driving-bakes', 'verify-effects', 'verify-sequence', 'verify-quality', 'verify-roof', 'verify-surfaces', 'verify-arena', 'capture-surfaces', 'damage-studio', 'bake', 'index-bakes', 'baked', 'baked-3d', 'capture-baked', 'drive', 'drive-sequence', 'arena', 'capture-driving', 'capture', 'import', 'check'))
    parser.add_argument('--godot', help='Godot executable, or set GODOT_BIN')
    parser.add_argument('--no-import', action='store_true', help='Skip import after the first successful run')
    args = parser.parse_args()
    if args.command == 'check':
        run([sys.executable, str(ROOT / 'tools/check_package.py')])
        return
    binary = find_godot(args.godot)
    version = subprocess.check_output([binary, '--version'], text=True).strip()
    print('Godot:', version, flush=True)
    if not version.startswith('4.7.2.'):
        print('This example was verified on Godot 4.7.2; other versions need their own verification.', flush=True)
    (ROOT / 'verification').mkdir(exist_ok=True)
    if args.command == 'import' or not args.no_import:
        run([binary, '--headless', '--path', str(ROOT), '--editor', '--import', '--quit'])
    if args.command == 'import':
        return
    if args.command in ('verify', 'verify-wheels', 'verify-driving', 'verify-adaptive', 'verify-ramps', 'verify-retention', 'verify-baked', 'verify-driving-bakes', 'verify-effects', 'verify-sequence', 'verify-quality', 'verify-roof', 'verify-surfaces', 'verify-arena'):
        import json
        if args.command == 'verify':
            run([binary, '--headless', '--path', str(ROOT), '--fixed-fps', '120', '--', '--verify-structure'])
            report = json.loads((ROOT / 'verification/structural_validation.json').read_text())
            if not report['passed']:
                raise SystemExit('Structural checks failed; see verification/structural_validation.json')
            print(f"PASS: {len(report['runs'])} structural cases, skin binding, strength sensitivity, replay and reset.")
        if args.command in ('verify', 'verify-wheels'):
            run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/verify_wheels.gd'])
            report = json.loads((ROOT / 'verification/wheel_validation.json').read_text())
            if not report['passed']:
                raise SystemExit('Wheel checks failed; see verification/wheel_validation.json')
            print(f"PASS: {len(report['runs'])} wheel cases, standing support, load transfer, suspension failure, detachment and replay.")
        if args.command in ('verify', 'verify-wheels'):
            run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/verify_wheel_mounts.gd'])
            report = json.loads((ROOT / 'verification/wheel_mount_validation.json').read_text())
            if not report['passed']:
                raise SystemExit('Wheel mount checks failed; see verification/wheel_mount_validation.json')
            print('PASS: rigid lateral mounts, permanent bending, full release and visible load fixture.')
        if args.command in ('verify', 'verify-driving'):
            run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/verify_driving.gd'])
            report = json.loads((ROOT / 'verification/driving_validation.json').read_text())
            if not report['passed']:
                raise SystemExit('Driving checks failed; see verification/driving_validation.json')
            print('PASS: shared runtime, throttle, brakes, steering direction, reverse, tuning and persistent damage.')
        if args.command in ('verify', 'verify-adaptive'):
            run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/verify_adaptive.gd'])
            report = json.loads((ROOT / 'verification/adaptive_validation.json').read_text())
            run([sys.executable, str(ROOT / 'tools/format_adaptive_report.py')])
            if not report['passed']:
                raise SystemExit('Adaptive checks failed; see verification/adaptive_validation.json')
            print('PASS: adaptive driving, forecast wake-up, continuous handoff, collision and timing comparison.')
        if args.command in ('verify', 'verify-ramps'):
            run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/verify_ramps.gd'])
            report = json.loads((ROOT / 'verification/ramp_validation.json').read_text())
            if not report['passed']:
                raise SystemExit('Ramp checks failed; see verification/ramp_validation.json')
            print('PASS: matching ramp/contact surfaces, natural takeoff and landing on both jumps.')
        if args.command in ('verify', 'verify-retention'):
            run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/verify_wheel_retention.gd'])
            report = json.loads((ROOT / 'verification/wheel_retention_validation.json').read_text())
            if not report['passed']:
                raise SystemExit('Wheel retention checks failed')
            print('PASS: rear wheel retention in crashes, extreme front release, and suspension absorbing both ramp landings.')
        if args.command in ('verify', 'verify-baked'):
            run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/verify_baked_roundtrip.gd'])
            report = json.loads((ROOT / 'verification/baked_roundtrip_validation.json').read_text())
            if not report['passed']:
                raise SystemExit('Baked round-trip checks failed')
            run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/verify_crash_library.gd'])
            library_report = json.loads((ROOT / 'verification/crash_library_validation.json').read_text())
            if not library_report['passed']:
                raise SystemExit('Crash library checks failed')
            print('PASS: complete impact library, contact-time nearest selection, registered replay and zero full solver steps.')
        if args.command in ('verify', 'verify-driving-bakes'):
            run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/verify_driving_bakes.gd'])
            report = json.loads((ROOT / 'verification/driving_bakes_validation.json').read_text())
            if not report['passed']:
                raise SystemExit('Driving bake integration checks failed')
            print('PASS: real driving triggers, continuous live/baked handoff, zero-forecast rigid recovery, live tuning, reset and fallback paths.')
        if args.command in ('verify', 'verify-effects'):
            for script in ('verify_vehicle_glass', 'verify_vehicle_interior'):
                run([binary, '--headless', '--path', str(ROOT), '--script', f'res://scripts/{script}.gd'])
            print('PASS: live/baked retained glass, fragment motion, seat hinges and optional airbag.')
        if args.command in ('verify', 'verify-sequence'):
            for script in ('verify_baked_contact_sensor', 'verify_conditioned_transitions',
                           'verify_conditioned_bank', 'verify_sandbox_sequence'):
                run([binary, '--headless', '--path', str(ROOT), '--script', f'res://scripts/{script}.gd'])
            print('PASS: sensitive contact, compatible damaged-state transitions and three sandbox impacts without live solves.')
        if args.command in ('verify', 'verify-quality'):
            run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/verify_quality_smoke.gd'])
            if args.command == 'verify-quality':
                run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/verify_authoring_quality.gd'])
        if args.command in ('verify', 'verify-surfaces'):
            run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/verify_vehicle_surface.gd'])
            report = json.loads((ROOT / 'verification/vehicle_surface_validation.json').read_text())
            if not report['passed']:
                raise SystemExit('Surface state/skin/replay checks failed')
            print('PASS: live/baked surface lifecycle, deterministic seeking, persistence, repair and native skin.')
        if args.command in ('verify', 'verify-roof'):
            run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/verify_roof_bank.gd'])
        if args.command in ('verify', 'verify-arena'):
            run([binary, '--headless', '--path', str(ROOT), '--script', 'res://arena/verify.gd'])
            report = json.loads((ROOT / 'verification/arena_validation.json').read_text())
            if not report['passed']:
                raise SystemExit('Arena driving/contact checks failed')
            print('PASS: arena contact surfaces, jump landings, paired ramps, wheel retention and ring boundary.')
    elif args.command == 'damage-studio':
        run([binary, '--path', str(ROOT), '--resolution', '1600x1000', 'res://probes/damage_studio/studio.tscn'])
    elif args.command == 'capture-surfaces':
        command = [binary, '--path', str(ROOT), '--script', 'res://scripts/capture_damage_integration.gd']
        import json
        import time
        for label, suffix in [('baked', []), ('live', ['--', '--surface-live'])]:
            started = time.time()
            run(command + suffix)
            report = json.loads((ROOT / f'verification/damage_surface/{label}_journey.json').read_text())
            if not report.get('repair_cleared') or report.get('completed_at', 0) < started:
                raise SystemExit(f'{label} capture ended before the journey completed')
    elif args.command == 'bake':
        run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/bake_frontal_clip.gd'])
    elif args.command == 'index-bakes':
        run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/bake_frontal_clip.gd', '--', '--index-only'])
    elif args.command == 'baked':
        run([binary, '--path', str(ROOT), 'res://baked_probe.tscn'])
    elif args.command == 'baked-3d':
        run([binary, '--path', str(ROOT), 'res://multiaxis_crash_viewer.tscn'])
    elif args.command == 'capture-baked':
        run([binary, '--path', str(ROOT), '--script', 'res://scripts/capture_baked.gd', '--', '--capture-baked'])
    elif args.command in ('drive', 'drive-sequence'):
        command = [binary, '--path', str(ROOT), 'res://driving.tscn']
        if args.command == 'drive-sequence':
            command += ['--', '--baked-sequence']
        run(command)
    elif args.command == 'arena':
        run([binary, '--path', str(ROOT), 'res://arena/colosseum.tscn'])
    elif args.command == 'capture-driving':
        run([binary, '--path', str(ROOT), '--script', 'res://scripts/capture_driving.gd', '--', '--capture-driving'])
    elif args.command == 'capture':
        run([binary, '--path', str(ROOT), '--script', 'res://scripts/capture_hidden.gd', '--', '--capture-structure'])
    else:
        run([binary, '--path', str(ROOT), '--', '--autoplay'])


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode)
