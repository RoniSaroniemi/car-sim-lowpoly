extends RefCounted
## Cosmetic, one-way hinge response; its equivalent inertia adds no chassis mass.
var id: String='seat'
var angle:=0.0
var angular_velocity:=0.0
var plastic_angle:=0.0
var plastic_work:=0.0
var parameters: Dictionary={}
func setup(settings: Dictionary) -> void:
 parameters=settings.duplicate(true);id=str(settings.get('id','seat'));reset()
func reset() -> void:angle=0;angular_velocity=0;plastic_angle=0;plastic_work=0
func step(dt: float,proper_deceleration: float) -> void:
 var torque: float=(float(parameters.get('back_mass_kg',10))+float(parameters.get('equivalent_load_kg',0)))*float(parameters.get('lever_arm_m',.30))*proper_deceleration
 var spring: float=parameters.get('spring_nm_per_rad',3500)
 var damping: float=parameters.get('damping_nms',90)
 var inertia: float=parameters.get('equivalent_inertia',5.5)
 var elastic: float=spring*(angle-plastic_angle)
 angular_velocity+=(torque-elastic-damping*angular_velocity)/inertia*dt
 var next: float=angle+angular_velocity*dt
 angle=clampf(next,deg_to_rad(parameters.get('minimum_angle_deg',-20)),deg_to_rad(parameters.get('maximum_angle_deg',55)))
 if angle!=next:angular_velocity=0
 var yield_torque: float=parameters.get('yield_torque_nm',450)
 var elastic_limit: float=yield_torque/spring
 if absf(angle-plastic_angle)>elastic_limit:
  var next_plastic: float=angle-signf(angle-plastic_angle)*elastic_limit
  plastic_work+=yield_torque*absf(next_plastic-plastic_angle);plastic_angle=next_plastic
func capture() -> Dictionary:return {'id':id,'angle':angle,'omega':angular_velocity,'plastic_angle':plastic_angle,'plastic_work':plastic_work}
func restore(a: Dictionary,b: Dictionary,alpha: float) -> void:
 angle=lerpf(a.get('angle',0),b.get('angle',0),alpha)
 angular_velocity=lerpf(a.get('omega',0),b.get('omega',0),alpha)
 plastic_angle=lerpf(a.get('plastic_angle',0),b.get('plastic_angle',0),alpha)
 plastic_work=lerpf(a.get('plastic_work',0),b.get('plastic_work',0),alpha)
