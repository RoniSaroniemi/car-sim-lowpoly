#!/usr/bin/env python3
"""Check handover integrity without Godot, Blender or third-party Python packages."""
from pathlib import Path
import hashlib
import json
import struct
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
structure_path = root / 'structure.json'
before = structure_path.read_bytes()
subprocess.run([sys.executable, str(root / 'scripts/build_structure.py')], check=True, cwd=root)
assert structure_path.read_bytes() == before, 'Generated structure differs from the checked-in definition'
s = json.loads(before)
assert len(s['nodes']) == 38 and len(s['links']) == 175
assert abs(sum(n['mass_kg'] for n in s['nodes']) - 1210) < 1e-6
assert sum(s['nodes'][i]['mass_kg'] for i in s['engine_nodes']) == 190
assert all(l['stiffness_n_per_m'] > 0 and l['yield_n'] > 0 for l in s['links'])
assert all(0 <= l[k] < len(s['nodes']) for l in s['links'] for k in ('a', 'b'))
payload = (root / 'assets/Niva_2121_LOD0.glb').read_bytes()
magic, version, length = struct.unpack_from('<III', payload)
assert magic == 0x46546C67 and version == 2 and length == len(payload)
chunk_length, chunk_type = struct.unpack_from('<II', payload, 12)
assert chunk_type == 0x4E4F534A
model = json.loads(payload[20:20 + chunk_length])
wheel_names = [n['name'] for n in model['nodes'] if n.get('name', '').startswith('Wheel_') and 'mesh' in n]
assert len(wheel_names) == 4, wheel_names
assert any(n.get('name') == 'Niva_Body_Static' for n in model['nodes'])
assert (root / 'model/Niva_2121.blend').read_bytes().startswith(b'BLENDER')
manifest = json.loads((root / 'checksums.json').read_text())
for filename, expected in manifest.items():
    assert hashlib.sha256((root / filename).read_bytes()).hexdigest() == expected, filename
assert json.loads((root / 'verification/baseline.json').read_text())['passed']
print('PASS: reproducible graph, 1,210 kg, GLB structure, editable model and published file checksums.')
