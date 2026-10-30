extends SceneTree
## Level 03 Vertical Liftworks: three physical tiers, a carrying lift, obstacles,
## the full start-to-socket route, smart camera switching and goal validation.

const T1 := 0.02
const T2 := 1.42
const T3 := 2.82
const PROBE_RADIUS := 0.30
const PROBE_LIFT := 0.36


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
	game._load_level(2)
	await process_frame
	await physics_frame

	if not _require(game.current_level_index == 2 and game.level_data["id"] == "vertical_liftworks_03", "Level 3 must load from its own data file"):
		return
	if not _require(game.level_selector.item_count == 3, "Level select must list three levels"):
		return
	if not _require(game.ball is RigidBody3D and not game.ball.freeze, "Level 3 marble must be a live RigidBody3D"):
		return
	var board: AnimatableBody3D = game.board

	# --- Three physical tiers on ONE board -------------------------------------
	var tops := {}
	for tile: Dictionary in game.level_data["floor_tiles"]:
		if not _require(board.get_node_or_null(String(tile["name"]) + "Collision") is CollisionShape3D, "Tile %s needs a collider on the tilting board" % tile["name"]):
			return
		var tile_at: Vector3 = tile["position"]
		var tile_size: Vector3 = tile["size"]
		var top := snappedf(tile_at.y + tile_size.y * 0.5, 0.01)
		if top > -0.5:
			tops[top] = true
	if not _require(tops.size() == 3 and tops.has(T1) and tops.has(T2) and tops.has(T3), "Level 3 must have exactly three walkable tier heights"):
		return

	var works = game.clockwork
	if not _require(works is LiftworksMechanisms, "Level 3 must use the LiftworksMechanisms component"):
		return
	var lift: VerticalLift = works.lift
	if not _require(lift is VerticalLift and lift.floors.size() == 3 and lift.landing_gates.size() == 3, "Lift must serve three floors with landing gates"):
		return
	if not _require(lift.deck.get_node_or_null("LiftDeckCollision") is CollisionShape3D, "Lift deck needs a real collider"):
		return

	# --- Every obstacle is a physical body -----------------------------------
	var obstacles: Array = []
	obstacles.append_array(works.gear_bodies)
	obstacles.append_array(works.rotor_bodies)
	obstacles.append_array(works.shutter_bodies)
	obstacles.append_array([works.bridge_body, works.moving_platform, works.gate_body])
	obstacles.append_array(lift.landing_gates)
	if not _require(works.gear_bodies.size() >= 3 and works.rotor_bodies.size() >= 2 and works.shutter_bodies.size() >= 2, "Level 3 needs gears, rotating shafts and shutters"):
		return
	for body in obstacles:
		if not _require(body is AnimatableBody3D and _has_collision(body), "Obstacle %s must be an AnimatableBody3D with collision" % body.name):
			return
	if not _require(works.power_cube is PuzzleShapeBody and works.power_cube.is_inside_tree(), "Power cube must be a live PuzzleShapeBody"):
		return

	await _wait_physics_frames(60)
	var settled: Vector3 = board.to_local(game.ball.global_position)
	if not _require(settled.y > T1 + 0.25 and settled.y < T1 + 0.5, "Marble must settle on the tier 1 start pad"):
		return

	# --- Full route: start -> lift -> tier 2 -> release -> lift -> socket -----
	if not await _check_route(game, works):
		return

	# --- Moving mechanisms really move ---------------------------------------
	var rotor_angle: float = works.rotor_bodies[0].rotation.y
	var platform_start: Vector3 = works.moving_platform.position
	await _wait_physics_frames(40)
	# Euler angles wrap, so compare over a window shorter than half a turn.
	if not _require(absf(angle_difference(rotor_angle, works.rotor_bodies[0].rotation.y)) > 0.5, "Sweeper must rotate"):
		return
	var shutter_seen := {}
	var platform_reach := 0.0
	for _frame in range(260):
		await physics_frame
		shutter_seen[str(works.shutters_open())] = true
		platform_reach = maxf(platform_reach, works.moving_platform.position.distance_to(platform_start))
	if not _require(platform_reach > 0.5, "Transfer platform must shuttle across the gap"):
		return
	if not _require(shutter_seen.size() >= 3, "Shutters must cycle through open and closed states"):
		return
	game._reset_level()
	await physics_frame

	# --- Goal never completes falsely ----------------------------------------
	var goal: Vector3 = game.level_data["goal"]
	game.ball.freeze = true
	game.ball.global_position = board.to_global(goal + Vector3(0.62, 0.20, 0.0))
	await _wait_physics_frames(40)
	if not _require(not game.game_won and not game.goal_detector.capture_complete, "Marble beside the socket must not finish Level 3"):
		return
	game.ball.global_position = board.to_global(goal + Vector3(0.0, 1.10, 0.0))
	await _wait_physics_frames(30)
	if not _require(not game.game_won, "Marble above the socket must not finish Level 3"):
		return
	game.ball.freeze = false
	game._reset_level()
	await _wait_physics_frames(5)

	# --- Lift: locked until the cube powers it --------------------------------
	_place_on_deck(game, lift)
	await _wait_physics_frames(110)
	if not _require(lift.current_floor == 0 and not lift.moving, "Unpowered lift must not leave floor 1"):
		return
	var plate: Vector3 = game.level_data["liftworks"]["power_plate"]["position"]
	works.power_cube.global_position = board.to_global(plate + Vector3.UP * 0.32)
	works.power_cube.linear_velocity = Vector3.ZERO
	await _wait_physics_frames(30)
	if not _require(works.lift_powered and lift.is_powered(), "Cube on the power plate must power the lift"):
		return

	# The marble is still riding: the lift departs, carries it and parks at floor 2.
	if not await _wait_for_floor(lift, 1, 420):
		_require(false, "Lift must carry the marble to floor 2")
		return
	var on_floor_two: Vector3 = board.to_local(game.ball.global_position)
	var on_deck: Vector3 = lift.deck.to_local(game.ball.global_position)
	if not _require(on_floor_two.y > T2 + 0.2 and absf(on_deck.x) < 0.6 and absf(on_deck.z) < 0.6, "Marble must physically ride the deck up to tier 2"):
		return
	await _wait_physics_frames(40)
	if not _require(lift.door_open("west") and not lift.door_open("south"), "Floor 2 must open the west deck door and keep the south door shut"):
		return
	if not _require(lift.landing_gates[1].position.y < lift.landing_closed_y[1] - 0.3 and lift.landing_gates[0].position.y > lift.landing_closed_y[0] - 0.05, "Only the floor 2 landing gate may be open"):
		return
	await _wait_physics_frames(120)
	if not _require(lift.current_floor == 1, "Floor 3 must stay locked before the upper release"):
		return

	var release: Vector3 = game.level_data["liftworks"]["upper_release"]["position"]
	game.ball.global_position = board.to_global(release + Vector3.UP * 0.40)
	game.ball.linear_velocity = Vector3.ZERO
	await _wait_physics_frames(25)
	if not _require(works.upper_released and not lift.locked[2], "Upper release lever must unlock floor 3"):
		return
	_place_on_deck(game, lift)
	if not await _wait_for_floor(lift, 2, 420):
		_require(false, "Lift must carry the marble to floor 3")
		return
	if not _require(board.to_local(game.ball.global_position).y > T3 + 0.2, "Marble must arrive on tier 3"):
		return

	var call_pad: Vector3 = game.level_data["liftworks"]["lift"]["call_pads"][0]
	game.ball.global_position = board.to_global(call_pad + Vector3.UP * 0.40)
	game.ball.linear_velocity = Vector3.ZERO
	if not await _wait_for_floor(lift, 0, 520):
		_require(false, "Floor 1 call pad must bring the lift down")
		return

	# --- Bridge and timer gate -------------------------------------------------
	works.activate_bridge()
	await _wait_physics_frames(110)
	if not _require(absf(works.bridge_body.rotation.z - works.bridge_open_angle) < 0.06, "Lever must lower the pit bridge"):
		return
	works.activate_gate()
	await _wait_physics_frames(50)
	if not _require(works.gate_body.position.y > works.gate_origin.y + 0.7, "Timer pad must lift the tier 3 gate"):
		return

	game._reset_level()
	await physics_frame
	if not _require(lift.current_floor == 0 and lift.locked[1] and lift.locked[2] and not works.lift_powered and not works.bridge_open, "Reset must restore the lift, locks and bridge"):
		return
	var cube_local: Vector3 = board.to_local(works.power_cube.global_position)
	if not _require(cube_local.distance_to(game.level_data["liftworks"]["power_cube"]["start"]) < 0.05, "Reset must return the power cube"):
		return

	# --- Smart camera ---------------------------------------------------------
	var cam: SmartCameraController = game.smart_camera
	if not _require(cam != null and cam.auto_enabled and cam.mode == SmartCameraController.Mode.OVERVIEW, "Level 3 starts in the automatic overview camera"):
		return
	game.ball.freeze = true
	game.ball.global_position = board.to_global(Vector3(1.0, T2 + 0.34, -1.25))
	await _wait_process_frames(8)
	if not _require(cam.mode == SmartCameraController.Mode.OVERVIEW and cam.overview_occluded, "A short occlusion must not switch the camera yet"):
		return
	await _wait_process_frames(80)
	if not _require(cam.mode == SmartCameraController.Mode.CHASE and cam.auto_chase, "Tier 3 hiding the marble must switch to CHASE"):
		return
	if not _require(_camera_has_clear_view(game), "Chase camera must see the marble without clipping through geometry"):
		return
	if not _require(board.to_local(game.camera.global_position).y < T3 - 0.36, "Chase camera must stay beneath the tier 3 deck"):
		return
	if not _require(game.camera_label.text.contains("CHASE"), "HUD must show CAMERA: CHASE"):
		return
	game.ball.global_position = board.to_global(Vector3(-3.40, T2 + 0.34, -2.40))
	await _wait_process_frames(30)
	if not _require(cam.mode == SmartCameraController.Mode.CHASE, "Camera must wait before leaving CHASE"):
		return
	await _wait_process_frames(140)
	if not _require(cam.mode == SmartCameraController.Mode.OVERVIEW and not cam.auto_chase, "Clear view must return to OVERVIEW"):
		return

	cam.probe_override = 1
	game._cycle_camera_preference()
	await _wait_process_frames(60)
	if not _require(cam.preference == SmartCameraController.Preference.OVERVIEW and cam.mode == SmartCameraController.Mode.OVERVIEW, "Manual TOP view must override auto chase"):
		return
	game._cycle_camera_preference()
	await _wait_process_frames(60)
	if not _require(cam.mode == SmartCameraController.Mode.CHASE, "Manual CHASE view must work"):
		return
	game._cycle_camera_preference()
	cam.probe_override = -1
	if not _require(cam.preference == SmartCameraController.Preference.AUTO, "Camera preference must cycle back to AUTO"):
		return

	# --- Seated socket completes ----------------------------------------------
	game.ball.global_position = board.to_global(goal + Vector3(0.0, 0.20, 0.0))
	await _wait_physics_frames(40)
	if not _require(game.game_won and game.completion_overlay.visible, "Centred steady marble must complete Level 3"):
		return
	game.ball.freeze = false

	# --- Levels 1 and 2 still work, and 2 -> 3 transition ----------------------
	game._load_level(0)
	await process_frame
	await physics_frame
	if not _require(game.level_data["id"] == "brass_workshop_01" or game.level_data["number"] == 1, "Level 1 must still load"):
		return
	if not _require(not game.smart_camera.auto_enabled and game.smart_camera.mode == SmartCameraController.Mode.OVERVIEW, "Levels 1 and 2 keep the classic overview by default"):
		return
	game._load_level(1)
	await process_frame
	await physics_frame
	var factory_goal: Vector3 = game.level_data["goal"]
	game.ball.freeze = true
	game.ball.global_position = game.board.to_global(factory_goal + Vector3(0.0, 0.20, 0.0))
	await _wait_physics_frames(40)
	if not _require(game.game_won and game.next_level_button.text.contains("LIFTWORKS"), "Level 2 completion must offer Level 3"):
		return
	game._advance_level()
	if not _require(game.current_level_index == 2 and game.level_data["id"] == "vertical_liftworks_03", "Completion must transition from level 2 to level 3"):
		return

	print("LEVEL 3 PASS: three tiers, carrying lift with doors/gates/locks/call, cube power plate, upper release, bridge, shutters, sweepers, gears, timer gate, full route, smart camera auto/manual, seated goal, reset and transitions")
	quit(0)


## Static reachability: every free-roll leg is swept with a marble-sized sphere
## against the board's walls, every waypoint has a deck under it, and each
## mechanism leg is proven by the mechanism that bridges it.
func _check_route(game: Node, works: LiftworksMechanisms) -> bool:
	var board: AnimatableBody3D = game.board
	var route: Array = game.level_data["route"]
	var start: Vector3 = game.level_data["start"]
	var goal: Vector3 = game.level_data["goal"]
	var first: Vector3 = route[0]["at"]
	var last: Vector3 = route[route.size() - 1]["at"]
	if not _require(Vector2(first.x, first.z).distance_to(Vector2(start.x, start.z)) < 0.1, "Route must begin at the start pad"):
		return false
	if not _require(Vector2(last.x, last.z).distance_to(Vector2(goal.x, goal.z)) < 0.1 and absf(last.y - T3) < 0.01, "Route must end in the final socket, not part-way"):
		return false
	var vias := {}
	for step: Dictionary in route:
		vias[step["via"]] = true
	for required_via in ["lift", "bridge", "platform", "gate"]:
		if not _require(vias.has(required_via), "Route must use the %s" % required_via):
			return false

	var space := board.get_world_3d().direct_space_state
	var dynamic: Array[RID] = [game.ball.get_rid(), works.power_cube.get_rid()]
	_collect_body_rids(works, dynamic)
	# The parked lift deck is the floor of the floor-1 landing waypoint.
	var support_exclude: Array[RID] = dynamic.duplicate()
	support_exclude.erase(works.lift.deck.get_rid())
	for index in range(route.size()):
		var step: Dictionary = route[index]
		var at: Vector3 = step["at"]
		var via: String = step["via"]
		# A waypoint inside the shaft is floored by the parked deck; the ride test
		# below proves the deck reaches every floor.
		var lift_xz: Vector3 = game.level_data["liftworks"]["lift"]["position"]
		var in_shaft := Vector2(at.x, at.z).distance_to(Vector2(lift_xz.x, lift_xz.z)) < 0.1
		if not in_shaft and not _require(_deck_under(space, board, at, support_exclude), "Route waypoint %d needs a static deck at %s" % [index, at]):
			return false
		if index == 0:
			continue
		var previous: Vector3 = route[index - 1]["at"]
		match via:
			"roll":
				if not _require(absf(previous.y - at.y) < 0.01 and _sweep_clear(space, board, previous, at, dynamic), "Route roll %d -> %d is blocked by static geometry" % [index - 1, index]):
					return false
			"lift":
				if not _require(in_shaft and _serves_height(works.lift, at.y), "Lift leg %d must ride the lift shaft" % index):
					return false
			"platform":
				var platform: Dictionary = game.level_data["liftworks"]["moving_platform"]
				var origin: Vector3 = platform["origin"]
				var travel: Vector3 = platform["travel"]
				var size: Vector3 = platform["size"]
				var east_edge := origin.x + size.x * 0.5
				var west_edge := origin.x + travel.x - size.x * 0.5
				if not _require(absf(east_edge + 0.8) < 0.05 and absf(west_edge + 2.4) < 0.05 and absf(origin.y + size.y * 0.5 - T2) < 0.01, "Transfer platform must dock flush at both gap edges"):
					return false
			"bridge":
				works.activate_bridge()
				await _wait_physics_frames(110)
				var mid := (previous + at) * 0.5
				var hit := _ray_down(space, board, mid, [game.ball.get_rid()])
				var ok: bool = not hit.is_empty() and hit["collider"] == works.bridge_body
				works.reset_state()
				if not _require(ok, "Lowered bridge must carry the marble across the pit"):
					return false
			"gate":
				var all_static_and_gate: Array[RID] = dynamic.duplicate()
				all_static_and_gate.erase(works.gate_body.get_rid())
				if not _require(not _sweep_clear(space, board, previous, at, all_static_and_gate), "Closed timer gate must block the main corridor"):
					return false
				works.activate_gate()
				await _wait_physics_frames(60)
				var gate_clear := _sweep_clear(space, board, previous, at, all_static_and_gate)
				works.reset_state()
				if not _require(gate_clear, "Open timer gate must let the marble through"):
					return false
	await _wait_physics_frames(2)
	return true


func _serves_height(lift: VerticalLift, height: float) -> bool:
	for floor_top in lift.floors:
		if absf(floor_top - height) < 0.01:
			return true
	return false


func _deck_under(space: PhysicsDirectSpaceState3D, board: Node3D, at: Vector3, exclude: Array[RID]) -> bool:
	var hit := _ray_down(space, board, at, exclude)
	return not hit.is_empty() and absf(board.to_local(hit["position"]).y - at.y) < 0.06


func _ray_down(space: PhysicsDirectSpaceState3D, board: Node3D, at: Vector3, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(board.to_global(at + Vector3.UP * 0.30), board.to_global(at + Vector3.DOWN * 0.40))
	query.exclude = exclude
	return space.intersect_ray(query)


func _sweep_clear(space: PhysicsDirectSpaceState3D, board: Node3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> bool:
	var probe := SphereShape3D.new()
	probe.radius = PROBE_RADIUS
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.transform = Transform3D(Basis.IDENTITY, board.to_global(from + Vector3.UP * PROBE_LIFT))
	params.motion = board.to_global(to + Vector3.UP * PROBE_LIFT) - params.transform.origin
	params.exclude = exclude
	var result := space.cast_motion(params)
	return result.size() == 2 and result[0] >= 0.999


func _collect_body_rids(node: Node, into: Array[RID]) -> void:
	for child in node.get_children():
		if child is CollisionObject3D:
			into.append((child as CollisionObject3D).get_rid())
		_collect_body_rids(child, into)


func _has_collision(body: Node) -> bool:
	for child in body.get_children():
		if child is CollisionShape3D:
			return true
	return false


func _place_on_deck(game: Node, lift: VerticalLift) -> void:
	game.ball.global_position = lift.deck.to_global(Vector3(0.0, 0.45, 0.0))
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.angular_velocity = Vector3.ZERO
	game.ball.sleeping = false


func _wait_for_floor(lift: VerticalLift, floor_index: int, max_frames: int) -> bool:
	for _frame in range(max_frames):
		await physics_frame
		if lift.current_floor == floor_index and not lift.moving:
			return true
	return false


## Walls and decks (the board body) must never sit between camera and marble.
func _camera_has_clear_view(game: Node) -> bool:
	var query := PhysicsRayQueryParameters3D.create(game.ball.global_position, game.camera.global_position)
	var exclude: Array[RID] = [game.ball.get_rid()]
	var space: PhysicsDirectSpaceState3D = game.board.get_world_3d().direct_space_state
	for _attempt in range(8):
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		if hit["collider"] == game.board:
			return false
		exclude.append(hit["rid"])
	return true


func _wait_physics_frames(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _wait_process_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("LEVEL 3 FAIL: " + message)
	quit(1)
	return false
