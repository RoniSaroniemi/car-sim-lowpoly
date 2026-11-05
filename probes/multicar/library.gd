extends RefCounted
## Pure cache: remove the authored rigid world trajectory, retain recorded shape.
const Clip=preload('res://scripts/baked_crash_clip.gd')
static var clips: Dictionary={}
static var tracks: Dictionary={}
static func get_clip(id: String,g: RefCounted) -> Dictionary:
 if clips.has(id):return clips[id]
 var path: String='res://bakes/'+id+'.crashclip'
 if id=='opposed_front_rear_60':path='res://probes/multicar/data/'+id+'.crashclip'
 var data: Dictionary=Clip.read(path)
 if data.is_empty() or not Clip.input_compatibility(data).compatible:return {}
 Clip.prepare_surfaces(g,data)
 clips[id]=data
 var samples: Array=[]
 for frame in data.frames:
  var center:=Vector3.ZERO;var total:=0.0
  for i in g.points.size():center+=frame.points[i]*g.masses[i];total+=g.masses[i]
  center/=total
  var x: Vector3=(frame.points[12]+frame.points[13]-frame.points[4]-frame.points[5]).normalized()
  var z: Vector3=frame.points[5]-frame.points[4];z=(z-x*x.dot(z)).normalized()
  var y: Vector3=z.cross(x).normalized()
  var basis:=Basis(x,y,x.cross(y).normalized()).orthonormalized()
  var points:=PackedVector3Array()
  for p in frame.points:points.append(basis.transposed()*(p-center))
  var wheel_rotations: Array=[]
  for wheel in frame.wheels:wheel_rotations.append((basis.get_rotation_quaternion().inverse()*wheel.rotation).normalized())
  samples.append({'points':points,'rotations':wheel_rotations,'removed_root':center,'removed_basis':basis})
 tracks[id]=samples
 return data
static func frame(id: String,time: float) -> Dictionary:
 var data: Dictionary=clips[id]
 var samples: Array=tracks[id]
 var n: float=clampf(time*float(data.metadata.sample_hz),0,samples.size()-1)
 var index:=floori(n);var next:=mini(index+1,samples.size()-1);var t:=n-index
 var p:=PackedVector3Array();var rotations: Array=[]
 for i in samples[index].points.size():p.append(samples[index].points[i].lerp(samples[next].points[i],t))
 for i in samples[index].rotations.size():rotations.append(samples[index].rotations[i].slerp(samples[next].rotations[i],t))
 return {'points':p,'rotations':rotations,'a':data.frames[index],'b':data.frames[next],'alpha':t,'surface':data._surface_track[index]}
