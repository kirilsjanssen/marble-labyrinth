extends SceneTree
## P1 integration checks: real rigid bodies, material pairs and modular force zones.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _require(PhysicsMaterialCatalog.BALL_IDS.size() == 7, "seven reusable ball profiles are required"):
		return
	if not _require(PhysicsMaterialCatalog.SURFACE_IDS.size() == 9, "nine surface profiles are required"):
		return
	var packed := load("res://scenes/labs/physics_lab.tscn") as PackedScene
	if not _require(packed != null, "Physics Lab scene must load"):
		return
	var lab := packed.instantiate() as PhysicsLab
	root.add_child(lab)
	await process_frame
	await physics_frame

	var balls := lab.test_balls
	for ball_name in balls:
		if not _require(balls[ball_name] is PhysicsBall and not balls[ball_name].freeze, "%s must be a live PhysicsBall/RigidBody3D" % ball_name):
			return

	var initial_z := -5.2
	var rubber_peak := 0.0
	var stone_peak := 0.0
	var rubber_impacted := false
	var stone_impacted := false
	for _frame in range(240):
		await physics_frame
		var rubber: PhysicsBall = balls.RubberDrop
		var stone: PhysicsBall = balls.StoneDrop
		if rubber.global_position.y < 0.7:
			rubber_impacted = true
		if stone.global_position.y < 0.7:
			stone_impacted = true
		if rubber_impacted:
			rubber_peak = maxf(rubber_peak, rubber.global_position.y)
		if stone_impacted:
			stone_peak = maxf(stone_peak, stone.global_position.y)

	var ice: PhysicsBall = balls.IceBall
	var wood: PhysicsBall = balls.WoodBall
	var sticky: PhysicsBall = balls.StickyBall
	var ice_distance := ice.global_position.z - initial_z
	var wood_distance := wood.global_position.z - initial_z
	var sticky_distance := sticky.global_position.z - initial_z
	if not _require(ice_distance > wood_distance + 0.25 and wood_distance > sticky_distance + 0.25, "ice, wood and sticky lanes must produce distinct stopping distances"):
		return
	if not _require(ice.angular_velocity.length() > 0.15, "the marble must physically rotate while rolling"):
		return
	if not _require(rubber_peak > stone_peak + 0.35, "rubber must rebound higher than stone on metal"):
		return

	var wind_ball: PhysicsBall = balls.WindBall
	if not _require(wind_ball.linear_velocity.x > 1.0, "wind must accelerate a real light rigid body"):
		return
	var steel: PhysicsBall = balls.MagneticSteelBall
	var aluminum: PhysicsBall = balls.AluminumBall
	if not _require(steel.global_position.x > 7.0, "magnetic steel must be attracted by physical force"):
		return
	if not _require(absf(aluminum.global_position.x - 6.0) < 0.08, "ordinary magnet must not attract aluminum"):
		return

	var zero_g: PhysicsBall = balls.ZeroGravityBall
	var control: PhysicsBall = balls.GravityControlBall
	if not _require(zero_g.global_position.y > 5.8, "zero-gravity field must cancel continued world-gravity acceleration"):
		return
	if not _require(control.global_position.y < -5.0 and zero_g.global_position.y - control.global_position.y > 10.0, "control body must continue falling under world gravity"):
		return

	print("PHYSICS LAB PASS: 7 balls, 9 surfaces, pair friction/bounce, rolling, wind, selective magnet and zero gravity")
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("PHYSICS LAB FAIL: " + message)
	quit(1)
	return false
