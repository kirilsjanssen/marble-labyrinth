extends Area3D
class_name FieldZone
## Modular force zone. It never moves a rigid body by changing its transform.

enum FieldType { WIND, MAGNETIC, LOCAL_GRAVITY, ADHESION }

@export var field_type := FieldType.WIND
@export var direction := Vector3.RIGHT
@export var strength := 8.0
@export var max_force := 20.0
@export_range(-1.0, 1.0, 0.1) var polarity := 1.0
@export var enabled := true


func _ready() -> void:
	monitoring = true


func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	for candidate in get_overlapping_bodies():
		if candidate is PhysicsBall:
			_apply_to_ball(candidate as PhysicsBall)


func _apply_to_ball(ball: PhysicsBall) -> void:
	match field_type:
		FieldType.WIND:
			var airflow := (global_basis * direction).normalized()
			ball.apply_central_force(airflow * minf(absf(strength), max_force))
		FieldType.MAGNETIC:
			var response := ball.magnetic_response()
			if absf(response) < 0.001:
				return
			var offset := global_position - ball.global_position
			var distance_squared := maxf(offset.length_squared(), 0.16)
			var magnitude := minf(absf(strength) * absf(response) / distance_squared, max_force)
			ball.apply_central_force(offset.normalized() * magnitude * signf(response * polarity))
		FieldType.LOCAL_GRAVITY:
			var desired_acceleration := (global_basis * direction).normalized() * strength
			var world_gravity := Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * ball.gravity_scale
			ball.apply_central_force((desired_acceleration - world_gravity) * ball.mass)
		FieldType.ADHESION:
			var response := ball.adhesion_response()
			if response <= 0.0:
				return
			var pull := global_position - ball.global_position
			if pull.length_squared() > 0.001:
				ball.apply_central_force(pull.normalized() * minf(strength * response, max_force))
