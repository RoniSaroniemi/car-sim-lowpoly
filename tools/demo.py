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
    parser.add_argument('command', choices=('run', 'verify', 'verify-wheels', 'verify-driving', 'drive', 'capture-driving', 'capture', 'import', 'check'))
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
    if args.command in ('verify', 'verify-wheels', 'verify-driving'):
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
        if args.command in ('verify', 'verify-driving'):
            run([binary, '--headless', '--path', str(ROOT), '--script', 'res://scripts/verify_driving.gd'])
            report = json.loads((ROOT / 'verification/driving_validation.json').read_text())
            if not report['passed']:
                raise SystemExit('Driving checks failed; see verification/driving_validation.json')
            print('PASS: shared runtime, throttle, brakes, steering direction, reverse, tuning and persistent damage.')
    elif args.command == 'drive':
        run([binary, '--path', str(ROOT), 'res://driving.tscn'])
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
