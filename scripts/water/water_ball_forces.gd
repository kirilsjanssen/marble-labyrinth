extends Node
class_name WaterBallForces
## Applies buoyancy, relative-velocity drag and current to existing PhysicsBall.

@export_range(0.0, 20.0, 0.01) var drag_coefficient := 3.2
@export_range(0.0, 20.0, 0.01) var current_coupling := 2.0
var volumes: Array[WaterVolume] = []


func register_volume(volume: WaterVolume) -> void:
	if not volumes.has(volume):
		volumes.append(volume)


func _physics_process(_delta: float) -> void:
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	for volume in volumes:
		if not is_instance_valid(volume):
			continue
		for candidate in volume.get_overlapping_bodies():
			if candidate is PhysicsBall:
				_apply_water_forces(candidate as PhysicsBall, volume, gravity)


func _apply_water_forces(ball: PhysicsBall, volume: WaterVolume, gravity: float) -> void:
	var fraction := volume.submerged_fraction(ball)
	if fraction <= 0.0 or not ball.material_profile:
		return
	ball.sleeping = false
	# Consistent density rule: profile density determines buoyant acceleration;
	# effective displaced volume is mass / density. Geometry only determines the
	# smooth submerged fraction, avoiding P1 radius/mass scale inconsistency.
	var density_ratio := volume.water_density / maxf(ball.material_profile.density, 1.0)
	var buoyancy := Vector3.UP * ball.mass * gravity * density_ratio * fraction
	var relative_velocity := ball.linear_velocity - volume.flow_velocity
	var drag := -relative_velocity * ball.mass * drag_coefficient * volume.viscosity * fraction
	var current_force := volume.flow_velocity * ball.mass * current_coupling * fraction
	ball.apply_central_force(buoyancy + drag + current_force)
