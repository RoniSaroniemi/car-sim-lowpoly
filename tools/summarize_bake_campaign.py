#!/usr/bin/env python3
"""Summarize saved assets and measured job reports; publish only a complete audit."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {'horizontal': 37, 'partial': 48, 'multiaxis': 36, 'roof': 2, 'conditioned': 3}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    audit_path = ROOT / 'verification/bake_campaign/asset_audit.json'
    audit = json.loads(audit_path.read_text()) if audit_path.exists() else {}
    audited_metadata = {row['id']: row['metadata'] for row in audit.get('records', [])
                        if not row.get('pending') and not row.get('failures')}
    records = []
    for family, expected in EXPECTED.items():
        directory = ROOT / 'bakes' / ('' if family == 'horizontal' else family)
        assets = []
        for clip in sorted(directory.glob('*.crashclip')):
            sidecar = clip.with_suffix('.json')
            # Conditioned clips intentionally keep metadata inside compressed
            # files; use the read-only disk auditor's extracted metadata.
            meta = json.loads(sidecar.read_text()) if sidecar.exists() else audited_metadata.get(clip.stem)
            if meta is None:
                continue
            assets.append({'id': meta['id'], 'bytes': clip.stat().st_size,
                           'frames': meta.get('frame_count', audit.get('samples_per_clip', 0)), 'physics_hz': meta['physics_hz'],
                           'sample_hz': meta['sample_hz'], 'duration_s': meta['duration_s'],
                           'panels_schema': meta.get('panels_schema', 0)})
        path = ROOT / 'verification' / 'bake_campaign' / (family + '.json')
        timing = json.loads(path.read_text()) if path.exists() else {}
        cpu = timing.get('total_cpu_s', sum(job.get('user_s', 0) + job.get('sys_s', 0)
                                          for job in timing.get('jobs', [])))
        pilot_process_wall = 0
        if family == 'multiaxis':
            receipt = ROOT / 'verification/multiaxis/pilot_receipt.json'
            if receipt.exists():
                pilots = json.loads(receipt.read_text())['process_timing']
                pilot_cpu = sum(p['user_cpu_s'] + p['system_cpu_s'] for p in pilots.values())
                # These three externally measured pilots are reused by the driver.
                cpu = (cpu or 0) + pilot_cpu
                pilot_process_wall = sum(p['wall_s'] for p in pilots.values())
        records.append({'family': family, 'expected': expected, 'count': len(assets),
                        'bytes': sum(a['bytes'] for a in assets),
                        'frames': sum(a['frames'] for a in assets),
                        'stored_animation_seconds': sum(a['duration_s'] for a in assets),
                        'driver_wall_s': timing.get('wall_elapsed_s'),
                        'family_elapsed_s': timing.get('campaign_elapsed_s', timing.get('wall_elapsed_s')),
                        'completed_job_cpu_s': cpu,
                        'external_pilot_process_wall_s': pilot_process_wall,
                        'workers': timing.get('workers'),
                        'timing_complete': timing.get('complete', False) and timing.get('success', False),
                        'assets': assets})
    report = {'generated_utc': datetime.now(timezone.utc).isoformat(),
              'families': records, 'clips': sum(r['count'] for r in records),
              'bytes': sum(r['bytes'] for r in records),
              'frames': sum(r['frames'] for r in records),
              'completed_job_cpu_s': sum(r['completed_job_cpu_s'] or 0 for r in records),
              'audit': {key: audit.get(key) for key in ('passed', 'complete', 'audited', 'failed', 'pending', 'expected_count', 'samples_per_clip', 'registration_samples')},
              'raw_audit_path': 'verification/bake_campaign/asset_audit.json',
              'timing_scope': 'Completed baking processes only; verification/rendering excluded. '
                  'Family elapsed times overlap and must not be added. Driver timings exclude '
                  'earlier reused pilots; CPU includes their independently measured process time. '
                  'Multiaxis upper/underside pilot CPU was measured as one sequential process. '
                  'Interrupted partial attempts are excluded from completed-job CPU.'}
    quality_path = ROOT / 'verification/multiaxis/final_acceptance.json'
    quality = json.loads(quality_path.read_text()) if quality_path.exists() else {}
    report['multiaxis_physical_quality'] = {
        key: quality.get(key) for key in ('replay_passed', 'finite_states_passed', 'mass_passed', 'energy_quality_passed')}
    report['physical_readiness_passed'] = bool(audit.get('passed') and audit.get('complete')
                                              and quality.get('energy_quality_passed'))
    logs = [ROOT / 'verification/bake_campaign/pilot_frontal_60.log']
    for row in records:
        timing_path = ROOT / 'verification/bake_campaign' / (row['family'] + '.json')
        if not timing_path.exists():
            continue
        for job in json.loads(timing_path.read_text()).get('jobs', []):
            logs.append(ROOT / job.get('log', 'verification/bake_campaign/' + job['id'] + '.log'))
    intervals = []
    for log in logs:
        if not log.exists():
            continue
        real = re.findall(r'^real\s+([\d.]+)$', log.read_text(), re.M)
        if real:
            end = log.stat().st_mtime
            intervals.append((end - float(real[-1]), end))
    if intervals:
        report['observed_baking_span_s'] = max(end for _, end in intervals) - min(start for start, _ in intervals)
        report['observed_baking_span_scope'] = 'Approximate first bake-process start to last completion; overlaps authoring and verification. Derived from retained raw log timestamps and measured process durations.'
    destination = ROOT / 'verification/bake_campaign/summary.json'
    destination.write_text(json.dumps(report, indent=2) + '\n')
    print('family       clips      MiB   elapsed_s     CPU_s')
    for row in records:
        elapsed = row['family_elapsed_s']
        cpu = row['completed_job_cpu_s']
        print(f"{row['family']:12} {row['count']:3}/{row['expected']:<3} "
              f"{row['bytes']/2**20:8.2f} {elapsed if elapsed is not None else 0:11.2f} "
              f"{cpu if cpu is not None else 0:9.2f}")
    if args.publish:
        if not all(r['count'] == r['expected'] and r['timing_complete'] for r in records):
            raise SystemExit('Cannot publish: campaign is incomplete or has failed jobs')
        # Keep acceptance tied to a final audit, not just file counts.
        if not audit.get('passed', False) or not audit.get('complete', False):
            raise SystemExit('Cannot publish: run the complete 126-asset audit first')
        target = ROOT / 'docs/evidence/bake_campaign_stats.json'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(report, indent=2) + '\n')
        print('Published', target)


if __name__ == '__main__':
    main()
