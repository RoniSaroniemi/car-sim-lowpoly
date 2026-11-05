#!/usr/bin/env python3
"""Run bounded offline jobs, retaining per-process timing and resumable reports.

Use --family horizontal|partial|roof|conditioned. Build horizontal before
conditioned. Resume skips only files whose recorded source hashes still match.
The simulation's record_cpu_ms is elapsed recorder time; user/sys below come
from the operating system and are CPU time, including process setup and save.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import json
import os
import signal
from pathlib import Path
import re
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='/Applications/Godot.app/Contents/MacOS/Godot')
    parser.add_argument('--family', required=True, choices=['horizontal', 'partial', 'roof', 'conditioned', 'multiaxis', 'roof_landing'])
    parser.add_argument('--workers', type=int, default=4)
    parser.add_argument('--resume', action='store_true')
    parser.add_argument('--timeout', type=float, default=1200)
    args = parser.parse_args()
    if not 1 <= args.workers <= 8:
        parser.error('--workers must be between 1 and 8')
    command = [args.godot, '--headless', '--path', str(ROOT), '--script']
    inventory = subprocess.run(command + ['res://scripts/bake_campaign_catalog.gd'],
                               capture_output=True, text=True, check=True, timeout=30)
    lines = [line for line in inventory.stdout.splitlines() if line.startswith('BAKE_JOBS_JSON=')]
    if len(lines) != 1:
        raise RuntimeError(inventory.stdout + inventory.stderr)
    jobs = [job for job in json.loads(lines[0].split('=', 1)[1]) if job['family'] == args.family]
    output = ROOT / 'verification' / 'bake_campaign'
    output.mkdir(parents=True, exist_ok=True)
    report_path = output / (args.family + '.json')
    previous = json.loads(report_path.read_text()) if args.resume and report_path.exists() else {}
    report = {'started_utc': datetime.now(timezone.utc).isoformat(), 'family': args.family,
              'workers': args.workers, 'quality_multiplier': 4, 'jobs': [], 'complete': False}
    report['first_started_utc'] = previous.get('first_started_utc', previous.get('started_utc', report['started_utc']))
    report['previous_attempts'] = previous.get('previous_attempts', [])
    if previous:
        report['previous_attempts'].append({key: previous.get(key) for key in ('started_utc', 'workers', 'wall_elapsed_s', 'complete')})
    began = time.monotonic()
    lock = threading.Lock()

    def save():
        report['wall_elapsed_s'] = time.monotonic() - began
        first = datetime.fromisoformat(report['first_started_utc'])
        report['campaign_elapsed_s'] = (datetime.now(timezone.utc) - first).total_seconds()
        temporary = report_path.with_suffix('.tmp')
        temporary.write_text(json.dumps(report, indent=2) + '\n')
        temporary.replace(report_path)

    def existing(job):
        if not job['metadata']:
            return None
        path = ROOT / job['metadata']
        if not path.exists():
            return None
        meta = json.loads(path.read_text())
        if meta.get('quality_multiplier') != 4 or meta.get('panels_schema') != 1:
            return None
        fingerprints = meta.get('input_sha256', {})
        if not fingerprints or any(not (ROOT / name).is_file() or
                hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest
                for name, digest in fingerprints.items()):
            return None
        clip = path.with_suffix('.crashclip')
        if not clip.exists() or clip.stat().st_size != meta['clip_bytes']:
            return None
        return meta

    def run(job):
        result = {'id': job['id'], 'metadata': job['metadata']}
        meta = existing(job) if args.resume else None
        if meta is not None:
            result.update(status='reused_exact_source', frames=meta['frame_count'],
                          bytes=meta['clip_bytes'], record_elapsed_ms=meta.get('record_cpu_ms'))
            # Retain an independently measured pilot when resuming this batch.
            pilot = output / ('pilot_frontal_60.log' if job['id'] == 'impact_000_60' else job['id'] + '.log')
            if pilot.exists():
                for name, value in re.findall(r'^(real|user|sys)\s+([\d.]+)$', pilot.read_text(), re.M):
                    result[name + '_s'] = float(value)
            return result
        log = output / (job['id'] + '.log')
        started = time.monotonic()
        cmd = ['/usr/bin/time', '-p'] + command + ['res://scripts/' + job['script'], '--'] + job['args']
        with log.open('w') as handle:
            try:
                process = subprocess.Popen(cmd, stdout=handle, stderr=subprocess.STDOUT, start_new_session=True)
                result['returncode'] = process.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                result['status'] = 'timeout'
        text = log.read_text()
        result['process_wall_s'] = time.monotonic() - started
        for name, value in re.findall(r'^(real|user|sys)\s+([\d.]+)$', text, re.M):
            result[name + '_s'] = float(value)
        # Godot can emit a script error and still exit 0; reject that explicitly.
        if result.get('status') != 'timeout':
            valid = result['returncode'] == 0 and 'SCRIPT ERROR:' not in text and 'ERROR:' not in text
            meta = existing(job) if job['metadata'] else None
            if job['metadata'] and meta is None:
                valid = False
            result['status'] = 'passed' if valid else 'failed'
            if meta:
                result.update(frames=meta['frame_count'], bytes=meta['clip_bytes'],
                              record_elapsed_ms=meta.get('record_cpu_ms'))
        result['log'] = str(log.relative_to(ROOT))
        return result

    save()
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(run, job) for job in jobs]
        for future in as_completed(futures):
            result = future.result()
            with lock:
                report['jobs'].append(result)
                save()
            print(f"{len(report['jobs'])}/{len(jobs)} {result['id']} {result['status']} "
                  f"wall={result.get('real_s', 0):.2f}s", flush=True)
    report['complete'] = True
    report['success'] = all(job['status'] in ('passed', 'reused_exact_source') for job in report['jobs'])
    report['total_cpu_s'] = sum(job.get('user_s', 0) + job.get('sys_s', 0) for job in report['jobs'])
    report['total_bytes'] = sum(job.get('bytes', 0) for job in report['jobs'])
    save()
    print(str(report_path))
    raise SystemExit(0 if report['success'] else 1)


if __name__ == '__main__':
    main()
