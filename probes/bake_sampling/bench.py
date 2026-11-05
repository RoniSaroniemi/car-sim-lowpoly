#!/usr/bin/env python3
"""Fresh-process data loading only. Does not change main assets or runtime."""
from pathlib import Path
import json,os,shutil,statistics,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
GODOT=os.environ.get('GODOT_BIN') or shutil.which('godot') or shutil.which('godot4') or '/Applications/Godot.app/Contents/MacOS/Godot'
OUT=ROOT/'verification/bake_sampling'
variants={'source_120':['res://bakes/frontal_120.crashclip']}
for hz in (120,30,15,'adaptive'):
 variants[f'snapshots_{hz}']=[f'res://verification/bake_sampling/snapshots_{hz}.track']
 variants[f'packed_{hz}']=[f'res://verification/bake_sampling/packed_{hz}.track']
 variants[f'first_packet_{hz}']=[f'res://verification/bake_sampling/header_{hz}.track',f'res://verification/bake_sampling/packet_{hz}_0.track']
rows=[]
for name,paths in variants.items():
 trials=[]
 for _ in range(3):
  start=time.perf_counter()
  result=subprocess.run([GODOT,'--headless','--path',str(ROOT),'--script','res://probes/bake_sampling/load_bench.gd','--',*paths],cwd=ROOT,text=True,capture_output=True,timeout=30,check=True)
  line=next((x for x in result.stdout.splitlines() if x.startswith('LOAD_BENCH ')),None)
  if line is None:raise RuntimeError(result.stdout+'\n'+result.stderr)
  data=json.loads(line.removeprefix('LOAD_BENCH '));data['process_wall_ms']=(time.perf_counter()-start)*1000;trials.append(data)
 row={'name':name,'paths':paths,'disk_bytes':trials[0]['disk_bytes'],'median_load_decode_ms':statistics.median(t['load_decode_ms'] for t in trials),'median_engine_heap_bytes':statistics.median(t['engine_static_heap_delta_bytes'] for t in trials),'median_observed_heap_peak_bytes':statistics.median(t['engine_static_heap_observed_peak_delta_bytes'] for t in trials),'heap_counter_available':all(t['heap_counter_available'] for t in trials),'trials':trials}
 rows.append(row);print(name,row['disk_bytes'],round(row['median_load_decode_ms'],3),row['median_engine_heap_bytes'],flush=True)
(OUT/'loading.json').write_text(json.dumps({'scope':'3 fresh Godot processes pervariant; OS file cache not evicted, so this is not a cold physical disk test. Load/decode excludes process startup and rendering. Heap is Godot static allocations, not OS RSS or a proven allocation high water mark. First-packet rows load metadata plus only the first0.5s block.','rows':rows},indent=2)+'\n')
