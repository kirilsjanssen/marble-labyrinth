class_name Level05Mechanisms
extends ClockworkMechanisms
## Level 05 machinery driving the finished GLB model (Level05Visuals) - no
## stand-in primitives for anything the art already contains.
##   * One conservative WaterNetwork: headgate, diverter, shutter, pool and
##     stream sluices, a ram pump and a mountain spring close the loop.
##   * Three WaterWheel models turn ONLY from the flux through their own
##     connection; every gear, shaft and the millstone follow at the exact
##     tooth ratios of the v2 engineering pass (bevel w_b = -w_a N_a / N_b).
##   * The east wheel's bevel train winds the three-stop VerticalLift: the
##     lift climbs only while that wheel works. The GLB cage and its doors
##     ride the physical deck.
##   * Crate on the plate unlocks the lift; the terrace crank (or the secret
##     alcove lever) releases its top stop; sluice boards follow their valves.
##   * Every water sheet, fall and spray reads its live flux (set_flow).

const WaterNetworkScript = preload("res://scripts/water/water_network.gd")
const WaterConnectionScript = preload("res://scripts/water/water_connection.gd")
const WaterValveScript = preload("res://scripts/water/water_valve.gd")
const WaterPumpScript = preload("res://scripts/water/water_pump.gd")
const WaterWheelScript = preload("res://scripts/mechanisms/water_wheel.gd")
const VerticalLiftScript = preload("res://scripts/mechanisms/vertical_lift.gd")
const PuzzleShapeBodyScript = preload("res://scripts/physics/puzzle_shape_body.gd")

const MARBLE_RADIUS := 0.33
const WATER_DENSITY := 1000.0
const WATER_DRAG := 3.2
const CURRENT_COUPLING := 2.0
const GATE_SPEED := 0.6
const LEVER_SPEED := 2.6
const CRANK_HOLD := 0.5

var visuals: Level05Visuals
var network: WaterNetwork
var connections: Dictionary = {}
var valves: Dictionary = {}
var valve_defaults: Dictionary = {}
var wheels: Dictionary = {}
var wheel_nodes: Dictionary = {}
var train: Array[Dictionary] = []
var lift: VerticalLift
var lift_chain: Node3D
var chain_rest := Transform3D.IDENTITY
var cube: PuzzleShapeBody
var crates: Array[PuzzleShapeBody] = []
var crate_specs: Array[Dictionary] = []
var cube_plate_area: Area3D
var gates: Dictionary = {}
var levers: Dictionary = {}
var valve_wheels: Dictionary = {}
var spinners: Dictionary = {}
var channel_volumes: Array = []
var water_specs: Dictionary = {}

var lift_powered := false
var upper_released := false
var crank_angle := 0.0
var crank_target := 0.0
var crank_hold := 0.0
var crank_done := false
var secrets_found: Dictionary = {}
var _wheel_states: Dictionary = {}


func setup_level05(level_config: Dictionary, materials: Dictionary, player_marble: RigidBody3D, world: Node3D, level_visuals: Level05Visuals) -> void:
	config = level_config
	palette = materials
	marble = player_marble
	visuals = level_visuals
	_build_network(config["water"])
	_build_wheels(config["wheels"], config["train"])
	_build_lift(config["lift"])
	_build_cube(config["cube"], world)
	for prop: Dictionary in config.get("props", []):
		_lash_prop(prop)
	_build_triggers()
	for gate_name: String in config.get("gates", {}):
		var gate_node := visuals.node(gate_name)
		if gate_node:
			gates[gate_name] = {"node": gate_node, "rest_y": gate_node.position.y, "spec": config["gates"][gate_name]}
	for wheel_name: String in config.get("valve_wheels", {}):
		var valve_node := visuals.node(wheel_name)
		if valve_node:
			valve_wheels[wheel_name] = {"node": valve_node, "rest": valve_node.basis, "valve": config["valve_wheels"][wheel_name], "angle": 0.0}
	for spec: Dictionary in config.get("extra_colliders", []):
		_add_box_collision(get_parent() as Node3D, spec["position"], spec["size"], 0.0, String(spec["name"]) + "Collision")
	channel_volumes.assign(config.get("channels", []))
	water_specs = config.get("water_bodies", {})
	tree_exiting.connect(_free_world_bodies)
	_restore_valves()
	_update_water_visuals()


func physics_step(delta: float) -> void:
	super.physics_step(delta)
	network.step(delta)
	for wheel_id: String in wheels:
		var wheel := wheels[wheel_id] as WaterWheel
		wheel.physics_step(delta, wheel_flux(wheel_id))
		if _wheel_states.get(wheel_id, -1) != wheel.state:
			_wheel_states[wheel_id] = wheel.state
			if wheel_id != "stream":
				state_changed.emit("%s WHEEL: %s" % ["LIFT" if wheel_id == "east" else "MILL", wheel.state_name()])
	_update_crank(delta)
	_apply_train()
	lift.drive_factor = (wheels["east"] as WaterWheel).drive_factor()
	lift.physics_step(delta)
	_update_chain()
	if not lift_powered and cube_plate_area:
		for body in cube_plate_area.get_overlapping_bodies():
			if body.is_in_group("puzzle_bodies") and _resting_on_plate(body as Node3D):
				activate_power()
				break
	_update_gates(delta)
	_update_levers(delta)
	_apply_channel_water()
	_update_water_visuals()


func reset_state() -> void:
	super.reset_state()
	network.reset()
	_restore_valves()
	for wheel_id: String in wheels:
		(wheels[wheel_id] as WaterWheel).reset_wheel()
		_wheel_states[wheel_id] = (wheels[wheel_id] as WaterWheel).state
	lift.reset_lift()
	lift.drive_factor = 0.0
	lift_powered = false
	upper_released = false
	crank_angle = 0.0
	crank_target = 0.0
	crank_hold = 0.0
	crank_done = false
	secrets_found.clear()
	spinners.clear()
	_apply_train()
	_update_chain()
	_reset_body(cube, config["cube"])
	for index in range(crates.size()):
		_reset_body(crates[index], crate_specs[index])
	for gate_name: String in gates:
		var gate: Dictionary = gates[gate_name]
		(gate["node"] as Node3D).position.y = _gate_target_y(gate)
	for lever_name: String in levers:
		var lever: Dictionary = levers[lever_name]
		lever["pulled"] = false
		lever["angle"] = 0.0
		(lever["node"] as Node3D).basis = lever["rest"]
	for wheel_name: String in valve_wheels:
		var valve_wheel: Dictionary = valve_wheels[wheel_name]
		valve_wheel["angle"] = 0.0
		(valve_wheel["node"] as Node3D).basis = valve_wheel["rest"]
	_update_water_visuals()


# --- Public state (HUD, tests) ------------------------------------------------

func wheel_flux(wheel_id: String) -> float:
	var spec: Dictionary = config["wheels"][wheel_id]
	return maxf(0.0, connection_flux(spec["flux"]))


func connection_flux(id: String) -> float:
	return (connections[id] as WaterConnection).last_flux


func valve_open(id: String) -> bool:
	return (valves[id] as WaterValve).openness > 0.5


func open_headgate() -> void:
	if valve_open("headgate"):
		return
	(valves["headgate"] as WaterValve).openness = 1.0
	_spin(config["start_ring"]["node"], 3.0)
	state_changed.emit("HEADGATE OPEN — the mill pond floods the aqueduct")


func toggle_valve(id: String, message_open: String, message_closed: String) -> void:
	var valve := valves[id] as WaterValve
	valve.openness = 0.0 if valve.openness > 0.5 else 1.0
	state_changed.emit(message_open if valve.openness > 0.5 else message_closed)


## Crate on the plate: the interlock lets the lift leave the ground floor.
func activate_power() -> void:
	if lift_powered:
		return
	lift_powered = true
	lift.unlock_floor(1)
	var plate := visuals.node(config["cube_plate"]["node"])
	if plate:
		plate.position.y -= 0.012
	state_changed.emit("CRATE ON THE PLATE — LIFT INTERLOCK RELEASED")


func release_upper_stop(source: String) -> void:
	if upper_released:
		return
	upper_released = true
	lift.unlock_floor(2)
	state_changed.emit("%s — LIFT CAN REACH THE MILLHOUSE TIER" % source)


func wheel_angle(wheel_id: String) -> float:
	return (wheels[wheel_id] as WaterWheel).wheel_angle


# --- Water ----------------------------------------------------------------------

func _build_network(water: Dictionary) -> void:
	network = WaterNetworkScript.new()
	network.name = "CascadeWaterNetwork"
	add_child(network)
	for reservoir: Dictionary in water["reservoirs"]:
		network.add_reservoir(StringName(reservoir["id"]), reservoir["capacity"], reservoir["volume"], reservoir["area"], reservoir["base"])
	for valve_id: String in water["valves"]:
		valves[valve_id] = WaterValveScript.new()
		valve_defaults[valve_id] = float(water["valves"][valve_id])
	for link: Dictionary in water["connections"]:
		var connection: WaterConnection = WaterConnectionScript.new()
		connection.reservoir_a = StringName(link["from"])
		connection.reservoir_b = StringName(link["to"])
		connection.conductance = float(link["conductance"])
		connection.max_flow = float(link["max_flow"])
		if link.has("valve"):
			connection.valve = valves[link["valve"]]
		if link.has("pump"):
			var pump: WaterPump = WaterPumpScript.new()
			pump.enabled = true
			pump.flow_rate = float(link["pump"])
			pump.max_head = 16.0
			connection.pump = pump
		network.add_connection(connection)
		connections[link["id"]] = connection


func _restore_valves() -> void:
	for valve_id: String in valves:
		(valves[valve_id] as WaterValve).openness = float(valve_defaults[valve_id])


func _update_water_visuals() -> void:
	if not visuals:
		return
	var nominal := float(config["water"].get("nominal_flux", 0.85))
	for body_name: String in water_specs:
		var spec: Dictionary = water_specs[body_name]
		var flux := 0.0
		for id: String in spec["flux"]:
			flux += absf(connection_flux(id))
		visuals.set_flow(body_name, flux / nominal * float(spec.get("gain", 1.0)))


func _apply_channel_water() -> void:
	var board := get_parent() as Node3D
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	for channel: Dictionary in channel_volumes:
		var at: Vector3 = channel["position"]
		var size: Vector3 = channel["size"]
		var fill := clampf(network.fill_ratio(StringName(channel["reservoir"])), 0.15, 1.0)
		var surface_y := at.y - size.y * 0.5 + fill * size.y
		var flow_local: Vector3 = channel["flow"]
		var flow_speed := absf(connection_flux(channel["flux"])) * float(channel.get("flux_to_speed", 0.6))
		var bodies: Array[RigidBody3D] = [marble, cube]
		bodies.append_array(crates)
		for body in bodies:
			if not is_instance_valid(body):
				continue
			var local := board.to_local(body.global_position)
			if absf(local.x - at.x) > size.x * 0.5 or absf(local.z - at.z) > size.z * 0.5:
				continue
			var radius := MARBLE_RADIUS if body == marble else 0.25
			var submerged := clampf(surface_y - (local.y - radius), 0.0, radius * 2.0)
			if submerged <= 0.0:
				continue
			var fraction := clampf(PI * submerged * submerged * (radius - submerged / 3.0) / (4.0 * PI * pow(radius, 3.0) / 3.0), 0.0, 1.0)
			var density := body.mass / (4.0 * PI * pow(radius, 3.0) / 3.0)
			var flow_world := board.global_basis * (flow_local.normalized() * flow_speed)
			var buoyancy := Vector3.UP * body.mass * gravity * minf(WATER_DENSITY / maxf(density, 1.0), 3.0) * fraction
			var drag := -(body.linear_velocity - flow_world) * body.mass * WATER_DRAG * fraction
			body.sleeping = false
			body.apply_central_force(buoyancy + drag + flow_world * body.mass * CURRENT_COUPLING * fraction)


# --- Wheels and gear trains --------------------------------------------------

func _build_wheels(wheel_specs: Dictionary, train_specs: Array) -> void:
	for wheel_id: String in wheel_specs:
		var spec: Dictionary = wheel_specs[wheel_id]
		var wheel: WaterWheel = WaterWheelScript.new()
		wheel.name = "WheelModel_" + wheel_id
		wheel.radius = float(spec.get("radius", 0.9))
		# The physics model only: the visible wheel is the GLB node below.
		add_child(wheel)
		wheels[wheel_id] = wheel
		var node := visuals.node(spec["node"])
		if node:
			wheel_nodes[wheel_id] = {"node": node, "rest": node.basis, "axis": (spec["axis"] as Vector3).normalized(), "sign": float(spec.get("sign", 1.0))}
		_wheel_states[wheel_id] = wheel.state
	for spec: Dictionary in train_specs:
		var node := visuals.node(spec["node"])
		if node == null:
			push_warning("Level05: train node %s missing" % spec["node"])
			continue
		var entry := {"node": node, "rest": node.transform, "axis": (spec["axis"] as Vector3).normalized(), "ratio": float(spec["ratio"]), "source": String(spec["source"])}
		if spec.has("pivot"):
			# Nodes whose origin is off their axis turn about the given pivot.
			entry["pivot"] = (spec["pivot"] as Vector3) - visuals.position
		train.append(entry)


func _driver_angle(source: String) -> float:
	if source == "crank":
		return crank_angle
	var wheel := wheels[source] as WaterWheel
	var info: Dictionary = wheel_nodes.get(source, {})
	return wheel.wheel_angle * float(info.get("sign", 1.0))


func _apply_train() -> void:
	for wheel_id: String in wheel_nodes:
		var info: Dictionary = wheel_nodes[wheel_id]
		(info["node"] as Node3D).basis = Basis(info["axis"], _driver_angle(wheel_id)) * (info["rest"] as Basis)
	for entry: Dictionary in train:
		var node := entry["node"] as Node3D
		var turn := Basis(entry["axis"], fposmod(_driver_angle(entry["source"]) * float(entry["ratio"]), TAU))
		var rest := entry["rest"] as Transform3D
		if entry.has("pivot"):
			var pivot: Vector3 = entry["pivot"]
			node.transform = Transform3D(turn, pivot - turn * pivot) * rest
		else:
			node.transform = Transform3D(turn * rest.basis, rest.origin)


# --- Lift -----------------------------------------------------------------------

func _build_lift(spec: Dictionary) -> void:
	var lift_config := spec.duplicate()
	var skin: Dictionary = spec.get("skin", {})
	var doors := {}
	for side: String in skin.get("doors", {}):
		var door := visuals.node(skin["doors"][side])
		if door:
			doors[side] = door
	lift_config["skin"] = {"deck": visuals.node(skin.get("deck", "")), "doors": doors}
	var riders: Array[RigidBody3D] = [marble]
	lift = VerticalLiftScript.new()
	lift.name = "MillLift"
	add_child(lift)
	lift.setup(lift_config, palette, riders)
	lift.requires_drive = true
	lift.drive_factor = 0.0
	lift.message.connect(func(text: String) -> void: state_changed.emit(text))
	lift_chain = visuals.node(skin.get("chain", ""))
	if lift_chain:
		chain_rest = lift_chain.transform


## The hoist chain hangs from the drum: it shortens as the cage climbs.
func _update_chain() -> void:
	if not lift_chain:
		return
	var rise := lift.deck_top() - float(config["lift"]["floors"][0])
	var bottom := 1.08
	var top := 4.58
	var scale_y := clampf((top - bottom - rise) / (top - bottom), 0.05, 1.0)
	var basis := chain_rest.basis.scaled(Vector3(1.0, scale_y, 1.0))
	lift_chain.transform = Transform3D(basis, chain_rest.origin + Vector3.UP * (top * (1.0 - scale_y)))


# --- Crate, plate and triggers ----------------------------------------------------

func _build_cube(spec: Dictionary, world: Node3D) -> void:
	cube = _dress_body(spec, world, "LiftPlateCrate")


## Cargo lashed to its deck: a box shape of the board itself, art untouched.
func _lash_prop(spec: Dictionary) -> void:
	var collision := _add_box_collision(get_parent() as Node3D, spec["start"], spec["size"], float(spec.get("yaw", 0.0)), String(spec["node"]) + "Collision")
	collision.set_meta("prop", true)


## A physical wooden crate (PuzzleShapeBody) wearing the GLB crate as its skin.
func _dress_body(spec: Dictionary, world: Node3D, body_name: String) -> PuzzleShapeBody:
	var skin := visuals.node(spec["node"])
	var body: PuzzleShapeBody = PuzzleShapeBodyScript.new()
	body.name = body_name
	body.body_shape = PuzzleShapeBody.BodyShape.CUBE
	body.material_id = &"wood"
	body.body_size = spec["size"]
	world.add_child(body)
	var shell := body.get_node_or_null("VisibleShape") as MeshInstance3D
	if shell and skin:
		shell.visible = false
	# Chamfered hull like the modelled crate: a sharp box snags on the internal
	# edge between two floor boxes (deck -> bridge seam); a sphere does not.
	var hull := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if hull:
		hull.shape = _chamfered_box(spec["size"], 0.04)
	_reset_body(body, spec)
	if skin:
		skin.reparent(body, false)
		skin.transform = Transform3D.IDENTITY
	return body


func _chamfered_box(size: Vector3, chamfer: float) -> ConvexPolygonShape3D:
	var h := size * 0.5
	var points := PackedVector3Array()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				points.append(Vector3(sx * (h.x - chamfer), sy * h.y, sz * h.z))
				points.append(Vector3(sx * h.x, sy * (h.y - chamfer), sz * h.z))
				points.append(Vector3(sx * h.x, sy * h.y, sz * (h.z - chamfer)))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape


func _reset_body(body: RigidBody3D, spec: Dictionary) -> void:
	if not is_instance_valid(body):
		return
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	var board := get_parent() as Node3D
	var start: Vector3 = spec["start"]
	body.global_transform = Transform3D(board.global_basis * Basis(Vector3.UP, float(spec.get("yaw", 0.0))), board.to_global(start))
	body.sleeping = false


func _resting_on_plate(body: Node3D) -> bool:
	var plate: Dictionary = config["cube_plate"]
	var plate_at: Vector3 = plate["position"]
	var local := (get_parent() as Node3D).to_local(body.global_position)
	return Vector2(local.x - plate_at.x, local.z - plate_at.z).length() <= float(plate["radius"]) + 0.08 and absf(local.y - plate_at.y) < 0.6


func _build_triggers() -> void:
	var plate: Dictionary = config["cube_plate"]
	cube_plate_area = _create_area("CubePlateTrigger", plate["position"] + Vector3.UP * 0.25, Vector3(float(plate["radius"]) * 1.6, 0.46, float(plate["radius"]) * 1.6))
	_trigger(config["start_ring"], "StartRingTrigger", func() -> void: open_headgate())
	_lever(config["sluice_lever"], "SluiceLeverTrigger", func() -> void:
		toggle_valve("stream_sluice", "STREAM SLUICE OPEN — the spring turns the stream wheel", "STREAM SLUICE CLOSED"))
	_trigger(config["diverter"], "DiverterTrigger", func() -> void:
		toggle_valve("diverter", "SPILL NOTCHES OPEN — the mill wheel runs again", "DIVERTER CLOSED — the channel backs up, more water for the lift wheel"))
	_trigger(config["secret_ring"], "SecretRingTrigger", func() -> void:
		_spin(config["secret_ring"]["node"], 2.5)
		if not secrets_found.has("corridor"):
			secrets_found["corridor"] = true
			state_changed.emit("SECRET CORRIDOR — follow the lanterns to the alcove"))
	_lever(config["secret_lever"], "SecretLeverTrigger", func() -> void:
		secrets_found["alcove"] = true
		release_upper_stop("SECRET LEVER"))
	var crank: Dictionary = config["crank"]
	var radius := float(crank["radius"])
	_create_area("CrankTrigger", crank["position"] + Vector3.UP * 0.25, Vector3(radius * 1.6, 0.5, radius * 1.6))


func _trigger(spec: Dictionary, trigger_name: String, action: Callable) -> Area3D:
	var radius := float(spec["radius"])
	var area := _create_area(trigger_name, spec["position"] + Vector3.UP * 0.25, Vector3(radius * 1.6, 0.5, radius * 1.6))
	area.body_entered.connect(func(body: Node3D) -> void:
		if body == marble:
			action.call()
	)
	return area


func _lever(spec: Dictionary, trigger_name: String, action: Callable) -> void:
	var node := visuals.node(spec["node"])
	if node:
		levers[spec["node"]] = {"node": node, "rest": node.basis, "pulled": false, "angle": 0.0}
	_trigger(spec, trigger_name, func() -> void:
		if levers.has(spec["node"]):
			levers[spec["node"]]["pulled"] = not levers[spec["node"]]["pulled"]
		action.call()
	)


func _update_crank(delta: float) -> void:
	var crank: Dictionary = config["crank"]
	if not crank_done:
		var local := (get_parent() as Node3D).to_local(marble.global_position)
		var at: Vector3 = crank["position"]
		var on_pad := Vector2(local.x - at.x, local.z - at.z).length() < float(crank["radius"]) and absf(local.y - at.y - MARBLE_RADIUS) < 0.3
		crank_hold = crank_hold + delta if on_pad else 0.0
		if crank_hold >= CRANK_HOLD and crank_target == 0.0:
			crank_target = TAU * float(crank["turns"])
			state_changed.emit("TERRACE CRANK TURNING — the pillar gear winds the release cable")
	if crank_angle < crank_target:
		crank_angle = minf(crank_target, crank_angle + crank_target / float(crank["seconds"]) * delta)
		if crank_angle >= crank_target and not crank_done:
			crank_done = true
			release_upper_stop("TERRACE CRANK WOUND")


func _spin(node_name: String, seconds: float) -> void:
	var node := visuals.node(node_name)
	if node:
		spinners[node_name] = {"node": node, "left": seconds}


# --- Gates, levers, valve wheels ------------------------------------------------

func _gate_target_y(gate: Dictionary) -> float:
	var spec: Dictionary = gate["spec"]
	var open := valve_open(spec["valve"])
	return float(gate["rest_y"]) + (float(spec["lift"]) if open else 0.0)


func _update_gates(delta: float) -> void:
	for gate_name: String in gates:
		var gate: Dictionary = gates[gate_name]
		var node := gate["node"] as Node3D
		node.position.y = move_toward(node.position.y, _gate_target_y(gate), GATE_SPEED * delta)
	for wheel_name: String in valve_wheels:
		var valve_wheel: Dictionary = valve_wheels[wheel_name]
		# Two turns of the handwheel between shut and fully open.
		var target := TAU * 2.0 * (valves[valve_wheel["valve"]] as WaterValve).openness
		valve_wheel["angle"] = move_toward(float(valve_wheel["angle"]), target, TAU * delta)
		(valve_wheel["node"] as Node3D).basis = Basis(Vector3.UP, float(valve_wheel["angle"])) * (valve_wheel["rest"] as Basis)
	for node_name: String in spinners.keys():
		var spinner: Dictionary = spinners[node_name]
		spinner["left"] = float(spinner["left"]) - delta
		(spinner["node"] as Node3D).rotate_y(4.0 * delta)
		if float(spinner["left"]) <= 0.0:
			spinners.erase(node_name)


func _update_levers(delta: float) -> void:
	for lever_name: String in levers:
		var lever: Dictionary = levers[lever_name]
		var target := -0.75 if lever["pulled"] else 0.0
		lever["angle"] = move_toward(float(lever["angle"]), target, LEVER_SPEED * delta)
		(lever["node"] as Node3D).basis = Basis(Vector3.RIGHT, float(lever["angle"])) * (lever["rest"] as Basis)


func _free_world_bodies() -> void:
	if is_instance_valid(cube):
		cube.queue_free()
	for crate in crates:
		if is_instance_valid(crate):
			crate.queue_free()
