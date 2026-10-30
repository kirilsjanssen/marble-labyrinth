extends Area3D
class_name GoalSocketDetector
## Broad Area3D detects proximity; only a centred, steady rigid body completes a goal.
## The trigger sphere's overlap alone must NEVER win a level.

signal body_captured(body: RigidBody3D)

@export_range(0.1, 0.5, 0.01) var capture_radius := 0.23
@export_range(0.15, 0.8, 0.01) var vertical_tolerance := 0.36
@export_range(0.05, 1.0, 0.01) var hold_seconds := 0.25
@export_range(0.1, 10.0, 0.1) var max_speed := 1.5

var target_body: RigidBody3D
var stable_seconds := 0.0
var capture_complete := false


func _ready() -> void:
	monitoring = true


func _physics_process(delta: float) -> void:
	if capture_complete or not is_instance_valid(target_body):
		return
	var detected := false
	for candidate in get_overlapping_bodies():
		if candidate == target_body:
			detected = true
			break
	if detected and is_body_centered(target_body) and target_body.linear_velocity.length() <= max_speed:
		stable_seconds += delta
		if stable_seconds >= hold_seconds:
			capture_complete = true
			body_captured.emit(target_body)
	else:
		stable_seconds = 0.0


func is_body_centered(body: RigidBody3D) -> bool:
	if not is_instance_valid(body):
		return false
	var local_position := to_local(body.global_position)
	var distance_flat := Vector2(local_position.x, local_position.z).length()
	return distance_flat <= capture_radius and absf(local_position.y) <= vertical_tolerance


func reset_capture() -> void:
	capture_complete = false
	stable_seconds = 0.0
