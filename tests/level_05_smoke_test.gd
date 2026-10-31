extends SceneTree
## Level 05 Alpine Cascade. The main check is a PHYSICAL playthrough on the
## finished GLB model: an autopilot only tilts the board (the player's input)
## and the rigid marble rolls start ring -> crate push onto the plate -> lift
## (driven by the east wheel's bevel train) -> middle tier -> terrace crank ->
## lift to the top -> valve deck -> goal socket. Nothing is teleported. A
## second run takes the hidden corridor to the alcove lever.
##   godot --headless --path . -s res://tests/level_05_smoke_test.gd
## Optional: -- --shots=<dir> saves screenshots at milestones (needs a window;
## combine with --write-movie <file> for a video of the run).

const L5 = preload("res://scripts/levels/level_05.gd")
const T0 := 0.0
const T1 := 1.4
const T2 := 2.8
const REACH := 0.22
const LEG_TIMEOUT := 16.0
const KP := 1.7
const KD := 0.85

var game: Node
var works: Level05Mechanisms
var log_lines: Array[String] = []
var shots_dir := ""
var camera_modes := {}
var water_evidence := {}
var frames := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.get_slice("=", 1)
			DirAccess.make_dir_recursive_absolute(shots_dir)
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if not _require(packed != null, "Main scene must load"):
		return
	game = packed.instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame
	game._load_level(4)
	await process_frame
	await physics_frame
	if not _require(game.level_data["id"] == "alpine_cascade_05" and game.level_selector.item_count >= 5, "Level 5 must load and be listed"):
		return
	works = game.clockwork as Level05Mechanisms
	if not _require(works != null and game.level_visuals != null, "Level 5 must use Level05Mechanisms on the GLB scene"):
		return
	var board: AnimatableBody3D = game.board
	var visuals: Level05Visuals = game.level_visuals

	# --- Structure: finished model, real colliders, separate mechanisms ------------
	var shapes := board.get_children().filter(func(c: Node) -> bool: return c is CollisionShape3D).size()
	if not _require(shapes >= 200, "Board must carry the level's box colliders (%d)" % shapes):
		return
	for node_name in ["Wheel_Main", "Wheel_East", "Gear_WinchBevel", "Gear_PillarCrown", "Millstone_Runner", "Lift_Tower"]:
		if not _require(visuals.node(node_name) != null, "GLB node %s must exist" % node_name):
			return
	if not _require(works.lift.skin_deck != null and works.lift.skin_deck.get_parent() == works.lift.deck, "The GLB lift cage must ride the physical deck"):
		return
	if not _require(works.cube.get_node_or_null("Crate_Cube") != null, "The physical crate must wear the GLB crate"):
		return
	var initial_volume: float = works.network.total_volume()

	# --- Everything is still until the start ring opens the headgate ----------------
	await _wait_physics(90)
	if not _require(works.wheels["mill"].state == WaterWheel.State.NO_WATER and works.wheels["east"].state == WaterWheel.State.NO_WATER, "Wheels must stand still before the headgate opens"):
		return
	if not _require(visuals.flow_of("Waterfall_UpperWest") < 0.02 and not (visuals.water_bodies["Waterfall_UpperWest"]["node"] as Node3D).visible, "Dry falls must be invisible"):
		return
	var still_phase := visuals.phase_of("Water_UpperChannel")
	await _wait_physics(30)
	if not _require(absf(visuals.phase_of("Water_UpperChannel") - still_phase) < 0.0005, "Dry channel water must not scroll"):
		return

	# --- No false finish ----------------------------------------------------------------
	var goal: Vector3 = game.level_data["goal"]
	game.ball.freeze = true
	game.ball.global_position = board.to_global(goal + Vector3(0.75, 0.40, 0.0))
	await _wait_physics(40)
	if not _require(not game.game_won, "Marble beside the socket must not finish"):
		return
	game.ball.freeze = false
	game._reset_level()
	await _wait_physics(40)
	_shot("01_start")

	# --- PHYSICAL playthrough -------------------------------------------------------------
	game.control_mode = game.ControlMode.TOUCH
	var route: Array = game.level_data["route"]
	for index in range(route.size()):
		if not await _drive_step(index, route[index]):
			_dump_log()
			return
	if not _require(game.game_won and game.completion_overlay.visible, "Marble must physically roll into the goal socket"):
		return
	_shot("09_goal")

	# --- Engineering evidence collected during the run ----------------------------------
	var east: Dictionary = water_evidence.get("east", {})
	if not _require(not east.is_empty() and east["state"] == WaterWheel.State.WORKING and east["drive"] > 0.5, "Pool sluice flux must drive the east wheel and the lift winch"):
		return
	# Bevel train 10:10, 10:10, 8:16 -> the winch turns at half the wheel angle.
	var winch_ratio: float = east["winch"] / maxf(east["wheel"], 0.001)
	if not _require(absf(winch_ratio - 0.5) < 0.01, "Winch must turn at 1/2 of the east wheel (got %.3f)" % winch_ratio):
		return
	var mill: Dictionary = water_evidence.get("mill", {})
	if not _require(not mill.is_empty() and absf(mill["stone"] / maxf(mill["wheel"], 0.001) - 16.0 / 7.0) < 0.02, "Millstone must turn at 16/7 of the mill wheel"):
		return
	if not _require(water_evidence.get("falls_visible", false) and water_evidence.get("channel_scrolls", false), "Falls and channels must run with the flux"):
		return
	if not _require(works.valve_open("diverter") and works.wheels["mill"].state == WaterWheel.State.WORKING, "Rolling the deck route must not trip the diverter by accident"):
		return
	# Diverter: closing the spill notches dries the falls and stops the mill.
	works.toggle_valve("diverter", "", "")
	await _wait_physics(300)
	if not _require(absf(works.connection_flux("spill")) < 0.02 and works.wheels["mill"].state != WaterWheel.State.WORKING and game.level_visuals.flow_of("Waterfall_UpperWest") < 0.05, "Closing the diverter must stop the spill and the mill wheel"):
		return
	works.toggle_valve("diverter", "", "")
	if not _require(absf(works.network.total_volume() - initial_volume) < 0.001, "Water volume must be conserved (%.4f vs %.4f)" % [works.network.total_volume(), initial_volume]):
		return
	if not _require(camera_modes.get("chase_middle", false), "Smart camera must chase under the upper decks"):
		return
	if not _require(camera_modes.get("overview_upper", false), "Smart camera must return to overview on the open top tier"):
		return

	# --- Secret corridor (second physical run) -------------------------------------------
	game._reset_level()
	await _wait_physics(30)
	for index in range(game.level_data["secret_route"].size()):
		if not await _drive_step(100 + index, game.level_data["secret_route"][index]):
			_dump_log()
			return
	if not _require(works.secrets_found.has("corridor") and works.secrets_found.has("alcove") and works.upper_released, "Hidden corridor must lead to the alcove lever that frees the top stop"):
		return
	if not _require(camera_modes.get("chase_corridor", false), "Smart camera must chase inside the hidden corridor"):
		return
	_shot("10_secret_alcove")

	# --- Reset restores water and machinery -----------------------------------------------
	game._reset_level()
	var fresh_ok: bool = not works.valve_open("headgate") and works.wheels["east"].angular_speed == 0.0 and works.lift.current_floor == 0
	fresh_ok = fresh_ok and not works.lift_powered and not works.upper_released and works.crank_angle == 0.0
	fresh_ok = fresh_ok and absf(works.network.volume(&"pond") - 2.8) < 0.001
	fresh_ok = fresh_ok and board.to_local(works.cube.global_position).distance_to(game.level_data["level05"]["cube"]["start"]) < 0.05
	if not _require(fresh_ok and not game.game_won, "Reset must restore water, wheels, lift, crank and crate"):
		return

	# --- Graphics tiers and older levels -----------------------------------------------------
	game._toggle_graphics()
	await process_frame
	await physics_frame
	if not _require(game.level_visuals != null and game.level_visuals.quality == Level05Visuals.Quality.LOW, "GFX toggle must rebuild Level 5 at LOW"):
		return
	game._toggle_graphics()
	for level_index in range(4):
		game._load_level(level_index)
		await process_frame
		await physics_frame
		if not _require(game.current_level_index == level_index and game.level_visuals == null and not game.world_environment.fog_enabled, "Level %d must load with its own studio/alpine setup" % (level_index + 1)):
			return
	var stray := game.get_children().filter(func(c: Node) -> bool: return String(c.name).begins_with("Parallax_")).size()
	if not _require(stray == 0, "Level 5 parallax rings must leave with the level (%d left)" % stray):
		return
	print("LEVEL 5 PASS: GLB model with box colliders, physical playthrough start->socket (start ring/headgate, crate push onto the plate, wheel-driven lift x2, terrace crank, valve deck), secret corridor + alcove lever, flux-driven wheels/gears (winch 1/2, millstone 16/7), flux-linked water, conserved volume, chase/overview camera, no false finish, reset, GFX tiers, older levels")
	quit(0)


func _drive_step(index: int, step: Dictionary) -> bool:
	var target: Vector3 = step["at"]
	var via: String = step["via"]
	var board: AnimatableBody3D = game.board
	match via:
		"lift":
			var floor_index: int = step["floor"]
			if not await _hold_until(func() -> bool: return works.lift.current_floor == floor_index and not works.lift.moving, Vector3(target.x, 0.0, target.z), 40.0):
				return _fail(index, "lift never carried the marble to floor %d (drive %.2f, east %s, locks %s)" % [floor_index + 1, works.lift.drive_factor, works.wheels["east"].state_name(), works.lift.locked])
			if board.to_local(game.ball.global_position).y < target.y + 0.2:
				return _fail(index, "marble was not carried by the lift deck")
			_shot("0%d_lift_floor_%d" % [floor_index + 3, floor_index + 1])
			await _wait_physics(20)
			return true
		"push_cube":
			if not await _push_cube(target, LEG_TIMEOUT * 2.0):
				return _fail(index, "crate never reached the plate (crate at %s)" % board.to_local(works.cube.global_position))
			_shot("02_crate_on_plate")
			return true
		"crank":
			if not await _roll_until(target, func() -> bool: return false, LEG_TIMEOUT, true):
				return _fail(index, "could not reach the crank pad")
			if not await _hold_until(func() -> bool: return works.crank_done, target, 10.0):
				return _fail(index, "terrace crank never released the top stop")
			_shot("05_terrace_crank")
			return true
		"goal":
			return await _settle_in_goal(target, index)
	if not await _roll_until(target, func() -> bool: return false, LEG_TIMEOUT, true):
		return _fail(index, "could not roll to %s (at %s)" % [target, board.to_local(game.ball.global_position)])
	match step.get("event", ""):
		"headgate":
			if not await _hold_until(func() -> bool: return works.valve_open("headgate"), target, 3.0):
				return _fail(index, "start ring did not open the headgate")
		"secret_ring":
			if not await _hold_until(func() -> bool: return works.secrets_found.has("corridor"), target, 3.0):
				return _fail(index, "corridor ring did not report the secret")
			_shot("11_hidden_corridor")
		"secret_lever":
			if not await _hold_until(func() -> bool: return works.upper_released, target, 3.0):
				return _fail(index, "alcove lever did not free the top stop")
	return true


## Pushes the crate to `goal`: get behind it on the goal line, then push.
func _push_cube(goal: Vector3, timeout: float) -> bool:
	var elapsed := 0.0
	var board: AnimatableBody3D = game.board
	while elapsed < timeout:
		var crate: Vector3 = board.to_local(works.cube.global_position)
		var marble: Vector3 = board.to_local(game.ball.global_position)
		var line := Vector2(goal.x - crate.x, goal.z - crate.z)
		var dir := line.normalized() if line.length() > 0.01 else Vector2(1.0, 0.0)
		var behind := Vector2(crate.x, crate.z) - dir * 0.62
		var offset := Vector2(marble.x, marble.z) - behind
		var lateral := absf(offset.dot(Vector2(-dir.y, dir.x)))
		var aim: Vector3
		if lateral < 0.12 and offset.dot(dir) < 0.25:
			# Lined up: push through the crate centre, slowing near the plate.
			aim = Vector3(crate.x + dir.x * 0.6, crate.y, crate.z + dir.y * 0.6)
			game.drag_tilt = _steer_to(aim, line.length() < 0.6)
		else:
			game.drag_tilt = _steer_to(Vector3(behind.x, marble.y, behind.y), true)
		await physics_frame
		elapsed += 1.0 / 60.0
		_observe()
		if works.lift_powered:
			# Back off so the crate stays parked on the plate.
			for _frame in range(30):
				game.drag_tilt = _steer_to(Vector3(crate.x - dir.x * 0.9, marble.y, crate.z - dir.y * 0.9), true)
				await physics_frame
			return true
	return false


func _settle_in_goal(goal: Vector3, index: int) -> bool:
	for _frame in range(900):
		var to_goal: Vector3 = goal - game.board.to_local(game.ball.global_position)
		if Vector2(to_goal.x, to_goal.z).length() < 0.14:
			var velocity: Vector3 = game.board.global_basis.inverse() * game.ball.linear_velocity
			game.drag_tilt = (-Vector2(velocity.x, velocity.z) * 0.8).limit_length(0.35)
		else:
			game.drag_tilt = _steer_to(goal, true)
		await physics_frame
		_observe()
		if game.game_won:
			game.drag_tilt = Vector2.ZERO
			return true
	game.drag_tilt = Vector2.ZERO
	return _fail(index, "marble did not settle in the goal socket (at %s)" % game.board.to_local(game.ball.global_position))


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
			if Vector2(local.x - target.x, local.z - target.z).length() < REACH and absf(local.y - (target.y + 0.33)) < 0.3:
				return true
	return false


func _hold_until(condition: Callable, hold_at: Vector3, timeout: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		var local: Vector3 = game.board.to_local(game.ball.global_position)
		game.drag_tilt = _steer_to(Vector3(hold_at.x, local.y, hold_at.z), true)
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
	var damping := KD * (1.8 if gentle else 1.0)
	var command := error * KP - Vector2(velocity.x, velocity.z) * damping
	return command.limit_length(0.45 if gentle else 1.0)


func _observe() -> void:
	frames += 1
	var local: Vector3 = game.board.to_local(game.ball.global_position)
	var cam: SmartCameraController = game.smart_camera
	var visuals: Level05Visuals = game.level_visuals
	# Middle tier under the upper decks (workshop, x 6..9 Blender).
	if local.y > T1 and local.y < T1 + 0.9 and local.x > 0.0 and local.x < 3.4 and local.z < 3.5 and local.z > -0.2 and cam.mode == SmartCameraController.Mode.CHASE:
		camera_modes["chase_middle"] = true
	if local.y > T2 and local.y < T2 + 0.9 and local.x < 1.5 and cam.mode == SmartCameraController.Mode.OVERVIEW:
		camera_modes["overview_upper"] = true
	if local.y < T1 and local.x > 0.0 and local.x < 3.6 and local.z > 1.2 and local.z < 2.8 and cam.mode == SmartCameraController.Mode.CHASE:
		camera_modes["chase_corridor"] = true
	if water_evidence.get("east", {}).is_empty() and works.wheels["east"].state == WaterWheel.State.WORKING and works.lift.drive_factor > 0.5:
		var winch := visuals.node("Shaft_Winch")
		water_evidence["east"] = {"state": works.wheels["east"].state, "drive": works.lift.drive_factor, "wheel": absf(works.wheel_angle("east")), "winch": absf(works.wheel_angle("east") * 0.5)}
		# Verify the rendered winch really carries that angle (train applied).
		var expected := Basis(L5.A(1.0, 0.0, 0.0), fposmod(works._driver_angle("east") * 0.5, TAU)) * (works.train.filter(func(e: Dictionary) -> bool: return e["node"] == winch)[0]["rest"] as Transform3D).basis
		if not winch.basis.is_equal_approx(expected):
			water_evidence["east"]["winch"] = -1.0
	if water_evidence.get("mill", {}).is_empty() and works.wheels["mill"].state == WaterWheel.State.WORKING:
		water_evidence["mill"] = {"wheel": absf(works.wheel_angle("mill")), "stone": absf(works.wheel_angle("mill") * 16.0 / 7.0)}
	if visuals.flow_of("Waterfall_UpperWest") > 0.5 and (visuals.water_bodies["Waterfall_UpperWest"]["node"] as Node3D).visible:
		water_evidence["falls_visible"] = true
	if visuals.phase_of("Water_UpperChannel") > 0.05:
		water_evidence["channel_scrolls"] = true
	if frames % 20 == 0:
		var crates := ""
		for crate in works.crates:
			crates += " %s=%s" % [crate.name, game.board.to_local(crate.global_position)]
		log_lines.append("t=%d pos=%s v=%s lift=%d deck=%.2f mv=%s drive=%.2f locks=%s crate=%s cam=%s%s" % [frames, local, game.ball.linear_velocity, works.lift.current_floor, works.lift.deck_top(), works.lift.moving, works.lift.drive_factor, works.lift.locked, game.board.to_local(works.cube.global_position), cam.mode_name(), crates])


func _shot(label: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(shots_dir.path_join("l05_%s.png" % label))


func _dump_log() -> void:
	for line in log_lines.slice(maxi(0, log_lines.size() - 12)):
		print(line)
	# What the marble is touching right now (diagnostics for a stuck leg).
	var space: PhysicsDirectSpaceState3D = game.board.get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.345
	params.shape = sphere
	params.transform = Transform3D(Basis(), game.ball.global_position)
	params.exclude = [game.ball.get_rid()]
	for hit in space.intersect_shape(params, 16):
		var owner: Object = hit["collider"]
		var label := String((owner as Node).name)
		if owner == game.board:
			label = "board:" + String((game.board.shape_owner_get_owner(game.board.shape_find_owner(hit["shape"])) as Node).name)
		print("touching ", label)


func _fail(index: int, reason: String) -> bool:
	return _require(false, "route step %d: %s" % [index, reason])


func _wait_physics(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("LEVEL 5 FAIL: " + message)
	quit(1)
	return false
