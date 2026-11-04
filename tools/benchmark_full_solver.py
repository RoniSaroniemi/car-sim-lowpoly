#!/usr/bin/env python3
"""Benchmark an isolated full-XPBD candidate; never changes the live solver.

Requires Godot and git. Default comparisons use 480 Hz and eight sweeps; the
adaptive runtime, graphics, skinning and replay recorder do not participate.
An explicit --candidate-sweeps flag permits rejected accuracy experiments.
"""
from pathlib import Path
import argparse
import hashlib
import gzip
import platform
import json
import math
import shutil
import statistics
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

SINGLE_BENCHMARK_GD = r'''extends SceneTree
const Solver=preload('res://scripts/structure_solver.gd')
func _initialize() -> void:
 call_deferred('_run')
func _run() -> void:
 var results: Array=[]
 var args=OS.get_cmdline_user_args()
 var only_profile: bool='--profile' in args
 var tests: Array=[{'speed':20,'mode':0},{'speed':50,'mode':0},{'speed':80,'mode':0},{'speed':120,'mode':0},{'speed':80,'mode':1},{'speed':120,'mode':1},{'speed':120,'mode':1,'body_contact':false},{'speed':80,'mode':0,'weak':true}]
 if only_profile:tests=[{'speed':120,'mode':0},{'speed':120,'mode':1}]
 for test in tests:
  var s=Solver.new()
  s.setup()
  s.set_impact_mode(test.mode)
  s.wheels.body_contact_enabled=test.get('body_contact',true)
  s.reset(test.speed,Vector3(-9,0,0),test.get('weak',false))
  var frames: Array=[]
  var start: int=Time.get_ticks_usec()
  var dt: float=s.config.fixed_step_s
  var max_speed:=0.0
  var finite:=true
  var minimum_floor:=100.0
  var minimum_barrier:=100.0
  for step in 1440:
   s.step(dt)
   if step%24==23:
    var frame: Dictionary={'points':[],'lengths':[],'plastic_work':s.plastic_work,'broken':[],'detached':[]}
    for i in s.points.size():
     frame.points.append([s.points[i].x,s.points[i].y,s.points[i].z])
     finite=finite and s.points[i].is_finite() and s.velocities[i].is_finite()
     max_speed=maxf(max_speed,s.velocities[i].length())
     if s.config.nodes[i].group!='wheel':
      minimum_floor=minf(minimum_floor,s.points[i].y-s.radii[i])
      minimum_barrier=minf(minimum_barrier,float(s.barrier_distance(s.points[i]).distance)-s.radii[i])
    for l in s.links:
     frame.lengths.append(l.length)
     frame.broken.append(l.broken)
    for w in s.wheels.wheels:
     frame.detached.append(w.detached)
     finite=finite and w.rotation.is_finite() and w.angular_velocity.is_finite() and is_finite(w.spin_speed)
     minimum_floor=minf(minimum_floor,s.points[w.node].y+s.wheels.support(w,Vector3.DOWN).y+w.max_compression)
     var hit: Dictionary=s.barrier_distance(s.points[w.node])
     minimum_barrier=minf(minimum_barrier,float(hit.distance)+hit.normal.dot(s.wheels.support(w,-hit.normal))+w.max_compression)
    frames.append(frame)
  var elapsed: int=Time.get_ticks_usec()-start
  var result: Dictionary={'test':test,'elapsed_us':elapsed,'metrics':s.metrics(),'frames':frames,'finite':finite,'max_speed_mps':max_speed,'minimum_floor_m':minimum_floor,'minimum_barrier_m':minimum_barrier}
  if only_profile:result['phases']=s.phase_us
  results.append(result)
  print('CASE ',JSON.stringify({'test':test,'elapsed_us':elapsed,'metrics':result.metrics,'phases':result.get('phases',{})}))
 var output: String=args[args.find('--output')+1]
 FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(results))
 quit()
'''

BENCHMARK_GD = r'''extends SceneTree
const Baseline=preload('res://scripts/structure_solver.gd')
const Candidate=preload('res://scripts/candidate_solver.gd')
func _initialize() -> void:
 call_deferred('_run')
func _sample(s: RefCounted,result: Dictionary) -> void:
 var frame: Dictionary={'points':[],'lengths':[],'plastic_work':s.plastic_work,'broken':[],'detached':[]}
 for i in s.points.size():
  frame.points.append([s.points[i].x,s.points[i].y,s.points[i].z])
  result.finite=result.finite and s.points[i].is_finite() and s.velocities[i].is_finite()
  result.max_speed_mps=maxf(result.max_speed_mps,s.velocities[i].length())
  if s.config.nodes[i].group!='wheel':
   result.minimum_floor_m=minf(result.minimum_floor_m,s.points[i].y-s.radii[i])
   result.minimum_barrier_m=minf(result.minimum_barrier_m,float(s.barrier_distance(s.points[i]).distance)-s.radii[i])
 for l in s.links:
  frame.lengths.append(l.length)
  frame.broken.append(l.broken)
 for w in s.wheels.wheels:
  frame.detached.append(w.detached)
  result.finite=result.finite and w.rotation.is_finite() and w.angular_velocity.is_finite() and is_finite(w.spin_speed)
  result.minimum_floor_m=minf(result.minimum_floor_m,s.points[w.node].y+s.wheels.support(w,Vector3.DOWN).y+w.max_compression)
  var hit: Dictionary=s.barrier_distance(s.points[w.node])
  result.minimum_barrier_m=minf(result.minimum_barrier_m,float(hit.distance)+hit.normal.dot(s.wheels.support(w,-hit.normal))+w.max_compression)
 result.frames.append(frame)
func _run() -> void:
 var output: Dictionary={'baseline':[],'candidate':[]}
 var args=OS.get_cmdline_user_args()
 var tests: Array=[{'speed':20,'mode':0},{'speed':50,'mode':0},{'speed':80,'mode':0},{'speed':120,'mode':0},{'speed':80,'mode':1},{'speed':120,'mode':1},{'speed':120,'mode':1,'body_contact':false},{'speed':80,'mode':0,'weak':true}]
 for test in tests:
  var solvers: Array=[Baseline.new(),Candidate.new()]
  var results: Array=[]
  for s in solvers:
   s.setup()
   s.set_impact_mode(test.mode)
   s.wheels.body_contact_enabled=test.get('body_contact',true)
   s.reset(test.speed,Vector3(-9,0,0),test.get('weak',false))
   results.append({'test':test,'frames':[],'finite':true,'max_speed_mps':0.0,'minimum_floor_m':100.0,'minimum_barrier_m':100.0})
  if '--candidate-sweeps' in args:solvers[1].config.iterations=int(args[args.find('--candidate-sweeps')+1])
  var dt: float=solvers[0].config.fixed_step_s
  for step in 1440:
   # Reverse order each substep to cancel first/second execution bias.
   for index in ([0,1] if step%2==0 else [1,0]):
    solvers[index].step(dt)
    if step%24==23:_sample(solvers[index],results[index])
  for index in 2:
   results[index]['metrics']=solvers[index].metrics()
   results[index]['elapsed_us']=solvers[index].total_step_us
  output.baseline.append(results[0])
  output.candidate.append(results[1])
  print('PAIRED ',JSON.stringify({'test':test,'baseline_us':results[0].metrics.mean_step_us,'candidate_us':results[1].metrics.mean_step_us,'speedup':results[0].metrics.mean_step_us/results[1].metrics.mean_step_us}))
 FileAccess.open(args[args.find('--output')+1],FileAccess.WRITE).store_string(JSON.stringify(output))
 quit()
'''

FIXTURES_GD = r'''extends SceneTree
const Solver=preload('res://scripts/structure_solver.gd')
func _initialize() -> void:
 call_deferred('_run')
func _run() -> void:
 var s=Solver.new()
 s.setup()
 var dt: float=s.config.fixed_step_s
 s.step(dt)
 var results: Array=[]
 for index in [0,42,43,78,79,82,88,143,149,163,166,167]:
  for weak in [false,true]:
   for ratio in [.99,1.0,1.01,2.0,-.99,-1.0,-1.01,-2.0]:
    s.reset(0,Vector3(-9,0,0),weak)
    var l=s.links[index]
    var anchor:=Vector3.ZERO
    if l.wheel_index>=0:anchor=s.wheels.anchor(l.wheel_index,l.wheel_anchor)
    var direction: Vector3=(s.points[l.b]-s.points[l.a]-anchor).normalized()
    var w: float=l.weight_sum
    if l.wheel_index>=0:w+=s.wheels.rotational_weight(l.wheel_index,anchor,direction)
    var alpha: float=l.compliance/(dt*dt)
    var target_force: float=l.yield_n*ratio
    # For initially zero lambda this extension requests exactly the selected
    # force ratio (before float32 node rounding and hardening/tension factors).
    var extension: float=target_force*dt*dt*(w+alpha)
    s.points[l.b]=s.points[l.a]+anchor+direction*(l.original+extension)
    s._solve_link(l,dt)
    var positions: Array=[]
    for p in s.points:positions.append([p.x,p.y,p.z])
    results.append({'link':index,'weak':weak,'ratio':ratio,'peak_force':l.peak_force,'lambda':l.lambda,'length':l.length,'damage':l.damage,'plastic':l.plastic,'plastic_work':s.plastic_work,'points':positions})
 # The direct contact check measures conservation with no external floor/barrier.
 s.reset(0)
 var wheel=s.wheels.wheels[3]
 s.points[wheel.node]=s.points[13]+Vector3(.15,.05,.095)
 var before: Vector3=s.center_of_mass()
 s.wheels._body_contact(3,1,dt)
 var contact: Dictionary={'com_error_m':before.distance_to(s.center_of_mass()),'events':wheel.contact_events,'impulse':wheel.body_impulse}
 var args=OS.get_cmdline_user_args()
 FileAccess.open(args[args.find('--output')+1],FileAccess.WRITE).store_string(JSON.stringify({'force_fixtures':results,'contact':contact}))
 quit()
'''


def instrument_phases(s):
    s=s.replace('var compact: RefCounted','var phase_us: Dictionary={}\nfunc _phase(name: String,start: int) -> void:\n phase_us[name]=phase_us.get(name,0)+Time.get_ticks_usec()-start\n\nvar compact: RefCounted')
    s=s.replace(' wheels.predict(dt)',' var phase_start: int=Time.get_ticks_usec()\n wheels.predict(dt)',1)
    s=s.replace(' for iteration in int(config.iterations):',' _phase("predict",phase_start)\n for iteration in int(config.iterations):\n  phase_start=Time.get_ticks_usec()',1)
    s=s.replace('  wheels.constrain_lateral_mounts(dt)','  _phase("links",phase_start)\n  phase_start=Time.get_ticks_usec()\n  wheels.constrain_lateral_mounts(dt)',1)
    s=s.replace('  _contacts()','  _phase("mounts",phase_start)\n  phase_start=Time.get_ticks_usec()\n  _contacts()',1)
    s=s.replace('  wheels.contacts(dt)','  _phase("body_world_contacts",phase_start)\n  phase_start=Time.get_ticks_usec()\n  wheels.contacts(dt)',1)
    s=s.replace('  if bool(config.enforce_symmetry)','  _phase("wheel_contacts",phase_start)\n  phase_start=Time.get_ticks_usec()\n  if bool(config.enforce_symmetry)',1)
    s=s.replace('   _symmetry()','   _symmetry()\n  _phase("symmetry",phase_start)\n phase_start=Time.get_ticks_usec()',1)
    s=s.replace(' wheels.finish_step(dt)',' _phase("linear_velocity",phase_start)\n phase_start=Time.get_ticks_usec()\n wheels.finish_step(dt)\n _phase("wheel_finish",phase_start)\n phase_start=Time.get_ticks_usec()',1)
    s=s.replace(' _break_links(dt)',' _phase("damping",phase_start)\n phase_start=Time.get_ticks_usec()\n _break_links(dt)',1)
    s=s.replace(' step_count+=1',' _phase("diagnostics_break",phase_start)\n step_count+=1',1)
    return s


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compare(reference, candidate):
    assert reference['test'] == candidate['test']
    node_max = rest_max = work_max = 0.0
    failures_equal = True
    for a, b in zip(reference['frames'], candidate['frames']):
        node_max = max(node_max, *(math.dist(x, y) for x, y in zip(a['points'], b['points'])))
        rest_max = max(rest_max, *(abs(x-y) for x, y in zip(a['lengths'], b['lengths'])))
        work_max = max(work_max, abs(a['plastic_work']-b['plastic_work']))
        failures_equal &= a['broken'] == b['broken'] and a['detached'] == b['detached']
    am, bm = reference['metrics'], candidate['metrics']
    return {
        'max_sampled_node_deviation_m': node_max,
        'max_sampled_plastic_length_deviation_m': rest_max,
        'max_sampled_plastic_work_deviation_j': work_max,
        'sampled_failure_states_equal': failures_equal,
        'front_shortening_difference_m': bm['front_shortening_m']-am['front_shortening_m'],
        'cabin_shortening_difference_m': bm['cabin_shortening_m']-am['cabin_shortening_m'],
        'yielded_links_equal': am['yielded_links'] == bm['yielded_links'],
        'wheel_metrics_equal': am['wheels'] == bm['wheels'],
        'finite': candidate['finite'],
        'minimum_floor_clearance_m': candidate['minimum_floor_m'],
        'minimum_barrier_clearance_m': candidate['minimum_barrier_m'],
        'no_energy_explosion': bm['maximum_kinetic_kj'] <= bm['initial_energy_kj']*1.06+1,
        'baseline_mean_step_us': am['mean_step_us'],
        'candidate_mean_step_us': bm['mean_step_us'],
        'speedup': am['mean_step_us']/bm['mean_step_us'],
        'candidate_metrics': bm,
    }


def run(binary, project, output, profile=False, candidate_sweeps=8):
    command = [binary, '--headless', '--path', str(project), '--script', 'res://benchmark.gd', '--']
    if profile:
        command.append('--profile')
    if candidate_sweeps != 8:
        command += ['--candidate-sweeps', str(candidate_sweeps)]
    command += ['--output', str(output)]
    print('+', ' '.join(command), flush=True)
    with output.with_suffix('.log').open('w') as log:
        subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT)
    return json.loads(output.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='/Applications/Godot.app/Contents/MacOS/Godot')
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--candidate-sweeps', type=int, default=8, help='Exploratory candidate sweep count; baseline stays at eight')
    parser.add_argument('--profile', action='store_true', help='Run separately instrumented baseline phases after timing')
    parser.add_argument('--scratch', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT/'verification/full_solver_performance.json')
    args = parser.parse_args()
    assert args.repeats > 0
    scratch = args.scratch.expanduser().resolve() if args.scratch else Path(tempfile.mkdtemp(prefix='car-full-solver-'))
    args.output = args.output.expanduser().resolve()
    assert scratch != ROOT and ROOT not in scratch.parents, 'Use a scratch directory outside the repository'
    assert args.candidate_sweeps > 0
    scratch.mkdir(parents=True, exist_ok=True)
    config = json.loads((ROOT/'structure.json').read_text())
    assert abs(config['fixed_step_s']-1/480) < 1e-10 and config['iterations'] == 8
    assert config['hardening'] >= 0, 'Candidate yield bound requires nonnegative hardening'
    sources = ['scripts/structure_solver.gd', 'scripts/wheel_physics.gd', 'structure.json']
    source_data = {name: (ROOT/name).read_bytes() for name in sources}
    hashes = {name: hashlib.sha256(data).hexdigest() for name,data in source_data.items()}
    for variant in ['baseline', 'candidate']:
        project = scratch/variant
        (project/'scripts').mkdir(parents=True, exist_ok=True)
        (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Isolated full solver benchmark"\n')
        for name in sources:
            (project/name).write_bytes(source_data[name])
        (project/'benchmark.gd').write_text(SINGLE_BENCHMARK_GD)
        (project/'fixtures.gd').write_text(FIXTURES_GD)
    patch = ROOT/'tools/performance_candidates/full_solver.patch'
    subprocess.run(['git', 'apply', '--check', str(patch)], cwd=scratch/'candidate', check=True)
    subprocess.run(['git', 'apply', str(patch)], cwd=scratch/'candidate', check=True)
    paired = scratch/'paired'
    shutil.copytree(scratch/'baseline', paired, dirs_exist_ok=True)
    shutil.copy2(scratch/'candidate/scripts/structure_solver.gd', paired/'scripts/candidate_solver.gd')
    (paired/'benchmark.gd').write_text(BENCHMARK_GD)
    fixture_results = {}
    for variant in ['baseline', 'candidate']:
        output = scratch/f'{variant}_fixtures.json'
        subprocess.run([args.godot, '--headless', '--path', str(scratch/variant),
                        '--script', 'res://fixtures.gd', '--', '--output', str(output)], check=True)
        fixture_results[variant] = json.loads(output.read_text())
    all_runs = []
    for repeat in range(args.repeats):
        runs = run(args.godot, paired, scratch/f'paired_{repeat}.json', candidate_sweeps=args.candidate_sweeps)
        comparisons = [dict(test=a['test'], **compare(a,b)) for a,b in zip(runs['baseline'],runs['candidate'])]
        all_runs.append(comparisons)
        print('Repeat', repeat+1, 'speedups:', [round(x['speedup'],3) for x in comparisons], flush=True)
    phase_profile = None
    if args.profile:
        project = scratch/'profile'
        shutil.copytree(scratch/'baseline', project, dirs_exist_ok=True)
        source = project/'scripts/structure_solver.gd'
        source.write_text(instrument_phases(source.read_text()))
        phase_profile = run(args.godot, project, scratch/'phase_profile.json', profile=True)
    cases=[]
    for index in range(len(all_runs[0])):
        comparisons = [run[index] for run in all_runs]
        entry = dict(comparisons[0])
        entry['median_speedup'] = statistics.median(x['speedup'] for x in comparisons)
        entry['all_speedups'] = [x['speedup'] for x in comparisons]
        entry['baseline_median_step_us'] = statistics.median(x['baseline_mean_step_us'] for x in comparisons)
        entry['candidate_median_step_us'] = statistics.median(x['candidate_mean_step_us'] for x in comparisons)
        entry['passed_accuracy'] = all(
            x['max_sampled_node_deviation_m'] == 0 and
            x['max_sampled_plastic_length_deviation_m'] == 0 and
            x['max_sampled_plastic_work_deviation_j'] == 0 and
            x['sampled_failure_states_equal'] and x['yielded_links_equal'] and
            x['wheel_metrics_equal'] and x['finite'] and x['no_energy_explosion'] and
            x['minimum_floor_clearance_m'] > -.005 and
            x['minimum_barrier_clearance_m'] > -.005 for x in comparisons)
        cases.append(entry)
    report = {'source_sha256': hashes,
              'candidate_sha256':digest(scratch/'candidate/scripts/structure_solver.gd'),
              'patch_sha256':digest(patch), 'hardware':platform.platform()+' '+platform.machine(),
              'godot': subprocess.check_output([args.godot,'--version'],text=True).strip(),
              'scratch': str(scratch), 'repeats': args.repeats, 'physics_hz':480, 'baseline_sweeps':8, 'candidate_sweeps':args.candidate_sweeps,
              'phase_profile': [{ 'test':x['test'], 'phases_us':x['phases']} for x in phase_profile] if phase_profile else None,
              'trace_interval_s':.05, 'timing_method':'Baseline and candidate alternate execution order each substep in one process.',
              'cases':cases, 'all_runs':all_runs,
              'force_and_contact_fixtures_equal': fixture_results['baseline'] == fixture_results['candidate'],
              'force_fixture_count': len(fixture_results['baseline']['force_fixtures']),
              'contact_fixture': fixture_results['candidate']['contact'],
              'passed_accuracy': all(x['passed_accuracy'] for x in cases) and fixture_results['baseline'] == fixture_results['candidate'],
              'median_speedup': statistics.median(x['median_speedup'] for x in cases)}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    archive = args.output.with_name(args.output.stem+'_traces.json.gz')
    with gzip.open(archive,'wt') as stream:
        json.dump({'paired_runs':[json.loads((scratch/f'paired_{i}.json').read_text()) for i in range(args.repeats)],
                   'force_fixtures':fixture_results['baseline']},stream,separators=(',',':'))
    print('Report:',args.output, '\nScratch:',scratch, '\nAccuracy:',report['passed_accuracy'],
          '\nMedian speedup:',round(report['median_speedup'],3))
    raise SystemExit(0 if report['passed_accuracy'] else 1)


if __name__ == '__main__':
    main()
