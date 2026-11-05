extends SceneTree
const Fixture=preload('res://probes/panels/fixtures.gd')
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var cases: Array=Fixture.CASES
 if not OS.get_cmdline_user_args().is_empty():cases=Array(OS.get_cmdline_user_args())
 for name_ in cases:
  var fixture:=Fixture.new();fixture.start(name_)
  while not fixture.complete:fixture.step()
  print('PANEL_CASE ',JSON.stringify(fixture.metrics()))
 quit()
