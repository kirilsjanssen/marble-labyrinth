extends SceneTree
## Godot headless regression: cube and pyramid keep proper colliders and obey gravity.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/labs/shape_lab.tscn") as PackedScene
	if not _require(scene != null, "Shape Lab scene must load"):
		return
	var lab := scene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame

	if not _require(lab.cube is PuzzleShapeBody and lab.pyramid is PuzzleShapeBody,
		"Cube and pyramid must be reusable live rigid bodies"):
		return
	if not _require(lab.cube.get_node("CollisionShape3D").shape is BoxShape3D,
		"Cube must have actual BoxShape3D collision"):
		return
	if not _require(lab.pyramid.get_node("CollisionShape3D").shape is ConvexPolygonShape3D,
		"Pyramid must have real convex collision, not visual-only geometry"):
		return
	if not _require(lab.marble is PhysicsBall and lab.marble.get_node("CollisionShape3D").shape is SphereShape3D,
		"Existing P1 sphere must remain available"):
		return
	if not _require(not lab.cube.freeze and not lab.pyramid.freeze and not lab.marble.freeze,
		"All three objects must remain dynamic"):
		return
	if not _require(lab.cube.magnetic_response() > 0.5 and lab.pyramid.magnetic_response() == 0.0,
		"Shapes must share material-dependent magnetic response"):
		return
	if not _require(lab.pyramid.geometric_volume() < lab.cube.geometric_volume(),
		"Pyramid must have one third of bounding-box volume"):
		return

	var start_cube: Vector3 = lab.cube.global_position
	var start_pyramid: Vector3 = lab.pyramid.global_position
	await _wait_physics_frames(90)
	if not _require(lab.cube.global_position.y < start_cube.y - 1.0,
		"Real cube must fall under gravity"):
		return
	if not _require(lab.pyramid.global_position.y < start_pyramid.y - 1.0,
		"Real convex pyramid must fall under gravity"):
		return
	if not _require(lab.cube.global_position.y > -1.0 and lab.pyramid.global_position.y > -1.0,
		"Cube and pyramid must collide with floor instead of falling through"):
		return

	# Both shapes are still real rigid bodies, so the existing P1 magnet field
	# can act on magnetic steel while the non-magnetic wooden pyramid stays put.
	var magnet := FieldZone.new()
	magnet.field_type = FieldZone.FieldType.MAGNETIC
	magnet.strength = 42.0
	magnet.max_force = 20.0
	magnet.position = Vector3(0.0, 6.0, 0.0)
	var field_collision := CollisionShape3D.new()
	var field_shape := SphereShape3D.new()
	field_shape.radius = 5.0
	field_collision.shape = field_shape
	magnet.add_child(field_collision)
	lab.add_child(magnet)
	lab.cube.gravity_scale = 0.0
	lab.pyramid.gravity_scale = 0.0
	lab.cube.global_position = Vector3(-2.0, 6.0, 0.0)
	lab.pyramid.global_position = Vector3(2.0, 6.0, 0.0)
	lab.cube.linear_velocity = Vector3.ZERO
	lab.pyramid.linear_velocity = Vector3.ZERO
	lab.cube.angular_velocity = Vector3.ZERO
	lab.pyramid.angular_velocity = Vector3.ZERO
	lab.cube.sleeping = false
	lab.pyramid.sleeping = false
	await _wait_physics_frames(25)
	if not _require(lab.cube.linear_velocity.x > 0.08,
		"Magnetic cube must physically accelerate toward field"):
		return
	if not _require(absf(lab.pyramid.linear_velocity.x) < 0.08,
		"Non-magnetic wooden pyramid must ignore magnetic field"):
		return

	print("SHAPE LAB PASS: dynamic cube, convex pyramid and sphere have colliders, gravity and selective magnetism")
	quit(0)


func _wait_physics_frames(count: int) -> void:
	for _i in range(count):
		await physics_frame


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("SHAPE LAB FAIL: " + message)
	quit(1)
	return false
