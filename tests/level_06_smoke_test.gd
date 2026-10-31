extends SceneTree
## Runtime integration check for the test level. It exercises a real rolling
## segment, both physical lifts, goal/reset, camera setup and LOW/HIGH reload.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if not _require(packed != null, "Main scene must load"):
		return
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame
	game._load_level(5)
	await process_frame
	await physics_frame

	if not _require(game.current_level_index == 5 and game.level_selector.item_count == 6, "Level 06 must be selectable as the sixth level"):
		return
	if not _require(game.level_data["id"] == "orbital_mechanism_06_test", "Orbital definition must be active"):
		return
	var visuals := game.level06_visuals as Level06Visuals
	var mechanisms := game.clockwork as Level06Mechanisms
	if not _require(visuals != null and mechanisms != null, "Level 06 visuals and mechanism layer must be connected"):
		return
	var expected_quality := Level06Visuals.Quality.LOW if OS.get_name() == "Android" else Level06Visuals.Quality.HIGH
	if not _require(visuals.quality == expected_quality, "Runtime must select the platform-appropriate graphics profile"):
		return
	var shape_count: int = game.board.get_children().filter(func(child: Node) -> bool: return child is CollisionShape3D).size()
	if not _require(shape_count >= 30, "Route must carry simplified physics colliders (%d)" % shape_count):
		return
	if not _require(game.ball is RigidBody3D and not game.ball.freeze, "A live physical marble must spawn"):
		return

	# Let the marble settle, then use the same tilt input path as the phone UI.
	await _wait_physics(45)
	var start_local: Vector3 = game.board.to_local(game.ball.global_position)
	game.control_mode = game.ControlMode.TOUCH
	game.drag_tilt = Vector2(1.0, 0.0)
	await _wait_physics(75)
	game.drag_tilt = Vector2.ZERO
	var rolled_local: Vector3 = game.board.to_local(game.ball.global_position)
	if not _require(rolled_local.distance_to(start_local) > 0.12 and rolled_local.y > 3.4, "Tilt must roll the marble on the start route"):
		return

	# Exercise each separate AnimatableBody lift through its public gameplay API.
	game.ball.freeze = true
	game.ball.global_position = game.board.to_global(game.level_data["start"])
	game.ball.linear_velocity = Vector3.ZERO
	game.respawn_queued = false
	mechanisms.request_lift("L01", true)
	if not await _wait_lift(mechanisms, "L01", 9.0, 360):
		_require(false, "L01 must travel 5 m to the middle level (got %.3f)" % mechanisms.lift_surface("L01"))
		return
	mechanisms.request_lift("L02", true)
	if not await _wait_lift(mechanisms, "L02", 12.0, 300):
		_require(false, "L02 must travel 3 m to the upper level (got %.3f)" % mechanisms.lift_surface("L02"))
		return

	# The receiver uses the same centred-and-steady detector as existing levels.
	game.ball.freeze = true
	game.ball.global_position = game.board.to_global(game.level_data["goal"] + Vector3(0.0, 0.20, 0.0))
	await _wait_physics(45)
	if not _require(game.game_won, "Golden receiver must complete Level 06"):
		return
	game._reset_level()
	await _wait_physics(2)
	if not _require(not game.game_won and game.ball.global_position.distance_to(game.board.to_global(game.level_data["start"])) < 0.09, "Reset must restore start and game state"):
		return
	if not _require(absf(mechanisms.lift_surface("L01") - 4.0) < 0.02 and absf(mechanisms.lift_surface("L02") - 9.0) < 0.02, "Reset must return both lifts (L01 %.3f, L02 %.3f)" % [mechanisms.lift_surface("L01"), mechanisms.lift_surface("L02")]):
		return

	game._toggle_graphics()
	await process_frame
	await physics_frame
	var toggled_quality := Level06Visuals.Quality.HIGH if expected_quality == Level06Visuals.Quality.LOW else Level06Visuals.Quality.LOW
	if not _require(game.level06_visuals != null and game.level06_visuals.quality == toggled_quality, "GFX must reload the alternate committed v2 GLB"):
		return
	if not _require(game.smart_camera != null and game.smart_camera.auto_enabled, "Level 06 overview/chase camera controller must be active"):
		return

	# Quick regression load: every previous level still resolves through the same menu.
	for level_index in range(5):
		game._load_level(level_index)
		await process_frame
		await physics_frame
		if not _require(game.current_level_index == level_index and game.ball != null and game.board != null, "Existing Level %d must still load" % (level_index + 1)):
			return
	print("LEVEL 6 PASS: selector, LOW/HIGH v2 GLB, live marble and tilt, simplified route collisions, L01/L02 travel, golden goal, reset, smart camera, Levels 01-05 load")
	quit(0)


func _wait_physics(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _wait_lift(mechanisms: Level06Mechanisms, lift_name: String, target: float, timeout_frames: int) -> bool:
	for _index in range(timeout_frames):
		await physics_frame
		if absf(mechanisms.lift_surface(lift_name) - target) < 0.08:
			return true
	return false


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("LEVEL 6 FAIL: " + message)
	quit(1)
	return false
