extends SceneTree
## Level 04 Alpine Watermill. The main check is a PHYSICAL playthrough: an
## autopilot only tilts the board (the same input a player gives), and the
## rigid marble must roll from the start pad through the sluice lever, wheel,
## cube plate, mill lift, sluice boards, pontoon, diverter, float ride and
## timer gate into the goal socket. Nothing is teleported on that run.

const T1 := 0.02
const T2 := 1.42
const T3 := 2.82
const REACH := 0.20
const LEG_TIMEOUT := 14.0
const KP := 1.7
const KD := 0.85

var game: Node
var works: WatermillMechanisms
var log_lines: Array[String] = []
var seen_chase_on_tier2 := false
var seen_overview_on_tier2_west := false
var sluice_snapshot := {}
var divert_snapshot := {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if not _require(packed != null, "Main scene must load"):
		return
	game = packed.instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame
	game._load_level(3)
	await process_frame
	await physics_frame
	if not _require(game.level_data["id"] == "alpine_watermill_04" and game.level_selector.item_count == 4, "Level 4 must load and be listed"):
		return
	works = game.clockwork
	if not _require(works is WatermillMechanisms, "Level 4 must use WatermillMechanisms"):
		return
	var board: AnimatableBody3D = game.board

	# --- Structure ---------------------------------------------------------------
	var tops := {}
	for tile: Dictionary in game.level_data["floor_tiles"]:
		if not _require(board.get_node_or_null(String(tile["name"]) + "Collision") is CollisionShape3D, "Tile %s needs a collider" % tile["name"]):
			return
		var top := snappedf((tile["position"] as Vector3).y + (tile["size"] as Vector3).y * 0.5, 0.01)
		if top > -0.3:
			tops[top] = true
	if not _require(tops.has(T1) and tops.has(T2) and tops.has(T3) and tops.size() == 3, "Three walkable tiers"):
		return
	var moving_parts: Array = [works.wheel, works.pontoon, works.mill_gate, works.gate_body, works.lift.deck]
	moving_parts.append_array(works.rotor_bodies)
	moving_parts.append_array(works.shutter_bodies)
	moving_parts.append_array(works.gear_bodies)
	moving_parts.append_array(works.lift.landing_gates)
	for body in moving_parts:
		if not _require(body is AnimatableBody3D and _has_collision(body), "%s must be a collidable AnimatableBody3D" % body.name):
			return
	if not _require(works.wheel._gears.size() >= 3, "The wheel must drive a real gear train"):
		return
	if not _require(works.network.reservoirs.size() == 4 and works.connections.size() == 5, "Hydraulic network must have its reservoirs and channels"):
		return
	var initial_volume: float = works.network.total_volume()

	# --- Parallax reacts to the camera, with per-layer depth ------------------------
	var env: AlpineParallaxController = game.alpine_environment
	if not _require(env != null and env.far_layers.size() >= 3 and env.get_child_count() >= 8, "Alpine environment needs far layers plus near 3D layers"):
		return
	env.snap_to_camera()
	var before: Array[Vector3] = env.layer_offsets()
	game.yaw += deg_to_rad(80.0)
	game._update_camera()
	env.snap_to_camera()
	var after: Array[Vector3] = env.layer_offsets()
	var moved: Array[float] = []
	for index in range(before.size()):
		moved.append(before[index].distance_to(after[index]))
	for index in range(moved.size() - 1):
		if not _require(moved[index] > moved[index + 1] + 0.3, "Farther layers must follow the camera more (layer %d %.2f vs %.2f)" % [index, moved[index], moved[index + 1]]):
			return
	for index in range(after.size()):
		if not _require(after[index].length() <= env.layer_max_shift[index] + 0.01, "Layer %d must respect its parallax limit" % index):
			return
	game._reset_camera_view()
	game._update_camera()
	env.snap_to_camera()

	# --- Visual water speed is tied to the flux -------------------------------------
	var aqueduct := works.surface_by_name("AqueductEast")
	if not _require(aqueduct != null and works.wheel.state == WaterWheel.State.NO_WATER, "Wheel starts dry"):
		return
	await _wait_physics(30)
	if not _require(aqueduct.uv_speeds().x < 0.01, "Dry aqueduct must not animate"):
		return

	# --- No false finish --------------------------------------------------------------
	var goal: Vector3 = game.level_data["goal"]
	game.ball.freeze = true
	game.ball.global_position = board.to_global(goal + Vector3(0.62, 0.20, 0.0))
	await _wait_physics(40)
	if not _require(not game.game_won, "Marble beside the socket must not finish"):
		return
	game.ball.freeze = false
	game._reset_level()
	await _wait_physics(40)

	# --- PHYSICAL playthrough -------------------------------------------------------------
	game.control_mode = game.ControlMode.TOUCH
	var route: Array = game.level_data["route"]
	for index in range(route.size()):
		var step: Dictionary = route[index]
		if not await _drive_step(index, step):
			for line in log_lines.slice(maxi(0, log_lines.size() - 50)).filter(func(l: String) -> bool: return log_lines.find(l) % 4 == 0):
				print(line)
			return
	game.drag_tilt = Vector2.ZERO
	# Settle into the socket with the board level; the detector needs a hold.
	var settled := false
	for _frame in range(600):
		var to_goal: Vector3 = goal - game.board.to_local(game.ball.global_position)
		if Vector2(to_goal.x, to_goal.z).length() < 0.14:
			# Over the socket: tilt against the motion to brake, like a player.
			var velocity: Vector3 = game.board.global_basis.inverse() * game.ball.linear_velocity
			game.drag_tilt = (-Vector2(velocity.x, velocity.z) * 0.8).limit_length(0.35)
		else:
			game.drag_tilt = _steer_to(goal, true)
		await physics_frame
		if game.game_won:
			settled = true
			break
	game.drag_tilt = Vector2.ZERO
	if not settled:
		print("goal detector local ", game.goal_detector.to_local(game.ball.global_position), " speed ", game.ball.linear_velocity.length(), " overlapping ", game.goal_detector.get_overlapping_bodies().size())
	if not _require(settled and game.completion_overlay.visible, "Marble must physically roll into the goal socket"):
		return

	# --- Linked water evidence collected during the run -------------------------------
	if not _require(sluice_snapshot.get("wheel_state", -1) == WaterWheel.State.WORKING and sluice_snapshot["aqueduct_uv"] > 0.2 and sluice_snapshot["lift_drive"] > 0.5, "Sluice must drive the wheel, gear train and aqueduct visuals"):
		return
	if not _require(divert_snapshot.get("wheel_flux", 9.0) < sluice_snapshot["wheel_flux"] * 0.3 and divert_snapshot["divert_uv"] > 0.2 and divert_snapshot["aqueduct_uv"] < sluice_snapshot["aqueduct_uv"], "Diverter must move the flow (and its visual speed) from the wheel to the tank"):
		return
	if not _require(absf(works.network.total_volume() - initial_volume) < 0.001, "Water volume must be conserved"):
		return
	if not _require(seen_chase_on_tier2 and seen_overview_on_tier2_west, "Camera must chase under tier 3 and return to overview on the open deck"):
		return

	# --- Reset restores water and machinery ---------------------------------------------------
	# Checked before the next physics tick: the ram pump legitimately starts
	# moving water again on the very first step after a reset.
	game._reset_level()
	var fresh_ok: bool = absf(works.network.volume(&"cistern") - 6.0) < 0.001 and absf(works.network.volume(&"tank") - 0.6) < 0.001
	fresh_ok = fresh_ok and works.water_route == WatermillMechanisms.WaterRoute.CLOSED and works.wheel.angular_speed == 0.0
	fresh_ok = fresh_ok and works.lift.current_floor == 0 and not works.lift_powered and absf(works.pontoon_top() - T2) < 0.01
	fresh_ok = fresh_ok and absf(works.mill_gate.position.y - works.mill_gate_closed_y) < 0.01
	fresh_ok = fresh_ok and board.to_local(works.power_cube.global_position).distance_to(game.level_data["watermill"]["power_cube"]["start"]) < 0.05
	if not fresh_ok:
		print("reset state: cistern %.3f tank %.3f route %d wheel %.3f lift %d powered %s pontoon %.3f gate %.3f/%.3f cube %s" % [works.network.volume(&"cistern"), works.network.volume(&"tank"), works.water_route, works.wheel.angular_speed, works.lift.current_floor, works.lift_powered, works.pontoon_top(), works.mill_gate.position.y, works.mill_gate_closed_y, board.to_local(works.power_cube.global_position)])
	if not _require(fresh_ok and not game.game_won, "Reset must restore water, wheel, lift, pontoon, gate and cube"):
		return

	# --- Older levels still load -----------------------------------------------------------
	for level_index in range(3):
		game._load_level(level_index)
		await process_frame
		await physics_frame
		if not _require(game.current_level_index == level_index and game.alpine_environment == null, "Level %d must load without the Alpine environment" % (level_index + 1)):
			return
	print("LEVEL 4 PASS: 3 tiers, physical playthrough start->socket (sluice, wheel, gears, lift, cube plate, sluice boards, pontoon, diverter, float ride, timer gate), conserved water, flux-linked visuals, parallax depth/limits, chase camera, no false finish, reset, older levels")
	quit(0)


func _drive_step(index: int, step: Dictionary) -> bool:
	var target: Vector3 = step["at"]
	var via: String = step["via"]
	var board: AnimatableBody3D = game.board
	match via:
		"lift":
			# Ride: hold still on the deck until the wheel-driven lift parks upstairs.
			if not await _hold_until(func() -> bool: return works.lift.current_floor == 1 and not works.lift.moving, Vector3(target.x, T1, target.z), 30.0):
				return _fail(index, "lift never carried the marble to tier 2 (drive %.2f, wheel %s)" % [works.lift.drive_factor, works.wheel.state_name()])
			var ride_local: Vector3 = board.to_local(game.ball.global_position)
			if ride_local.y < T2 + 0.2:
				return _fail(index, "marble was not carried by the lift deck")
			await _wait_physics(40)
			return true
		"float":
			if not await _hold_until(func() -> bool: return works.pontoon_top() >= T3 - 0.02, Vector3(target.x, T2, target.z), 25.0):
				return _fail(index, "pontoon never floated to tier 3 (tank %.2f)" % works.tank_fill())
			if board.to_local(game.ball.global_position).y < T3 + 0.2:
				return _fail(index, "marble did not ride the pontoon up")
			return true
		"push_cube":
			if not await _roll_until(Vector3(target.x, target.y, target.z), func() -> bool: return works.lift_powered, LEG_TIMEOUT):
				return _fail(index, "cube never reached the plate")
			return true
		"gate":
			if not await _roll_until(target, func() -> bool: return false, LEG_TIMEOUT, true):
				return _fail(index, "could not pass the timer gate")
			return true
	var wait: String = step.get("wait", "")
	if wait == "mill_gate":
		if not await _hold_until(func() -> bool: return works.mill_gate.position.y < works.mill_gate_closed_y - 0.45, board.to_local(game.ball.global_position), 8.0):
			return _fail(index, "mill gate did not open")
	elif wait == "sluice_boards":
		if not await _hold_until(_sluice_boards_ready, board.to_local(game.ball.global_position), 12.0):
			return _fail(index, "sluice boards never opened together")
	if not await _roll_until(target, func() -> bool: return false, LEG_TIMEOUT, true):
		return _fail(index, "could not roll to %s (at %s)" % [target, board.to_local(game.ball.global_position)])
	match step.get("event", ""):
		"sluice":
			if not await _hold_until(func() -> bool: return works.water_route == WatermillMechanisms.WaterRoute.TO_WHEEL, target, 3.0):
				return _fail(index, "sluice lever did not open the sluice")
		"divert":
			if not await _hold_until(func() -> bool: return works.water_route == WatermillMechanisms.WaterRoute.TO_TANK, target, 3.0):
				return _fail(index, "diverter lever did not switch the water")
		"gate":
			if not await _hold_until(func() -> bool: return works.gate_timer > 0.0, target, 3.0):
				return _fail(index, "timer pad did not open the gate")
	return true


func _sluice_boards_ready() -> bool:
	var spec: Dictionary = works.shutter_specs[0]
	var cycle := fposmod(works.motion_time / float(spec["period"]) + float(spec["phase"]), 1.0)
	return cycle > 0.06 and cycle < 0.10


## Rolls toward `target` by tilting the board. `arrive` stops early when true.
func _roll_until(target: Vector3, arrive: Callable, timeout: float, need_reach := false) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		game.drag_tilt = _steer_to(target)
		await physics_frame
		elapsed += 1.0 / 60.0
		_observe()
		if arrive.call():
			return true
		if need_reach:
			var local: Vector3 = game.board.to_local(game.ball.global_position)
			if Vector2(local.x - target.x, local.z - target.z).length() < REACH and absf(local.y - (target.y + 0.33)) < 0.25:
				return true
	return false


func _hold_until(condition: Callable, hold_at: Vector3, timeout: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		game.drag_tilt = _steer_to(hold_at, true)
		await physics_frame
		elapsed += 1.0 / 60.0
		_observe()
		if condition.call():
			return true
	return false


func _steer_to(target: Vector3, gentle := false) -> Vector2:
	var board: AnimatableBody3D = game.board
	var local: Vector3 = board.to_local(game.ball.global_position)
	var velocity: Vector3 = board.global_basis.inverse() * game.ball.linear_velocity
	var error := Vector2(target.x - local.x, target.z - local.z)
	# Gentle mode damps harder: the board tilt lags the command, so a
	# stiff controller would orbit a small target instead of stopping on it.
	var damping := KD * (1.8 if gentle else 1.0)
	var command := error * KP - Vector2(velocity.x, velocity.z) * damping
	return command.limit_length(0.45 if gentle else 1.0)


func _observe() -> void:
	var local: Vector3 = game.board.to_local(game.ball.global_position)
	var cam: SmartCameraController = game.smart_camera
	if local.y > T2 and local.y < T2 + 0.8 and local.x > -0.6 and local.x < 2.6 and local.z > -2.2:
		if cam.mode == SmartCameraController.Mode.CHASE:
			seen_chase_on_tier2 = true
	if seen_chase_on_tier2 and local.y > T2 and local.y < T2 + 0.8 and local.x < -2.6 and cam.mode == SmartCameraController.Mode.OVERVIEW:
		seen_overview_on_tier2_west = true
	if sluice_snapshot.is_empty() and works.water_route == WatermillMechanisms.WaterRoute.TO_WHEEL and works.wheel.state == WaterWheel.State.WORKING and works.wheel.drive_factor() > 0.5:
		sluice_snapshot = {"wheel_state": works.wheel.state, "wheel_flux": works.wheel_flux(), "aqueduct_uv": works.surface_by_name("AqueductEast").uv_speeds().x, "lift_drive": works.lift.drive_factor}
	if divert_snapshot.is_empty() and works.water_route == WatermillMechanisms.WaterRoute.TO_TANK and works.tank_fill() > 0.5:
		divert_snapshot = {"wheel_flux": works.wheel_flux(), "divert_uv": works.surface_by_name("DivertFlume").uv_speeds().x, "aqueduct_uv": works.surface_by_name("AqueductEast").uv_speeds().x}
	if Engine.get_physics_frames() % 15 == 0:
		log_lines.append("t=%d cube=%s pos=%s v=%s wheel=%s lift=%d deck=%.2f mv=%s doorW=%s pontoon=%.2f cam=%s" % [Engine.get_physics_frames(), game.board.to_local(works.power_cube.global_position), local, game.ball.linear_velocity, works.wheel.state_name(), works.lift.current_floor, works.lift.deck_top(), works.lift.moving, works.lift.door_open("west"), works.pontoon_top(), cam.mode_name()])


func _fail(index: int, reason: String) -> bool:
	return _require(false, "route step %d: %s" % [index, reason])


func _has_collision(body: Node) -> bool:
	for child in body.get_children():
		if child is CollisionShape3D:
			return true
	return false


func _wait_physics(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("LEVEL 4 FAIL: " + message)
	quit(1)
	return false
