extends SceneTree
## Regression: overlapping the goal's wide Area3D must not prematurely finish.
## Only a centred, steady, held body at the socket qualifies.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if not _require(scene != null, "Main scene must load"):
		return
	var game := scene.instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame
	if not _require(game.goal_detector is GoalSocketDetector, "Goal must use reusable seated-socket component"):
		return

	var goal: Vector3 = game.level_data["goal"]
	game.ball.freeze = true
	game.ball.global_position = game.board.to_global(goal + Vector3(0.62, 0.20, 0.0))
	game._on_goal_entered(game.ball)
	if not _require(not game.game_won, "Manually calling old trigger must not bypass validation"):
		return
	await _wait_physics_frames(40)
	if not _require(not game.game_won and not game.goal_detector.capture_complete,
		"Ball close to outside edge must not finish the level"):
		return

	game.ball.global_position = game.board.to_global(goal + Vector3(0.0, 1.10, 0.0))
	await _wait_physics_frames(25)
	if not _require(not game.game_won, "Object above the goal must not complete"):
		return

	game.ball.global_position = game.board.to_global(goal + Vector3(0.0, 0.20, 0.0))
	await _wait_physics_frames(3)
	if not _require(not game.game_won, "Entering centre must require a dwell time"):
		return
	await _wait_physics_frames(40)
	if not _require(game.game_won and game.completion_overlay.visible,
		"Steady centred ball must complete with overlay"):
		return

	game.ball.freeze = false
	game._reset_level()
	if not _require(not game.game_won and not game.goal_detector.capture_complete,
		"Reset clears goal state"):
		return

	game._load_level(1)
	await process_frame
	await physics_frame
	var upper_goal: Vector3 = game.level_data["goal"]
	game.ball.freeze = true
	game.ball.global_position = game.board.to_global(upper_goal + Vector3(0.62, 0.20, 0.0))
	await _wait_physics_frames(35)
	if not _require(not game.game_won, "Level 2 must also reject edge overlap"):
		return
	game.ball.global_position = game.board.to_global(upper_goal + Vector3(0.0, 0.20, 0.0))
	await _wait_physics_frames(40)
	if not _require(game.game_won, "Level 2 centred socket must complete"):
		return

	print("GOAL SOCKET PASS: rejects edges/height/early signal, accepts centred hold and resets on both levels")
	quit(0)


func _wait_physics_frames(count: int) -> void:
	for _i in range(count):
		await physics_frame


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("GOAL SOCKET FAIL: " + message)
	quit(1)
	return false
