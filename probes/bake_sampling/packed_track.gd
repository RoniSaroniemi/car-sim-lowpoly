extends RefCounted
## Local experiment: packed continuous tracks + exact-time sparse state changes.
## Does not change the production format or claim a shipping codec.
var data: Dictionary={}
var discrete: Dictionary={}
var cursor:=0
var last_time:=-INF
static func count(v: Variant) -> int:
 match typeof(v):
  TYPE_FLOAT:return 1
  TYPE_VECTOR2:return 2
  TYPE_VECTOR3:return 3
  TYPE_QUATERNION,TYPE_COLOR:return 4
  TYPE_PACKED_FLOAT32_ARRAY,TYPE_PACKED_FLOAT64_ARRAY:return v.size()
  TYPE_PACKED_VECTOR3_ARRAY:return v.size()*3
 return -1
static func same(a: Variant,b: Variant) -> bool:return typeof(a)==typeof(b) and a==b
static func at_path(v: Variant,path: Array) -> Variant:
 for key in path:
  if v==null or (v is Dictionary and not v.has(key)):return null
  v=v[key]
 return v
static func put_path(v: Variant,path: Array,value: Variant) -> void:
 for i in path.size()-1:
  var key: Variant=path[i]
  if v is Dictionary and not v.has(key):v[key]={}
  v=v[key]
 if value==null and v is Dictionary:v.erase(path[-1])
 else:v[path[-1]]=value
static func numbers(v: Variant) -> PackedFloat32Array:
 var result:=PackedFloat32Array()
 match typeof(v):
  TYPE_FLOAT:result.append(v)
  TYPE_VECTOR2:result.append_array([v.x,v.y])
  TYPE_VECTOR3:result.append_array([v.x,v.y,v.z])
  TYPE_QUATERNION:result.append_array([v.x,v.y,v.z,v.w])
  TYPE_COLOR:result.append_array([v.r,v.g,v.b,v.a])
  TYPE_PACKED_FLOAT32_ARRAY,TYPE_PACKED_FLOAT64_ARRAY:result=PackedFloat32Array(v)
  TYPE_PACKED_VECTOR3_ARRAY:
   for point in v:result.append_array([point.x,point.y,point.z])
 return result
static func scan(values: Array,path: Array,result: Dictionary) -> void:
 var first: Variant=values[0]
 if values.all(func(v):return same(v,first)):return
 if values.all(func(v):return v is Dictionary):
  var keys: Dictionary={}
  for v in values:
   for key in v:keys[key]=true
  for key in keys:
   var p:=path.duplicate();p.append(key)
   scan(values.map(func(v):return v.get(key,null)),p,result)
  return
 if values.all(func(v):return v is Array and v.size()==first.size()):
  for i in first.size():
   var p:=path.duplicate();p.append(i)
   scan(values.map(func(v):return v[i]),p,result)
  return
 var size: int=count(first)
 if size>=0 and str(path[-1]) not in ['release_time','trigger_time','event_time','impact_time','deployment_time'] and values.all(func(v):return typeof(v)==typeof(first) and count(v)>=0):
  var maximum:=size;var sizes: Array=[];var previous:=size
  sizes.append({'frame':0,'size':size})
  for i in values.size():
   var n: int=count(values[i]);maximum=maxi(maximum,n)
   if n!=previous:sizes.append({'frame':i,'size':n});previous=n
  result.channels.append({'path':path,'type':typeof(first),'size':maximum,'sizes':sizes,'offset':result.width})
  result.width+=maximum
 else:
  var slot: int=result.event_paths.size();result.event_paths.append(path)
  var previous: Variant=first
  for i in range(1,values.size()):
   if same(values[i],previous):continue
   result.events.append({'frame':i,'slot':slot,'value':values[i]});previous=values[i]
static func build(source: Dictionary) -> Dictionary:
 var result: Dictionary={'version':1,'template':source.frames[0].duplicate(true),'metadata':source.metadata.duplicate(true),'channels':[],'event_paths':[],'events':[],'width':0,'sample_hz':120,'keyframes':[],'keys':[]}
 scan(source.frames,[],result)
 result.events.sort_custom(func(a,b):return a.frame<b.frame)
 result['event_frames']=PackedInt32Array();result['event_slots']=PackedInt32Array();result['event_values']=[]
 for event in result.events:
  result.event_frames.append(event.frame);result.event_slots.append(event.slot);result.event_values.append(event.value)
 result.erase('events')
 for index in source.frames.size():
  var buffer:=PackedFloat32Array();buffer.resize(result.width)
  for channel in result.channels:
   var packed:=numbers(at_path(source.frames[index],channel.path))
   for i in packed.size():buffer[channel.offset+i]=packed[i]
  result.keyframes.append(index);result.keys.append(buffer)
 return result
static func reduced(source: Dictionary,hz: int) -> Dictionary:
 var result: Dictionary=source.duplicate();result.keyframes=[];result.keys=[];result.sample_hz=hz
 var stride:=120/hz
 for i in range(0,source.keyframes.size(),stride):result.keyframes.append(i);result.keys.append(source.keys[i])
 if result.keyframes[-1]!=source.keyframes[-1]:result.keyframes.append(source.keyframes[-1]);result.keys.append(source.keys[-1])
 return result
static func adaptive(source: Dictionary) -> Dictionary:
 var chosen: Dictionary={0:true,300:true}
 for channel in source.channels:
  for change in channel.sizes:
   if change.frame>0:chosen[change.frame]=true;chosen[change.frame-1]=true
 var seeds: Array=chosen.keys();seeds.sort()
 for i in seeds.size()-1:_split(source,seeds[i],seeds[i+1],chosen)
 var result: Dictionary=source.duplicate();result.keyframes=chosen.keys();result.keyframes.sort();result.keys=[];result.sample_hz=0
 for i in result.keyframes:result.keys.append(source.keys[i])
 return result
static func _split(source: Dictionary,left: int,right: int,chosen: Dictionary) -> void:
 if right-left<2:return
 var worst:=1.0;var selected:=-1
 for index in range(left+1,right):
  var t: float=float(index-left)/(right-left)
  var a: PackedFloat32Array=source.keys[left];var b: PackedFloat32Array=source.keys[right];var actual: PackedFloat32Array=source.keys[index]
  for channel in source.channels:
   var field: String=str(channel.path[-1]);var offset: int=channel.offset;var size: int=channel.size
   if int(channel.type)==TYPE_PACKED_VECTOR3_ARRAY and field in ['points','nodes']:
    var tolerance:=.015 if 'panels' in channel.path or 'effects' in channel.path else .01
    for j in range(0,size,3):
     var delta:=Vector3(lerpf(a[offset+j],b[offset+j],t)-actual[offset+j],lerpf(a[offset+j+1],b[offset+j+1],t)-actual[offset+j+1],lerpf(a[offset+j+2],b[offset+j+2],t)-actual[offset+j+2])
     var ratio: float=delta.length()/tolerance
     if ratio>worst:worst=ratio;selected=index
   elif int(channel.type)==TYPE_QUATERNION:
    var qa:=Quaternion(a[offset],a[offset+1],a[offset+2],a[offset+3]).normalized();var qb:=Quaternion(b[offset],b[offset+1],b[offset+2],b[offset+3]).normalized();var q:=Quaternion(actual[offset],actual[offset+1],actual[offset+2],actual[offset+3]).normalized()
    var ratio: float=qa.slerp(qb,t).angle_to(q)/deg_to_rad(2)
    if ratio>worst:worst=ratio;selected=index
   elif field=='spin':
    var ratio: float=absf(lerpf(a[offset],b[offset],t)-actual[offset])/deg_to_rad(2)
    if ratio>worst:worst=ratio;selected=index
 if selected>=0:chosen[selected]=true;_split(source,left,selected,chosen);_split(source,selected,right,chosen)
func setup(value: Dictionary) -> void:
 data=value;discrete=data.template.duplicate(true);cursor=0;last_time=-INF
func sample(time: float) -> Dictionary:
 if time<last_time:discrete=data.template.duplicate(true);cursor=0
 var frame: float=clampf(time*120,0,300)
 while cursor<data.event_frames.size() and float(data.event_frames[cursor])<=frame+.00001:
  put_path(discrete,data.event_paths[data.event_slots[cursor]],data.event_values[cursor]);cursor+=1
 last_time=time
 var state: Dictionary=discrete.duplicate(true)
 var lower:=0;var upper: int=data.keyframes.size()-1
 while upper-lower>1:
  var middle: int=(lower+upper)/2
  if data.keyframes[middle]<=frame:lower=middle
  else:upper=middle
 var a: PackedFloat32Array=data.keys[lower];var b: PackedFloat32Array=data.keys[upper]
 var t: float=clampf((frame-float(data.keyframes[lower]))/maxf(1,float(data.keyframes[upper]-data.keyframes[lower])),0,1)
 for channel in data.channels:
  var offset: int=channel.offset;var size: int=channel.size;var output: Variant
  for change in channel.sizes:
   if change.frame<=frame+.00001:size=change.size
   else:break
  match int(channel.type):
   TYPE_FLOAT:output=lerpf(a[offset],b[offset],t)
   TYPE_VECTOR2:output=Vector2(lerpf(a[offset],b[offset],t),lerpf(a[offset+1],b[offset+1],t))
   TYPE_VECTOR3:output=Vector3(lerpf(a[offset],b[offset],t),lerpf(a[offset+1],b[offset+1],t),lerpf(a[offset+2],b[offset+2],t))
   TYPE_QUATERNION:
    var qa:=Quaternion(a[offset],a[offset+1],a[offset+2],a[offset+3]).normalized()
    var qb:=Quaternion(b[offset],b[offset+1],b[offset+2],b[offset+3]).normalized()
    output=qa.slerp(qb,t)
   TYPE_COLOR:output=Color(lerpf(a[offset],b[offset],t),lerpf(a[offset+1],b[offset+1],t),lerpf(a[offset+2],b[offset+2],t),lerpf(a[offset+3],b[offset+3],t))
   TYPE_PACKED_VECTOR3_ARRAY:
    var points:=PackedVector3Array();points.resize(size/3)
    for i in points.size():points[i]=Vector3(lerpf(a[offset+i*3],b[offset+i*3],t),lerpf(a[offset+i*3+1],b[offset+i*3+1],t),lerpf(a[offset+i*3+2],b[offset+i*3+2],t))
    output=points
   _:
    var packed:=PackedFloat32Array();packed.resize(size)
    for i in size:packed[i]=lerpf(a[offset+i],b[offset+i],t)
    output=PackedFloat64Array(packed) if int(channel.type)==TYPE_PACKED_FLOAT64_ARRAY else packed
  put_path(state,channel.path,output)
 return state
