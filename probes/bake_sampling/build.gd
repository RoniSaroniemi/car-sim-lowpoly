extends SceneTree
const Track=preload('res://probes/bake_sampling/packed_track.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
const OUT='res://verification/bake_sampling'
func _initialize() -> void:call_deferred('_run')
func save_file(value: Dictionary,path: String) -> void:
 var f:=FileAccess.open_compressed(path,FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD);f.store_var(value);f.close()
func _run() -> void:
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 var raw: Dictionary=Clip.read('res://bakes/frontal_120.crashclip')
 # Preserve wheel direction at low sample rates: unwrap the authored phase while
 # the original 120Hz spacing is fine enough to distinguish complete turns.
 var original_hash: int=hash(var_to_bytes(raw.frames))
 var source: Dictionary=raw.duplicate();source.frames=raw.frames.duplicate(true)
 for wheel in 4:
  var phase: float=source.frames[0].wheels[wheel].spin
  var previous: float=phase
  for f in source.frames:
   var wrapped: float=f.wheels[wheel].spin
   phase+=angle_difference(previous,wrapped);previous=wrapped;f.wheels[wheel].spin=phase
 var started:=Time.get_ticks_usec();var packed: Dictionary=Track.build(source)
 var report: Dictionary={'source_id':raw.metadata.id,'source_sha256':FileAccess.get_sha256('res://bakes/frontal_120.crashclip'),'codec_sha256':FileAccess.get_sha256('res://probes/bake_sampling/packed_track.gd'),'builder_sha256':FileAccess.get_sha256('res://probes/bake_sampling/build.gd'),'original_immutable':original_hash==hash(var_to_bytes(raw.frames)),'build_ms':(Time.get_ticks_usec()-started)/1000.0,'continuous_channels':packed.channels.size(),'width_floats':packed.width,'events':packed.event_frames.size(),'event_paths':packed.event_paths.size(),'variants':[],'scope':'One clip only. Packed Float32 continuous channels, unchanged template fields once, exact120Hz discrete changes; no production format changes.'}
 for hz in [120,30,15,0]:
  var tag: String=str(hz) if hz>0 else 'adaptive'
  var variant: Dictionary=Track.reduced(packed,hz) if hz>0 else Track.adaptive(packed)
  var path: String=OUT+'/packed_%s.track'%tag;save_file(variant,path)
  var reader:=Track.new();reader.setup(variant)
  var squares:=0.;var maximum:=0.;var panel_max:=0.;var count:=0;var metal_max:=0.;var wheel_max:=0.;var max_frame:=-1;var spin_max:=0.
  var wheel_angle_max:=0.;var discrete_exact:=true;var began:=Time.get_ticks_usec()
  for frame in raw.frames.size():
   var state: Dictionary=reader.sample(float(frame)/120)
   for i in state.points.size():
    var d: float=state.points[i].distance_to(source.frames[frame].points[i]);
    if d>maximum:maximum=d;max_frame=frame
    if i<34:metal_max=maxf(metal_max,d)
    else:wheel_max=maxf(wheel_max,d)
    squares+=d*d;count+=1
   for panel in state.panels.panels.size():
    for i in 10:panel_max=maxf(panel_max,state.panels.panels[panel].points[i].distance_to(source.frames[frame].panels.panels[panel].points[i]))
   for i in 4:
    spin_max=maxf(spin_max,absf(state.wheels[i].spin-source.frames[frame].wheels[i].spin))
    var q: Quaternion=source.frames[frame].wheels[i].rotation
    wheel_angle_max=maxf(wheel_angle_max,rad_to_deg(q.angle_to(state.wheels[i].rotation)))
   for path_ in variant.event_paths:
    if not Track.same(Track.at_path(state,path_),Track.at_path(source.frames[frame],path_)):discrete_exact=false
  report.variants.append({'hz':hz,'label':tag,'key_count':variant.keys.size(),'compressed_bytes':FileAccess.get_file_as_bytes(path).size(),'serialized_bytes':var_to_bytes(variant).size(),'body_max_error_m':maximum,'metal_node_max_error_m':metal_max,'wheel_center_max_error_m':wheel_max,'worst_frame':max_frame,'spin_max_error_deg':rad_to_deg(spin_max),'body_rms_error_m':sqrt(squares/count),'panel_max_error_m':panel_max,'wheel_orientation_max_error_deg':wheel_angle_max,'discrete_states_exact_at120hz':discrete_exact,'sample_and_metric_ms':(Time.get_ticks_usec()-began)/1000.})
  # Full dictionary snapshots decimated to the same keys: separate frequency
  # savings from layout savings. Events here have only the low-rate timestamps.
  var snapshots: Array=[]
  for index in variant.keyframes:snapshots.append(source.frames[index])
  save_file({'metadata':source.metadata,'keyframes':variant.keyframes,'frames':snapshots},OUT+'/snapshots_%s.track'%tag)
  # Independently decodable half-second packets with a boundary overlap and
  # an exact discrete-state checkpoint. Header/topology travels once.
  var header: Dictionary=variant.duplicate();header.erase('keys');header.erase('event_frames');header.erase('event_slots');header.erase('event_values');header.erase('keyframes')
  save_file(header,OUT+'/header_%s.track'%tag)
  var blocks: Array=[]
  var checkpoint:=Track.new();checkpoint.setup(variant)
  for block in 5:
   var first:=block*60;var last: int=(block+1)*60
   var indices: Array=[];var buffers: Array=[]
   var previous:=0;var next: int=variant.keyframes.size()-1
   for i in variant.keyframes.size():
    if variant.keyframes[i]<=first:previous=i
    if variant.keyframes[i]>=last:next=i;break
   for i in range(previous,next+1):indices.append(variant.keyframes[i]);buffers.append(variant.keys[i])
   var state: Dictionary=checkpoint.sample(float(first)/120)
   var event_checkpoint: Array=[]
   for path_ in variant.event_paths:event_checkpoint.append(Track.at_path(state,path_))
   var frames:=PackedInt32Array();var slots:=PackedInt32Array();var values: Array=[]
   for i in variant.event_frames.size():
    if variant.event_frames[i]>first and variant.event_frames[i]<=last:
     frames.append(variant.event_frames[i]);slots.append(variant.event_slots[i]);values.append(variant.event_values[i])
   var packet: Dictionary={'block':block,'first_frame':first,'last_frame':last,'keyframes':indices,'keys':buffers,'event_frames':frames,'event_slots':slots,'event_values':values,'event_checkpoint':event_checkpoint}
   var file: String=OUT+'/packet_%s_%d.track'%[tag,block];save_file(packet,file)
   blocks.append({'path':file,'bytes':FileAccess.get_file_as_bytes(file).size()})
  report.variants[-1]['stream_header_bytes']=FileAccess.get_file_as_bytes(OUT+'/header_%s.track'%tag).size();report.variants[-1]['stream_packets']=blocks
  var density: Array=[]
  for block in 5:
   var n:=0
   for key in variant.keyframes:
    if key>=block*60 and (key<(block+1)*60 or (block==4 and key==300)):n+=1
   density.append(n)
  report.variants[-1]['keys_per_halfsecond']=density
 var adaptive: Dictionary=report.variants[-1]
 report['checks']={'source_immutable':report.original_immutable,'reference_body_exact':report.variants[0].body_max_error_m==0,'all_discrete_states_exact':report.variants.all(func(v):return v.discrete_states_exact_at120hz),'adaptive_body_under11mm':adaptive.body_max_error_m<.011,'adaptive_panels_under16mm':adaptive.panel_max_error_m<.016,'adaptive_fewer_keys':adaptive.key_count<301,'adaptive_smaller_than_source':adaptive.compressed_bytes<FileAccess.get_file_as_bytes('res://bakes/frontal_120.crashclip').size()}
 report['passed']=report.checks.values().all(func(value):return value)
 FileAccess.open(OUT+'/quality.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
 print('SAMPLING_PROBE_BUILT ',JSON.stringify(report));quit(0 if report.passed else 1)
