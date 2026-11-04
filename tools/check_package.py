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
assert len(s['nodes']) == 38 and len(s['links']) == 187
assert abs(sum(n['mass_kg'] for n in s['nodes']) - 1210) < 1e-6
assert sum(s['nodes'][i]['mass_kg'] for i in s['engine_nodes']) == 190
assert all(l['stiffness_n_per_m'] > 0 and l['yield_n'] > 0 for l in s['links'])
assert all(0 <= l[k] < len(s['nodes']) for l in s['links'] for k in ('a', 'b'))
assert s['schema_version'] == 3 and len(s['wheel_assemblies']) == 4
assert {w['node'] for w in s['wheel_assemblies']} == set(s['wheel_nodes'])
for wheel in s['wheel_assemblies']:
    anchors = [l for l in s['links'] if l['a'] == wheel['node'] and 'wheel_anchor' in l]
    assert len(anchors) == 6
    assert all(l['break_force_n'] > l['yield_n'] and l['break_delay_s'] > 0 for l in anchors)
    assert wheel['rim_radius_m'] < wheel['radius_m'] and wheel['half_width_m'] > 0
    assert all(0 <= c[k] < len(s['nodes']) for c in wheel['body_capsules'] for k in ('a', 'b'))
profile = json.loads((root / 'vehicles/niva.json').read_text())
for key in ('structure', 'model'):
    assert profile[key].startswith('res://')
    assert (root / profile[key][6:]).is_file(), profile[key]
for key in ('driven_wheels', 'steering_wheels', 'handbrake_wheels'):
    assert profile['dynamics'][key]
    assert all(type(i) is int and 0 <= i < len(s['wheel_assemblies'])
               for i in profile['dynamics'][key])
assert profile['dynamics']['drive_torque_nm'] > 0
assert profile['dynamics']['max_speed_kmh'] > profile['dynamics']['reverse_speed_kmh'] > 0
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
print('PASS: reproducible graph, 1,210 kg, GLB structure, editable model, shared vehicle profile and published file checksums.')
