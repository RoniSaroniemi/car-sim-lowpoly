extends SceneTree
const Fixture=preload('res://probes/panels/fixtures.gd')
func _initialize() -> void:call_deferred('_run')
func _run() -> void:
 var fixture:=Fixture.new();fixture.start('open_severe')
 while not fixture.complete:fixture.step()
 var report: Dictionary={'case':fixture.metrics(),'first_full_release_step_us':fixture.graph.release_step_us,'scope':'Whole shared body+activepanel480Hz calls; release bookkeeping is separately timed. No new render resources are created at detachment; GPU timing unavailable in native_budget.json.'}
 FileAccess.open('res://probes/panels/evidence/release_budget.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
 print('PANEL_RELEASE_BUDGET ',JSON.stringify(report));quit(0 if fixture.metrics().detached else 1)
