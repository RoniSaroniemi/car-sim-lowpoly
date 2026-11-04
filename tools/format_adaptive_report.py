#!/usr/bin/env python3
"""Format actual Godot benchmark results; Python standard library only."""
from pathlib import Path
import csv
import json
import statistics

ROOT = Path(__file__).resolve().parents[1]
r = json.loads((ROOT / 'verification/adaptive_validation.json').read_text())
lines = ['# Adaptive vehicle benchmark', '',
         'Measured simulation code, milliseconds per simulated second; rendering excluded. '
         'Two serial trials with reversed order. Timings are wall-clock sections on this host, '
         'not an FPS or multi-car guarantee.', '',
         '| Scenario | Full reference, ms/s | Adaptive, ms/s | Speedup | Adaptive full-solver time |',
         '|---|---:|---:|---:|---:|']
summary = {}
for scenario in ('clear_road', 'head_on'):
    base = [x for x in r['runs'] if x['scenario'] == scenario and not x['adaptive']]
    adapt = [x for x in r['runs'] if x['scenario'] == scenario and x['adaptive']]
    full_ms = statistics.median(x['cpu_ms_per_sim_second'] for x in base)
    adaptive_ms = statistics.median(x['cpu_ms_per_sim_second'] for x in adapt)
    ratio = full_ms / adaptive_ms
    fraction = statistics.median(x['full_time_fraction'] for x in adapt)
    summary[scenario] = dict(full_ms_per_sim_second=full_ms,
                             adaptive_ms_per_sim_second=adaptive_ms,
                             speedup=ratio, full_time_fraction=fraction)
    lines.append(f'| {scenario} | {full_ms:.1f} | {adaptive_ms:.1f} | {ratio:.2f}x | {fraction:.1%} |')
head = next(x for x in r['runs'] if x['scenario'] == 'head_on' and x['adaptive'])
base = next(x for x in r['runs'] if x['scenario'] == 'head_on' and not x['adaptive'])
lines += ['', f"- Forecast activated {head.get('wake_lead_s', 0):.3f} s before contact, at {head.get('wake_clearance_m', 0):.2f} m clearance.",
          f"- Impact speeds: full reference {base['impact_speed_kmh']:.2f} km/h; adaptive {head['impact_speed_kmh']:.2f} km/h.",
          f"- Activation discontinuity: {head['handoff_position_jump_m']:.8f} m, {head['handoff_velocity_jump_mps']:.8f} m/s.",
          '- A matched-state full-solver continuation is checked separately from whole-trajectory differences.',
          '- The compact body is an approximation; trajectories and wreck shapes need not be identical.', '',
          f"Overall verification: {'PASS' if r['passed'] else 'FAIL'}", '', '| Check | Passed |', '|---|---|']
lines += [f'| {key} | {value} |' for key, value in r['checks'].items()]
(ROOT / 'verification/adaptive_report.md').write_text('\n'.join(lines) + '\n')
(ROOT / 'verification/adaptive_summary.json').write_text(json.dumps(summary, indent=2) + '\n')
with (ROOT / 'verification/adaptive_trace.csv').open('w', newline='') as stream:
    fields = ['scenario', 'adaptive', 'trial', 'time_s', 'mode', 'speed_kmh', 'body_x_m', 'plastic_work_kj', 'full_steps']
    writer = csv.DictWriter(stream, fieldnames=fields)
    writer.writeheader()
    for case in r['runs']:
        for sample in case['samples']:
            writer.writerow({**{k: case[k] for k in ('scenario', 'adaptive', 'trial')}, **sample})
print('\n'.join(lines[:18]))
