extends SceneTree
const Track=preload('res://probes/bake_sampling/packed_track.gd')
const Stream=preload('res://probes/bake_sampling/packet_player.gd')
const OUT='res://verification/bake_sampling'
func read(path: String) -> Dictionary:
 var f:=FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_ZSTD);var value: Dictionary=f.get_var(false);f.close();return value
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var results: Array=[];var passed:=true
 for tag in ['120','30','15','adaptive']:
  var full:=Track.new();full.setup(read(OUT+'/packed_'+tag+'.track'))
  var max_error:=0.;var exact_events:=true
  for block in 5:
   var header: Dictionary=read(OUT+'/header_'+tag+'.track');var packet: Dictionary=read(OUT+'/packet_%s_%d.track'%[tag,block])
   header.keyframes=packet.keyframes;header.keys=packet.keys;header.event_frames=packet.event_frames;header.event_slots=packet.event_slots;header.event_values=packet.event_values
   for i in header.event_paths.size():Track.put_path(header.template,header.event_paths[i],packet.event_checkpoint[i])
   var partial:=Track.new();partial.setup(header)
   for frame in range(packet.first_frame,packet.last_frame+1):
    var expected: Dictionary=full.sample(float(frame)/120);var actual: Dictionary=partial.sample(float(frame)/120)
    for i in actual.points.size():max_error=maxf(max_error,expected.points[i].distance_to(actual.points[i]))
    for path in header.event_paths:exact_events=exact_events and Track.same(Track.at_path(expected,path),Track.at_path(actual,path))
  passed=passed and max_error<.000001 and exact_events
  results.append({'tag':tag,'body_difference_m':max_error,'discrete_exact':exact_events,'independent_blocks':5,'compared_samples':305})
 var stream:=Stream.new();stream.setup('adaptive');var reference:=Track.new();reference.setup(read(OUT+'/packed_adaptive.track'))
 var stream_error:=0.;var stream_events:=true
 for frame in 301:
  var expected: Dictionary=reference.sample(float(frame)/120);var actual: Dictionary=stream.sample(float(frame)/120)
  for i in actual.points.size():stream_error=maxf(stream_error,expected.points[i].distance_to(actual.points[i]))
  for path in reference.data.event_paths:stream_events=stream_events and Track.same(Track.at_path(expected,path),Track.at_path(actual,path))
 stream.sample(.1)
 passed=passed and stream_error<.000001 and stream_events and stream.loads.size()==6
 # Test seeking back and source-shared immutability, including exact event state.
 var data: Dictionary=read(OUT+'/packed_adaptive.track');var before: int=hash(var_to_bytes(data));var player:=Track.new();player.setup(data)
 player.sample(2);var rewound: Dictionary=player.sample(.02);var fresh:=Track.new();fresh.setup(data)
 var seek_exact: bool=hash(var_to_bytes(rewound))==hash(var_to_bytes(fresh.sample(.02)))
 passed=passed and seek_exact and before==hash(var_to_bytes(data))
 FileAccess.open(OUT+'/packet_validation.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':passed,'runs':results,'backward_seek_exact':seek_exact,'source_immutable':before==hash(var_to_bytes(data)),'streaming_body_error_m':stream_error,'streaming_events_exact':stream_events,'streaming_loads':stream.loads,'scope':'One source clip, half-second independent packet decoding vs same monolithic variant; includes boundary lookahead and exact120Hz event state. Not a network test.'},'\t'))
 print('SAMPLING_PACKETS_VERIFIED ',passed,' variants=',results.size());quit(0 if passed else 1)
