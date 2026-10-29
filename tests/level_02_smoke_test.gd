extends SceneTree
## Integration checks for Clockwork Factory mechanisms and level transitions.


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
	game._load_level(1)
	await process_frame
	await physics_frame

	if not _require(game.current_level_index == 1 and game.level_data["id"] == "clockwork_factory_02", "Level 2 must load from separate data"):
		return
	if not _require(game.ball is RigidBody3D and not game.ball.freeze, "Level 2 marble must be a live RigidBody3D"):
		return
	if not _require(game.board.get_node_or_null("StartDeckCollision") != null, "Factory floor tiles need real collisions"):
		return
	if not _require(game.board.get_node_or_null("BridgePitTrigger") != null, "Factory gaps need fall triggers"):
		return
	if not _require(game.clockwork is ClockworkMechanisms, "Clockwork mechanisms must use the shared component"):
		return
	game._layout_hud(Vector2(800.0, 600.0))
	if not _require(game.button_row.position.y > game.info_panel.position.y + 80.0, "HUD controls must reflow below status on narrow screens"):
		return
	game._layout_hud(Vector2(1280.0, 720.0))
	await _wait_physics_frames(60)
	var settled_start: Vector3 = game.board.to_local(game.ball.global_position)
	if not _require(settled_start.y > 0.28 and settled_start.y < 0.55, "Level 2 marble must settle safely on the start deck"):
		return

	var clockwork: ClockworkMechanisms = game.clockwork
	if not _require(clockwork.gear_bodies.size() == 3, "Factory must build three physical gears"):
		return
	for gear: AnimatableBody3D in clockwork.gear_bodies:
		if not _require(gear.get_node_or_null("HubCollision") is CollisionShape3D, "Each gear needs a hub collider"):
			return
		var tooth_collisions := 0
		for child in gear.get_children():
			if child is CollisionShape3D and child.name.to_lower().contains("tooth"):
				tooth_collisions += 1
		if not _require(tooth_collisions >= 10, "Gear teeth need physical collision shapes"):
			return

	var gear_rotation := clockwork.gear_bodies[0].rotation.y
	var platform_start := clockwork.moving_platform.position
	await _wait_physics_frames(60)
	if not _require(absf(clockwork.gear_bodies[0].rotation.y - gear_rotation) > 0.5, "Gears must rotate during physics ticks"):
		return
	if not _require(clockwork.moving_platform.position.distance_to(platform_start) > 0.25, "Transfer platform must move on its route"):
		return
	game._reset_level()
	await physics_frame
	var ride_start: Vector3 = game.ball.global_position
	game.ball.global_position = clockwork.moving_platform.to_global(Vector3.UP * 0.48)
	game.ball.linear_velocity = Vector3.ZERO
	ride_start = game.ball.global_position
	await _wait_physics_frames(45)
	var platform_local_ball: Vector3 = clockwork.moving_platform.to_local(game.ball.global_position)
	if not _require(game.ball.global_position.distance_to(ride_start) > 0.12 and absf(platform_local_ball.x) < 0.75, "Moving platform collider must carry the rigid marble"):
		return
	game._reset_level()
	await physics_frame

	clockwork.activate_bridge()
	await _wait_physics_frames(120)
	if not _require(clockwork.bridge_open and absf(clockwork.bridge_body.rotation.z - clockwork.bridge_open_angle) < 0.06, "Lever must lower the collidable bridge"):
		return
	if not _require(clockwork.bridge_body.get_node_or_null("BridgeCollision") is CollisionShape3D, "Bridge must retain a real collider"):
		return

	clockwork.activate_elevator()
	await _wait_physics_frames(110)
	if not _require(clockwork.elevator_raised and clockwork.elevator_body.position.y > clockwork.elevator_origin.y + 0.90, "Lift must reach the upper deck"):
		return
	if not _require(clockwork.elevator_body.get_node_or_null("LiftCollision") is CollisionShape3D, "Lift must retain a real collider"):
		return

	clockwork.activate_gate()
	await _wait_physics_frames(50)
	if not _require(clockwork.gate_body.position.y > clockwork.gate_origin.y + 1.20, "Timer pad must lift the physical gate"):
		return
	await _wait_physics_frames(440)
	if not _require(clockwork.gate_timer <= 0.01 and clockwork.gate_body.position.y < clockwork.gate_origin.y + 0.08, "Timer gate must close after its countdown"):
		return

	clockwork.activate_bridge()
	clockwork.activate_elevator()
	clockwork.activate_gate()
	game._reset_level()
	if not _require(not clockwork.bridge_open and not clockwork.elevator_raised and clockwork.gate_timer == 0.0, "Restart must reset every mechanism"):
		return

	game._load_level(0)
	await process_frame
	game._on_goal_entered(game.ball)
	if not _require(game.game_won and game.completion_overlay.visible, "Level 1 completion screen must appear"):
		return
	game._advance_level()
	if not _require(game.current_level_index == 1 and game.level_data["id"] == "clockwork_factory_02", "Completion must transition from level 1 to level 2"):
		return

	print("LEVEL 2 PASS: floor gaps, physical gears, shafts, bridge, moving platform, lift, timer gate, reset, completion and transition")
	quit(0)


func _wait_physics_frames(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("LEVEL 2 FAIL: " + message)
	quit(1)
	return false
