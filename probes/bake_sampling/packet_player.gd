extends RefCounted
## Local disk-stream prototype: shared header + one independent0.5s packet.
const Track=preload('res://probes/bake_sampling/packed_track.gd')
var header: Dictionary={}
var data: Dictionary={}
var tag: String='adaptive'
var decoder: RefCounted
var block:=-1
var loads: Array=[]
func read(path: String) -> Dictionary:
 var f:=FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_ZSTD);var result: Dictionary=f.get_var(false);f.close();return result
func setup(name_: String='adaptive') -> void:
 tag=name_;header=read('res://verification/bake_sampling/header_'+tag+'.track');data=header
func sample(time: float) -> Dictionary:
 var required: int=clampi(floori(time/.5),0,4)
 if required!=block:
  var began:=Time.get_ticks_usec()
  var packet: Dictionary=read('res://verification/bake_sampling/packet_%s_%d.track'%[tag,required])
  data=header.duplicate(true);data.keyframes=packet.keyframes;data.keys=packet.keys
  data.event_frames=packet.event_frames;data.event_slots=packet.event_slots;data.event_values=packet.event_values
  for i in data.event_paths.size():Track.put_path(data.template,data.event_paths[i],packet.event_checkpoint[i])
  decoder=Track.new();decoder.setup(data);block=required
  loads.append({'block':block,'load_and_setup_ms':(Time.get_ticks_usec()-began)/1000.,'resident_key_count':data.keys.size()})
 return decoder.sample(time)
