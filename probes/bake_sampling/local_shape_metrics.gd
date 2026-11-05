extends SceneTree
const Track=preload('res://probes/bake_sampling/packed_track.gd')
const Frame=preload('res://scripts/incremental_crash_player.gd')
const Clip=preload('res://scripts/baked_crash_clip.gd')
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var source: Dictionary=Clip.read('res://bakes/frontal_120.crashclip')
 var results: Array=[]
 for tag in ['120','30','15','adaptive']:
  var f:=FileAccess.open_compressed('res://verification/bake_sampling/packed_'+tag+'.track',FileAccess.READ,FileAccess.COMPRESSION_ZSTD);var player:=Track.new();player.setup(f.get_var(false));f.close()
  var maximum:=0.;var square:=0.;var count:=0;var translation:=0.;var rotation:=0.
  for index in 301:
   var actual: Dictionary=player.sample(float(index)/120);var expected: Dictionary=source.frames[index]
   var a: Transform3D=Frame.frame(actual.points);var b: Transform3D=Frame.frame(expected.points)
   translation=maxf(translation,a.origin.distance_to(b.origin));rotation=maxf(rotation,rad_to_deg(a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())))
   var inverse_a:=a.affine_inverse();var inverse_b:=b.affine_inverse()
   for i in 34:
    var d: float=(inverse_a*actual.points[i]).distance_to(inverse_b*expected.points[i]);maximum=maxf(maximum,d);square+=d*d;count+=1
  results.append({'label':tag,'local_body_max_error_m':maximum,'local_body_rms_error_m':sqrt(square/count),'removed_frame_translation_max_m':translation,'removed_frame_orientation_max_deg':rotation})
 FileAccess.open('res://verification/bake_sampling/local_shape_quality.json',FileAccess.WRITE).store_string(JSON.stringify({'scope':'Body nodes excluding wheels, each pose expressed in the production incremental-player lower-chassis frame. Separates pose/root approximation from local shape error.','runs':results},'\t'))
 print('LOCAL_SHAPE_METRICS ',JSON.stringify(results));quit()
