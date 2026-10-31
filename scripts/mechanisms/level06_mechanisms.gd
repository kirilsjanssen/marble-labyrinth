class_name Level06Mechanisms
extends ClockworkMechanisms
## Minimal, reliable gameplay layer for the Level 06 test. The committed GLB
## supplies the art; these bodies provide two usable magnetic lifts. Barriers
## remain visual-only so an unfinished animation cannot make the test route
## impossible on a phone.

const PLATFORM_SIZE := Vector3(2.15, 0.24, 2.15)

var visuals: Level06Visuals
var lifts: Dictionary = {}
var barriers_open := false


func setup_level06(level_config: Dictionary, materials: Dictionary, player_marble: RigidBody3D, scene_visuals: Level06Visuals) -> void:
	config = level_config
	palette = materials
	marble = player_marble
	visuals = scene_visuals
	for lift_spec: Dictionary in config.get("lifts", []):
		_build_magnetic_lift(lift_spec)
	reset_state()


func physics_step(delta: float) -> void:
	motion_time += delta
	for lift_name: String in lifts:
		_step_lift(lift_name, delta)
	barriers_open = fmod(motion_time, 6.0) > 2.0
	if visuals:
		visuals.set_barrier_open("G01", barriers_open)
		visuals.set_barrier_open("G02", barriers_open)


func reset_state() -> void:
	motion_time = 0.0
	barriers_open = false
	for lift_name: String in lifts:
		var lift: Dictionary = lifts[lift_name]
		var body := lift["body"] as AnimatableBody3D
		body.sync_to_physics = false
		body.position.y = float(lift["lower"])
		body.reset_physics_interpolation()
		body.sync_to_physics = true
		lift["target"] = float(lift["lower"])
		lift["dwell"] = 0.0
		lift["state"] = "lower"
		lifts[lift_name] = lift
		if visuals:
			visuals.set_lift_surface(lift_name, body.position.y)
	if visuals:
		visuals.set_barrier_open("G01", false)
		visuals.set_barrier_open("G02", false)


func request_lift(lift_name: String, go_up: bool) -> void:
	if not lifts.has(lift_name):
		return
	var lift: Dictionary = lifts[lift_name]
	lift["target"] = float(lift["upper"] if go_up else lift["lower"])
	lift["state"] = "moving_up" if go_up else "moving_down"
	lift["dwell"] = 0.0
	lifts[lift_name] = lift


func lift_surface(lift_name: String) -> float:
	if not lifts.has(lift_name):
		return -1000.0
	return float((lifts[lift_name]["body"] as AnimatableBody3D).position.y)


func _build_magnetic_lift(spec: Dictionary) -> void:
	var body := AnimatableBody3D.new()
	var lift_name := String(spec["name"])
	body.name = lift_name + "_PhysicsPlatform"
	body.sync_to_physics = true
	var base: Vector3 = spec["position"]
	body.position = Vector3(base.x, float(spec["lower"]), base.z)
	var collision := CollisionShape3D.new()
	collision.name = lift_name + "_Collision"
	collision.position.y = -PLATFORM_SIZE.y * 0.5
	var shape := BoxShape3D.new()
	shape.size = PLATFORM_SIZE
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	lifts[lift_name] = {
		"body": body,
		"lower": float(spec["lower"]),
		"upper": float(spec["upper"]),
		"speed": float(spec.get("speed", 1.8)),
		"target": float(spec["lower"]),
		"dwell": 0.0,
		"state": "lower",
	}


func _step_lift(lift_name: String, delta: float) -> void:
	var lift: Dictionary = lifts[lift_name]
	var body := lift["body"] as AnimatableBody3D
	var target := float(lift["target"])
	var lower := float(lift["lower"])
	var upper := float(lift["upper"])
	var ball_local := to_local(marble.global_position)
	var planar_distance := Vector2(ball_local.x - body.position.x, ball_local.z - body.position.z).length()
	var near_platform := planar_distance < 1.45 and absf(ball_local.y - (body.position.y + 0.38)) < 1.05
	if absf(body.position.y - target) > 0.01:
		body.position.y = move_toward(body.position.y, target, float(lift["speed"]) * delta)
		lift["dwell"] = 0.0
	else:
		body.position.y = target
		lift["dwell"] = float(lift["dwell"]) + delta
		if is_equal_approx(target, lower) and near_platform and float(lift["dwell"]) > 0.45:
			lift["target"] = upper
			lift["state"] = "moving_up"
			lift["dwell"] = 0.0
			state_changed.emit("%s MAGNETIC LIFT — ascending" % lift_name)
		elif is_equal_approx(target, upper) and not near_platform and float(lift["dwell"]) > 1.5:
			lift["target"] = lower
			lift["state"] = "moving_down"
			lift["dwell"] = 0.0
	lifts[lift_name] = lift
	if visuals:
		visuals.set_lift_surface(lift_name, body.position.y)
