class_name WatermillMechanisms
extends LiftworksMechanisms
## Level 04 machinery, all driven by one conservative WaterNetwork:
##   cistern --sluice--> race --wheel buckets--> stream --ram pump--> cistern
##   cistern --diverter--> float tank --drain--> stream
## The wheel turns only from the simulated flux through it. Its gear train
## winds the lift winch, so the lift climbs only while the wheel works. The
## float pontoon rides the tank's water level. Visual water reads the same fluxes.

const WaterNetworkScript = preload("res://scripts/water/water_network.gd")
const WaterConnectionScript = preload("res://scripts/water/water_connection.gd")
const WaterValveScript = preload("res://scripts/water/water_valve.gd")
const WaterPumpScript = preload("res://scripts/water/water_pump.gd")
const WaterWheelScript = preload("res://scripts/mechanisms/water_wheel.gd")
const FlowWaterSurfaceScript = preload("res://scripts/water/flow_water_surface.gd")

const MARBLE_RADIUS := 0.33
const WATER_DENSITY := 1000.0
const WATER_DRAG := 3.2
const CURRENT_COUPLING := 2.0
const PONTOON_SPEED := 0.5
const FOAM_TEXTURE := "res://assets/luma/level04/water_foam.jpg"

enum WaterRoute { CLOSED, TO_WHEEL, TO_TANK }

var network: WaterNetwork
var connections: Dictionary = {}
var sluice_valve: WaterValve
var divert_valve: WaterValve
var drain_valve: WaterValve
var ram_pump: WaterPump
var wheel: WaterWheel
var pontoon: AnimatableBody3D
var mill_gate: AnimatableBody3D
var mill_gate_closed_y := 0.0
var water_surfaces: Array[FlowWaterSurface] = []
var water_surface_specs: Array[Dictionary] = []
var channel_volumes: Array[Dictionary] = []
var sluice_handle: Node3D
var divert_handle: Node3D

var water_route := WaterRoute.CLOSED
var pontoon_released := false
var pontoon_rider_seconds := 0.0
var secrets_found: Dictionary = {}
var _last_wheel_state := -1


func setup_watermill(watermill_config: Dictionary, materials: Dictionary, player_marble: RigidBody3D, world: Node3D) -> void:
	config = watermill_config
	palette = materials
	marble = player_marble
	_build_network(config["water"])
	_build_gears(config.get("gears", []))
	_build_gate(config["gate"], config["gate_pad"])
	for rotor_spec: Dictionary in config.get("rotors", []):
		_build_rotor(rotor_spec)
	for shutter_spec: Dictionary in config.get("shutters", []):
		_build_shutter(shutter_spec)

	var riders: Array[RigidBody3D] = [marble]
	lift = VerticalLiftScript.new()
	lift.name = "MillLift"
	add_child(lift)
	lift.setup(config["lift"], palette, riders)
	lift.requires_drive = true
	lift.drive_factor = 0.0
	lift.message.connect(func(text: String) -> void: state_changed.emit(text))

	_build_wheel(config["wheel"], config["transmission"])
	_build_pontoon(config["pontoon"])
	_build_mill_gate(config["mill_gate"])
	_build_power_plate(config["power_plate"])
	_build_power_cube(config["power_cube"], world)
	sluice_handle = _build_lever(config["sluice_lever"], "SluiceLever", func() -> void: set_water_route(WaterRoute.TO_WHEEL))
	divert_handle = _build_lever(config["divert_lever"], "DiverterLever", func() -> void: set_water_route(WaterRoute.TO_TANK))
	for secret: Dictionary in config.get("secrets", []):
		_build_secret(secret)
	for surface_spec: Dictionary in config.get("water_surfaces", []):
		_build_water_surface(surface_spec)
	channel_volumes.assign(config.get("channels", []))
	_build_mill_structures(config.get("structures", []))
	tree_exiting.connect(_free_world_bodies)
	set_water_route(WaterRoute.CLOSED, false)


func physics_step(delta: float) -> void:
	network.step(delta)
	wheel.physics_step(delta, wheel_flux())
	if wheel.state != _last_wheel_state:
		_last_wheel_state = wheel.state
		state_changed.emit("MILL WHEEL: %s" % wheel.state_name())
	lift.drive_factor = wheel.drive_factor()
	super.physics_step(delta)
	_update_pontoon(delta)
	if mill_gate:
		var target_y := mill_gate_closed_y - (mill_gate_size().y + 0.02) if lift_powered else mill_gate_closed_y
		mill_gate.position.y = move_toward(mill_gate.position.y, target_y, 1.4 * delta)
	if sluice_handle:
		sluice_handle.rotation.z = move_toward(sluice_handle.rotation.z, -0.72 if water_route == WaterRoute.TO_WHEEL else 0.48, 2.6 * delta)
	if divert_handle:
		divert_handle.rotation.z = move_toward(divert_handle.rotation.z, -0.72 if water_route == WaterRoute.TO_TANK else 0.48, 2.6 * delta)
	_apply_channel_water(delta)
	_update_water_visuals()


func reset_state() -> void:
	super.reset_state()
	network.reset()
	set_water_route(WaterRoute.CLOSED, false)
	wheel.reset_wheel()
	_last_wheel_state = wheel.state
	lift.drive_factor = 0.0
	pontoon_released = false
	pontoon_rider_seconds = 0.0
	pontoon.position.y = _pontoon_low_y()
	if mill_gate:
		mill_gate.position.y = mill_gate_closed_y
	secrets_found.clear()
	for surface in water_surfaces:
		surface.set_flux(0.0)
		surface.visual_speed = 0.0
	_update_water_visuals()


## The cube on the plate opens the mill gate in front of the lift; the lift
## itself is powered by the wheel, not by the plate.
func activate_power() -> void:
	if lift_powered:
		return
	lift_powered = true
	_set_glow(power_plate_glow, palette["goal"])
	state_changed.emit("CUBE ON THE PLATE — MILL GATE OPENS TO THE LIFT")


func set_water_route(route: WaterRoute, announce := true) -> void:
	water_route = route
	sluice_valve.openness = 1.0 if route == WaterRoute.TO_WHEEL else 0.0
	divert_valve.openness = 1.0 if route == WaterRoute.TO_TANK else 0.0
	# The float tank drains back to the stream unless the diverter fills it.
	drain_valve.openness = 0.0 if route == WaterRoute.TO_TANK else 1.0
	if not announce:
		return
	match route:
		WaterRoute.TO_WHEEL:
			state_changed.emit("SLUICE OPEN — water runs onto the mill wheel")
		WaterRoute.TO_TANK:
			state_changed.emit("WATER DIVERTED — the float tank fills, the wheel slows")


func wheel_flux() -> float:
	return maxf(0.0, (connections["wheel"] as WaterConnection).last_flux)


func connection_flux(id: String) -> float:
	return (connections[id] as WaterConnection).last_flux


func tank_fill() -> float:
	return network.fill_ratio(&"tank")


func mill_gate_size() -> Vector3:
	return config["mill_gate"]["size"]


func pontoon_top() -> float:
	return pontoon.position.y + (config["pontoon"]["size"] as Vector3).y * 0.5


func surface_by_name(surface_name: String) -> FlowWaterSurface:
	for surface in water_surfaces:
		if surface.name == surface_name:
			return surface
	return null


# --- Water network -------------------------------------------------------------

func _build_network(water: Dictionary) -> void:
	network = WaterNetworkScript.new()
	network.name = "MillWaterNetwork"
	add_child(network)
	for reservoir: Dictionary in water["reservoirs"]:
		network.add_reservoir(StringName(reservoir["id"]), reservoir["capacity"], reservoir["volume"], reservoir["area"], reservoir["base"])
	sluice_valve = WaterValveScript.new()
	divert_valve = WaterValveScript.new()
	drain_valve = WaterValveScript.new()
	ram_pump = WaterPumpScript.new()
	ram_pump.enabled = true
	ram_pump.flow_rate = float(water["pump_flow"])
	ram_pump.max_head = 8.0
	var valves := {"sluice": sluice_valve, "divert": divert_valve, "drain": drain_valve}
	for link: Dictionary in water["connections"]:
		var connection: WaterConnection = WaterConnectionScript.new()
		connection.reservoir_a = StringName(link["from"])
		connection.reservoir_b = StringName(link["to"])
		connection.conductance = float(link["conductance"])
		connection.max_flow = float(link["max_flow"])
		if link.has("valve"):
			connection.valve = valves[link["valve"]]
		if link.get("pump", false):
			connection.pump = ram_pump
		network.add_connection(connection)
		connections[link["id"]] = connection


func _apply_channel_water(_delta: float) -> void:
	var board := get_parent() as Node3D
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	for channel: Dictionary in channel_volumes:
		var at: Vector3 = channel["position"]
		var size: Vector3 = channel["size"]
		var surface_y := _channel_surface_y(channel)
		var flow_local: Vector3 = channel["flow"]
		var flow_speed := absf(connection_flux(channel["flux"])) * float(channel.get("flux_to_speed", 0.6))
		for body: RigidBody3D in [marble, power_cube]:
			if not is_instance_valid(body):
				continue
			var local := board.to_local(body.global_position)
			if absf(local.x - at.x) > size.x * 0.5 or absf(local.z - at.z) > size.z * 0.5:
				continue
			var radius := MARBLE_RADIUS if body == marble else 0.3
			var submerged := clampf(surface_y - (local.y - radius), 0.0, radius * 2.0)
			if submerged <= 0.0:
				continue
			var fraction := clampf(PI * submerged * submerged * (radius - submerged / 3.0) / (4.0 * PI * pow(radius, 3.0) / 3.0), 0.0, 1.0)
			var density := body.mass / (4.0 * PI * pow(radius, 3.0) / 3.0)
			var flow_world := board.global_basis * (flow_local.normalized() * flow_speed)
			var buoyancy := Vector3.UP * body.mass * gravity * (WATER_DENSITY / maxf(density, 1.0)) * fraction
			var drag := -(body.linear_velocity - flow_world) * body.mass * WATER_DRAG * fraction
			body.sleeping = false
			body.apply_central_force(buoyancy + drag + flow_world * body.mass * CURRENT_COUPLING * fraction)


func _channel_surface_y(channel: Dictionary) -> float:
	var at: Vector3 = channel["position"]
	var size: Vector3 = channel["size"]
	var fill := clampf(network.fill_ratio(StringName(channel["reservoir"])) * float(channel.get("fill_gain", 1.0)), 0.15, 1.0)
	return at.y - size.y * 0.5 + fill * size.y


# --- Wheel and transmission ------------------------------------------------------

func _build_wheel(spec: Dictionary, transmission: Dictionary) -> void:
	wheel = WaterWheelScript.new()
	wheel.name = "MillWheel"
	wheel.radius = float(spec["radius"])
	wheel.width = float(spec["width"])
	wheel.position = spec["position"]
	add_child(wheel)
	wheel.build(palette)
	# Axle, shafts and gears form one train from the wheel to the lift winch.
	for shaft: Dictionary in transmission.get("shafts", []):
		var from: Vector3 = shaft["from"]
		var to: Vector3 = shaft["to"]
		var shaft_node := _add_cylinder_visual(self, (from + to) * 0.5, float(shaft.get("radius", 0.06)), from.distance_to(to), palette["bronze"], "DriveShaft")
		var axis := (to - from).normalized()
		shaft_node.basis = Basis(_perpendicular(axis), axis, axis.cross(_perpendicular(axis))).orthonormalized()
	for gear_spec: Dictionary in transmission.get("gears", []):
		var gear := Node3D.new()
		gear.name = gear_spec["name"]
		var holder := Node3D.new()
		holder.name = gear_spec["name"] + "Mount"
		holder.position = gear_spec["position"]
		var axis: Vector3 = gear_spec["axis"]
		holder.basis = Basis(_perpendicular(axis), axis.normalized(), axis.normalized().cross(_perpendicular(axis))).orthonormalized()
		add_child(holder)
		holder.add_child(gear)
		var radius := float(gear_spec["radius"])
		_add_cylinder_visual(gear, Vector3.ZERO, radius * 0.78, 0.08, palette["bronze"], "GearBody")
		var teeth := int(gear_spec.get("teeth", 12))
		for tooth in range(teeth):
			var angle := tooth * TAU / teeth
			var tooth_visual := _add_box_visual(gear, Vector3(cos(angle) * radius * 0.86, 0.0, sin(angle) * radius * 0.86), Vector3(radius * 0.22, 0.08, radius * 0.14), palette["brass"], "GearTooth")
			tooth_visual.rotation.y = -angle
		wheel.attach_gear(gear, float(gear_spec["ratio"]), Vector3.UP)


func _perpendicular(axis: Vector3) -> Vector3:
	var helper := Vector3.UP if absf(axis.normalized().dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	return axis.cross(helper).normalized()


# --- Float pontoon ---------------------------------------------------------------

func _build_pontoon(spec: Dictionary) -> void:
	var size: Vector3 = spec["size"]
	pontoon = AnimatableBody3D.new()
	pontoon.name = "FloatPontoon"
	pontoon.sync_to_physics = false
	var at: Vector3 = spec["position"]
	pontoon.position = Vector3(at.x, _pontoon_low_y(), at.z)
	add_child(pontoon)
	_add_box_collision(pontoon, Vector3.ZERO, size, 0.0, "PontoonCollision")
	_add_box_visual(pontoon, Vector3.ZERO, size, palette["wood"], "PontoonDeck")
	for side in [-1.0, 1.0]:
		_add_cylinder_visual(pontoon, Vector3(0.0, -size.y * 0.9, side * size.z * 0.32), 0.14, size.x * 0.96, palette["wood_dark"], "PontoonFloat").rotation.z = PI * 0.5


func _pontoon_low_y() -> float:
	var spec: Dictionary = config["pontoon"]
	return float(spec["low_top"]) - (spec["size"] as Vector3).y * 0.5


func _pontoon_water_y() -> float:
	var spec: Dictionary = config["pontoon"]
	var rise := clampf((tank_fill() - float(spec["fill_low"])) / (float(spec["fill_high"]) - float(spec["fill_low"])), 0.0, 1.0)
	return lerpf(float(spec["low_top"]), float(spec["high_top"]), rise) - (spec["size"] as Vector3).y * 0.5


func _update_pontoon(delta: float) -> void:
	# A weight-operated catch holds the float on its tier-2 stops; it releases
	# only while a rider is aboard, so the pontoon is always boardable at tier 2.
	var rider := _pontoon_has_rider()
	pontoon_rider_seconds = pontoon_rider_seconds + delta if rider else 0.0
	pontoon_released = rider and pontoon_rider_seconds >= 0.6
	var target := _pontoon_water_y() if pontoon_released else _pontoon_low_y()
	if not rider and pontoon.position.y > _pontoon_low_y() + 0.01:
		target = _pontoon_low_y()
	elif rider and not pontoon_released:
		target = pontoon.position.y
	pontoon.position.y = move_toward(pontoon.position.y, target, PONTOON_SPEED * delta)


func _pontoon_has_rider() -> bool:
	if not is_instance_valid(marble):
		return false
	var size: Vector3 = config["pontoon"]["size"]
	var local := pontoon.to_local(marble.global_position)
	return absf(local.x) < size.x * 0.5 - 0.12 and absf(local.z) < size.z * 0.5 - 0.12 and local.y > 0.0 and local.y < 0.8


# --- Gates, levers and secrets ------------------------------------------------------

func _build_mill_gate(spec: Dictionary) -> void:
	var size: Vector3 = spec["size"]
	var at: Vector3 = spec["position"]
	mill_gate = AnimatableBody3D.new()
	mill_gate.name = "MillGate"
	mill_gate.sync_to_physics = false
	mill_gate_closed_y = at.y + size.y * 0.5
	mill_gate.position = Vector3(at.x, mill_gate_closed_y, at.z)
	add_child(mill_gate)
	_add_box_collision(mill_gate, Vector3.ZERO, size, 0.0, "MillGateCollision")
	_add_box_visual(mill_gate, Vector3.ZERO, size, palette["wood_dark"], "MillGatePlanks")
	_add_box_visual(mill_gate, Vector3(0.0, size.y * 0.5, 0.0), Vector3(size.x, 0.05, size.z + 0.04), palette["brass"], "MillGateCap")


func _build_lever(spec: Dictionary, lever_name: String, action: Callable) -> Node3D:
	var at: Vector3 = spec["position"]
	var radius := float(spec["radius"])
	_add_cylinder_visual(self, at, radius, 0.07, palette["wet_stone"], lever_name + "Plate")
	_add_torus_visual(self, at + Vector3.UP * 0.05, radius * 0.72, radius * 0.95, palette["amber_glow"], lever_name + "Glow")
	var handle := Node3D.new()
	handle.name = lever_name + "Handle"
	handle.position = at + Vector3(0.0, 0.18, 0.0)
	handle.rotation.z = 0.48
	add_child(handle)
	var bar := _add_cylinder_visual(handle, Vector3(0.0, 0.30, 0.0), 0.07, 0.64, palette["wood_dark"], lever_name + "Bar")
	bar.rotation.z = -0.32
	_add_cylinder_visual(handle, Vector3(0.10, 0.58, 0.0), 0.12, 0.18, palette["brass"], lever_name + "Grip")
	var area := _create_area(lever_name + "Trigger", at + Vector3.UP * 0.24, Vector3(radius * 1.55, 0.50, radius * 1.55))
	area.body_entered.connect(func(body: Node3D) -> void:
		if body == marble:
			action.call()
	)
	return handle


func _build_secret(spec: Dictionary) -> void:
	var area := _create_area("Secret" + String(spec["id"]), spec["position"], spec["size"])
	area.body_entered.connect(func(body: Node3D) -> void:
		if body == marble and not secrets_found.has(spec["id"]):
			secrets_found[spec["id"]] = true
			state_changed.emit(spec["message"])
	)


# --- Visual water -----------------------------------------------------------------

func _build_water_surface(spec: Dictionary) -> void:
	var size: Vector2 = spec["size"]
	var surface: FlowWaterSurface = FlowWaterSurfaceScript.create(spec["name"], size, spec.get("direction", Vector2(0.0, 1.0)), spec.get("waterfall", false))
	surface.position = spec["position"]
	surface.rotation = spec.get("rotation", Vector3.ZERO)
	surface.flux_to_uv = float(spec.get("flux_to_uv", 0.55))
	if spec.has("deep"):
		surface.water_material.set_shader_parameter("deep_color", spec["deep"])
	surface.water_material.set_shader_parameter("foam_amount", float(spec.get("foam", 0.35)))
	surface.water_material.set_shader_parameter("wave_height", float(spec.get("wave", 0.0)))
	if not spec.get("waterfall", false) and ResourceLoader.exists(FOAM_TEXTURE):
		surface.water_material.set_shader_parameter("detail_texture", load(FOAM_TEXTURE))
		surface.water_material.set_shader_parameter("use_detail", true)
	add_child(surface)
	water_surfaces.append(surface)
	water_surface_specs.append(spec)


func _update_water_visuals() -> void:
	for index in range(water_surfaces.size()):
		var spec := water_surface_specs[index]
		var surface := water_surfaces[index]
		if spec.has("flux"):
			surface.set_flux(connection_flux(spec["flux"]))
		if spec.has("level_of"):
			# Level-tracking sheets sit on the simulated water height.
			var fill := network.fill_ratio(StringName(spec["level_of"]))
			var range_y: Vector2 = spec["level_range"]
			surface.position.y = lerpf(range_y.x, range_y.y, clampf(fill, 0.0, 1.0))
		if spec.has("channel"):
			surface.position.y = _channel_surface_y(channel_volumes[int(spec["channel"])])


# --- Static mill structures (millhouse, flumes, posts) -------------------------------

func _build_mill_structures(structures: Array) -> void:
	for spec: Dictionary in structures:
		var material: Material = palette[spec.get("material", "wood")]
		var visual := _add_box_visual(self, spec["position"], spec["size"], material, spec["name"])
		visual.rotation = spec.get("rotation", Vector3.ZERO)
		if spec.get("roof", false):
			_add_roof(spec)


func _add_roof(spec: Dictionary) -> void:
	var at: Vector3 = spec["position"]
	var size: Vector3 = spec["size"]
	var roof := MeshInstance3D.new()
	roof.name = spec["name"] + "Roof"
	var prism := PrismMesh.new()
	prism.size = Vector3(size.x + 0.3, size.y * 0.7, size.z + 0.3)
	roof.mesh = prism
	roof.position = at + Vector3(0.0, size.y * 0.5 + size.y * 0.35, 0.0)
	roof.material_override = palette["roof_tiles"]
	add_child(roof)
