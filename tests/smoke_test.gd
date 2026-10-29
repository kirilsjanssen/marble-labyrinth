extends SceneTree
## Headless integration check for scene loading, collisions, control and hazards.


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

	if not _require(game.board is AnimatableBody3D, "Board must use physics-synchronised AnimatableBody3D"):
		return
	if not _require(game.ball is RigidBody3D and not game.ball.freeze, "Marble must remain a live RigidBody3D"):
		return
	if not _require(game.board.get_node_or_null("BoardCollision") != null, "Board collision is required"):
		return
	if not _require(game.board.get_node_or_null("WestWallCollision") != null, "Wall collisions are required"):
		return
	if not _require(game.level_data["walls"].size() >= 8, "Level data must describe the maze"):
		return

	await _wait_physics_frames(90)
	var settled: Vector3 = game.board.to_local(game.ball.global_position)
	if not _require(settled.y > 0.28 and settled.y < 0.55, "Marble must settle on the physical deck"):
		return

	var before_tilt: Vector3 = game.ball.global_position
	Input.action_press("ui_right")
	await _wait_physics_frames(75)
	Input.action_release("ui_right")
	if not _require(game.board.rotation.z < -0.12, "Keyboard input must tilt the board"):
		return
	if not _require(game.ball.global_position.distance_to(before_tilt) > 0.08, "Tilt must move the physical marble"):
		return

	game._reset_level()
	await physics_frame
	var start: Vector3 = game.level_data["start"]
	if not _require(game.ball.global_position.distance_to(game.board.to_global(start)) < 0.08, "Reset must restore the marble"):
		return
	if not _require(not game.game_won and not game.respawn_queued, "Reset must restore game state"):
		return

	var wind: Dictionary = game.level_data["wind"]
	var wind_position: Vector3 = wind["position"]
	game.ball.global_position = game.board.to_global(wind_position + Vector3.UP * 0.42)
	game.ball.linear_velocity = Vector3.ZERO
	await _wait_physics_frames(20)
	if not _require(game.ball.linear_velocity.length() > 0.08, "Wind device must apply a real force"):
		return

	var magnet: Dictionary = game.level_data["magnet"]
	var magnet_position: Vector3 = magnet["position"]
	game.ball.global_position = game.board.to_global(magnet_position + Vector3(1.0, 0.42, 0.0))
	game.ball.linear_velocity = Vector3.ZERO
	await _wait_physics_frames(20)
	if not _require(game.ball.linear_velocity.x < -0.02, "Magnet must attract the marble"):
		return

	game._on_trap_entered(game.ball)
	if not _require(game.respawn_queued, "Trap must queue a level reset"):
		return
	game._reset_level()
	game._on_goal_entered(game.ball)
	if not _require(game.game_won, "Goal must complete the level"):
		return

	print("SMOKE PASS: scene, rigid marble, deck and wall collisions, tilt, motion, wind, magnet, trap, reset, goal")
	quit(0)


func _wait_physics_frames(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("SMOKE FAIL: " + message)
	quit(1)
	return false
