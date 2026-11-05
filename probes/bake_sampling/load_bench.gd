extends SceneTree
var retained: Array=[]
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var paths:=OS.get_cmdline_user_args();var disk:=0
 for path in paths:
  var f:=FileAccess.open(path,FileAccess.READ);disk+=f.get_length();f.close()
 var before: int=OS.get_static_memory_usage();var started:=Time.get_ticks_usec();var peak:=before
 for path in paths:
  var f:=FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_ZSTD)
  retained.append(f.get_var(false));peak=maxi(peak,OS.get_static_memory_usage());f.close()
 var after: int=OS.get_static_memory_usage()
 print('LOAD_BENCH ',JSON.stringify({'paths':paths,'disk_bytes':disk,'load_decode_ms':(Time.get_ticks_usec()-started)/1000.,'engine_static_heap_delta_bytes':after-before,'engine_static_heap_observed_peak_delta_bytes':peak-before,'heap_counter_available':after>0,'scope':'Fresh Godot process, filesystem caches uncontrolled/warm. Engine static allocations for held decoded data; not OS RSS, true allocation peak, renderer/model RAM, or network latency. Startup excluded.'}))
 quit()
