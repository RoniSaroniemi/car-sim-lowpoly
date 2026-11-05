#!/usr/bin/env python3
"""Bounded production panel integration checks; leaves published banks alone."""
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
binary = os.environ.get('GODOT_BIN') or shutil.which('godot') or shutil.which('godot4')
if not binary:
    candidate = Path('/Applications/Godot.app/Contents/MacOS/Godot')
    binary = str(candidate) if candidate.exists() else None
if not binary:
    raise SystemExit('Set GODOT_BIN to the Godot4.7 executable')
for name in ('smoke', 'snapshots', 'glass', 'contrasts', 'driving', 'continuation_audit', 'author_roundtrip'):
    subprocess.run([binary, '--headless', '--path', str(ROOT), '--script',
                    f'res://tests/panels/{name}.gd'], check=True, timeout=240)
print('PASS: shared panel controls, mass, glass, driving, reduced mounts and replay ownership.')
