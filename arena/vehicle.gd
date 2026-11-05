extends 'res://scripts/driving_vehicle.gd'
## Shared vehicle, with an optional analytic arena provider and compatible wall.
const WorldContacts=preload('res://arena/world_contacts.gd')
var ring:=WorldContacts.new()
var boundary_contacts: int:
 get:return ring.contact_samples
func setup(profile_path: String='res://vehicles/niva.json',enable_driving: bool=true) -> void:
 super.setup(profile_path,enable_driving)
 solver.static_contact_provider=ring
 solver.barrier_min=WorldContacts.CRASH_MIN;solver.barrier_max=WorldContacts.CRASH_MAX
 solver.barrier_enabled=true
# Inherited _contact_event queries only the explicit planar crash barrier.
# Ring contacts remain rigid in baked mode and deform normally in live mode.
