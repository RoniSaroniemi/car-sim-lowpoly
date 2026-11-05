extends SceneTree
## Machine-readable job inventory from the authoritative case definitions.
const Clip=preload('res://scripts/baked_crash_clip.gd')
const Partial=preload('res://scripts/partial_crash_library.gd')
const Multiaxis=preload('res://scripts/multiaxis_crash_cases.gd')
func _initialize() -> void:
 var jobs: Array=[]
 for spec in Clip.specifications():
  var id: String=Clip.case_id(spec.angle,spec.speed)
  jobs.append({'id':id,'family':'horizontal','script':'bake_frontal_clip.gd','args':['--only='+id,'--quality=4','--no-index'],'metadata':'bakes/'+id+'.json'})
 for spec in Partial.specifications():
  var id: String=Partial.case_id(spec.angle,spec.speed,spec.side,spec.overlap)
  jobs.append({'id':id,'family':'partial','script':'bake_partial_crashes.gd','args':['--only='+id,'--quality=4','--no-index'],'metadata':'bakes/partial/'+id+'.json'})
 for fixture in ['roof_flat','roof_corner']:
  jobs.append({'id':fixture+'_35','family':'roof','script':'bake_roof_clips.gd','args':['--case='+fixture,'--speed=35','--quality=4'],'metadata':'bakes/roof/'+fixture+'_35.json'})
 jobs.append({'id':'conditioned_sequence','family':'conditioned','script':'bake_conditioned_transitions.gd','args':[],'metadata':''})
 for spec in Multiaxis.specifications():
  jobs.append({'id':spec.id,'family':'multiaxis','script':'bake_multiaxis_clips.gd','args':['--only='+spec.id,'--quality=4','--no-index'],'metadata':'bakes/multiaxis/'+spec.id+'.json'})
 print('BAKE_JOBS_JSON='+JSON.stringify(jobs))
 quit()
