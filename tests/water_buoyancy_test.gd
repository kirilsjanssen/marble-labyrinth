extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var network := WaterNetwork.new()
	root.add_child(network)
	network.add_reservoir(&"POOL", 10.0, 9.0, 5.0)
	var volume := WaterVolume.new()
	volume.position = Vector3.ZERO
	volume.setup(network, &"POOL", Vector3(8.0, 2.0, 8.0))
	root.add_child(volume)
	var forces := WaterBallForces.new()
	root.add_child(forces)
	forces.register_volume(volume)
	_add_floor(Vector3(0.0, -1.12, 0.0), Vector3(8.0, 0.2, 8.0))
	var wood := _spawn_ball("Wood", Vector3(-1.0, 0.2, 0.0), &"wood")
	var hollow := _spawn_ball("Hollow", Vector3(1.0, 0.2, 0.0), &"hollow")
	var steel := _spawn_ball("Steel", Vector3(0.0, 0.2, 1.5), &"magnetic_steel")
	await physics_frame
	await _wait_frames(240)
	if not _require(wood.global_position.y > -0.1 and hollow.global_position.y > 0.2, "wood and hollow balls must float using real forces"):
		return
	if not _require(steel.global_position.y < -0.45, "dense steel must sink to the physical floor"):
		return

	var wet := _spawn_ball("WetDrag", Vector3(-2.0, 0.0, -2.0), &"glass")
	wet.gravity_scale = 0.0
	wet.linear_velocity = Vector3(4.0, 0.0, 0.0)
	var air := _spawn_ball("AirControl", Vector3(-2.0, 4.0, -2.0), &"glass")
	air.gravity_scale = 0.0
	air.linear_velocity = Vector3(4.0, 0.0, 0.0)
	await _wait_frames(45)
	if not _require(wet.linear_velocity.length() < air.linear_velocity.length() * 0.65, "water drag must slow a rigid ball relative to air"):
		return

	var carried := _spawn_ball("CurrentBall", Vector3(-1.5, 0.2, -1.5), &"hollow")
	carried.gravity_scale = 0.0
	volume.flow_velocity = Vector3(1.6, 0.0, 0.0)
	var current_start := carried.global_position.x
	await _wait_frames(90)
	if not _require(carried.global_position.x > current_start + 0.35, "water current must physically carry a ball"):
		return

	print("WATER BUOYANCY PASS: real floating/sinking, relative drag and current force")
	quit(0)


func _spawn_ball(ball_name: String, at: Vector3, material_id: StringName) -> PhysicsBall:
	var ball := PhysicsBall.new()
	ball.name = ball_name
	ball.position = at
	ball.material_id = material_id
	root.add_child(ball)
	return ball


func _add_floor(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("WATER BUOYANCY FAIL: " + message)
	quit(1)
	return false
