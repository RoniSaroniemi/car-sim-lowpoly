extends SceneTree
const Fixture=preload('res://probes/panels/headon_fixtures.gd')
func _initialize() -> void:
 var results: Array=[]
 for name_ in ['headon_60','headon_120']:
  var f:=Fixture.new();f.start(name_)
  while not f.complete:f.step()
  var metrics: Dictionary=f.metrics();results.append(metrics)
  var file:=FileAccess.open_compressed('res://probes/panels/data/'+name_+'.panelclip',FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD);file.store_var({'version':2,'hz':120,'metrics':metrics,'frames':f.frames},true);file.close()
  print('HEADON_RESULT ',JSON.stringify(metrics))
 FileAccess.open('res://probes/panels/evidence/headon_results.json',FileAccess.WRITE).store_string(JSON.stringify(results,'  '))
 quit()
