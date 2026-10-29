class_name ClockworkMechanisms
extends Node3D
## Reusable physical mechanisms for clockwork levels. Every moving obstacle is an
## AnimatableBody3D so its motion is reported to the RigidBody3D marble.

signal state_changed(message: String)

var config: Dictionary
var palette: Dictionary
var marble: RigidBody3D

var gear_bodies: Array[AnimatableBody3D] = []
var gear_speeds: Array[float] = []
var shaft_bodies: Array[AnimatableBody3D] = []
var shaft_speeds: Array[float] = []
var bridge_body: AnimatableBody3D
var bridge_lever: Node3D
var moving_platform: AnimatableBody3D
var elevator_body: AnimatableBody3D
var gate_body: AnimatableBody3D
var gate_light: OmniLight3D

var bridge_open := false
var elevator_raised := false
var gate_pad_occupied := false
var gate_timer := 0.0
var motion_time := 0.0

var bridge_closed_angle := -PI * 0.5
var bridge_open_angle := 0.0
var bridge_speed := 1.5
var platform_origin := Vector3.ZERO
var platform_travel := Vector3.ZERO
var platform_period := 4.0
var elevator_origin := Vector3.ZERO
var elevator_height := 1.0
var elevator_speed := 0.7
var gate_origin := Vector3.ZERO
var gate_lift_height := 1.5
var gate_speed := 2.0
var gate_open_seconds := 6.0


func setup(mechanism_config: Dictionary, shaft_config: Array, materials: Dictionary, player_marble: RigidBody3D) -> void:
	config = mechanism_config
	palette = materials
	marble = player_marble
	_build_gears(config.get("gears", []))
	_build_shafts(shaft_config)
	_build_bridge(config["bridge"], config["lever"])
	_build_moving_platform(config["moving_platform"])
	_build_elevator(config["elevator"])
	_build_gate(config["gate"], config["gate_pad"])


func physics_step(delta: float) -> void:
	motion_time += delta
	for index in range(gear_bodies.size()):
		gear_bodies[index].rotation.y += gear_speeds[index] * delta
	for index in range(shaft_bodies.size()):
		shaft_bodies[index].rotation.x += shaft_speeds[index] * delta

	if bridge_body:
		var target_angle := bridge_open_angle if bridge_open else bridge_closed_angle
		bridge_body.rotation.z = move_toward(bridge_body.rotation.z, target_angle, bridge_speed * delta)
		if bridge_lever:
			bridge_lever.rotation.z = move_toward(bridge_lever.rotation.z, -0.72 if bridge_open else 0.48, 2.6 * delta)

	if moving_platform:
		var phase := (1.0 - cos(motion_time * TAU / platform_period)) * 0.5
		moving_platform.position = platform_origin + platform_travel * phase

	if elevator_body:
		var elevator_target := elevator_origin + Vector3.UP * elevator_height if elevator_raised else elevator_origin
		elevator_body.position = elevator_body.position.move_toward(elevator_target, elevator_speed * delta)

	if gate_pad_occupied:
		gate_timer = gate_open_seconds
	elif gate_timer > 0.0:
		gate_timer = maxf(0.0, gate_timer - delta)
	if gate_body:
		var gate_target := gate_origin + Vector3.UP * gate_lift_height if gate_timer > 0.0 else gate_origin
		gate_body.position = gate_body.position.move_toward(gate_target, gate_speed * delta)
	if gate_light:
		gate_light.light_color = Color("58e59a") if gate_timer > 0.0 else Color("ff5c52")
		gate_light.light_energy = 1.8 + 0.5 * sin(motion_time * 5.0)


func reset_state() -> void:
	motion_time = 0.0
	bridge_open = false
	elevator_raised = false
	gate_pad_occupied = false
	gate_timer = 0.0
	if bridge_body:
		bridge_body.rotation.z = bridge_closed_angle
	if bridge_lever:
		bridge_lever.rotation.z = 0.48
	if moving_platform:
		moving_platform.position = platform_origin
	if elevator_body:
		elevator_body.position = elevator_origin
	if gate_body:
		gate_body.position = gate_origin


func activate_bridge() -> void:
	if bridge_open:
		return
	bridge_open = true
	state_changed.emit("BRIDGE RELEASED — cross while the platform is aligned")


func activate_elevator() -> void:
	if elevator_raised:
		return
	elevator_raised = true
	state_changed.emit("LIFT ENGAGED — upper assembly unlocked")


func activate_gate() -> void:
	gate_timer = gate_open_seconds
	state_changed.emit("TIMER GATE OPEN — %0.1f SECONDS" % gate_open_seconds)


func _build_gears(gears: Array) -> void:
	for gear_spec: Dictionary in gears:
		var body := AnimatableBody3D.new()
		body.name = gear_spec["name"]
		body.sync_to_physics = true
		body.position = gear_spec["position"]
		add_child(body)
		gear_bodies.append(body)
		gear_speeds.append(float(gear_spec["speed"]))

		var radius := float(gear_spec["radius"])
		var teeth := int(gear_spec["teeth"])
		_add_cylinder_collision(body, radius * 0.72, 0.46, Vector3.ZERO, "HubCollision")
		_add_cylinder_visual(body, Vector3.ZERO, radius * 0.74, 0.38, palette["steel"], "SteelHub")
		_add_torus_visual(body, Vector3(0.0, 0.01, 0.0), radius * 0.40, radius * 0.67, palette["brass"], "BrassWheel")
		_add_cylinder_visual(body, Vector3(0.0, 0.24, 0.0), radius * 0.16, 0.18, palette["brass_dark"], "AxleCap")

		for tooth_index in range(teeth):
			var angle := tooth_index * TAU / teeth
			var tooth_at := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			var tooth_size := Vector3(radius * 0.36, 0.42, radius * 0.19)
			_add_box_collision(body, tooth_at, tooth_size, -angle, "ToothCollision%02d" % tooth_index)
			var tooth := _add_box_visual(body, tooth_at, tooth_size * Vector3(1.0, 0.88, 1.0), palette["brass"], "GearTooth%02d" % tooth_index)
			tooth.rotation.y = -angle


func _build_shafts(shafts: Array) -> void:
	for index in range(shafts.size()):
		var shaft_spec: Dictionary = shafts[index]
		var body := AnimatableBody3D.new()
		body.name = "DriveShaft%d" % (index + 1)
		body.sync_to_physics = true
		body.position = shaft_spec["position"]
		add_child(body)
		shaft_bodies.append(body)
		shaft_speeds.append(float(shaft_spec["speed"]))
		var length := float(shaft_spec["length"])
		var collider := CollisionShape3D.new()
		collider.name = "ShaftCollision"
		collider.rotation.z = PI * 0.5
		var shape := CylinderShape3D.new()
		shape.radius = 0.13
		shape.height = length
		collider.shape = shape
		body.add_child(collider)
		var shaft := _add_cylinder_visual(body, Vector3.ZERO, 0.13, length, palette["steel"], "SteelShaft")
		shaft.rotation.z = PI * 0.5
		for side in [-1.0, 1.0]:
			var collar := _add_torus_visual(body, Vector3(side * length * 0.42, 0.0, 0.0), 0.13, 0.21, palette["brass"], "ShaftCollar")
			collar.rotation.z = PI * 0.5


func _build_bridge(bridge: Dictionary, lever: Dictionary) -> void:
	bridge_closed_angle = float(bridge["closed_angle"])
	bridge_open_angle = float(bridge["open_angle"])
	bridge_speed = float(bridge["speed"])
	var size: Vector3 = bridge["size"]
	bridge_body = AnimatableBody3D.new()
	bridge_body.name = "LeverBridge"
	bridge_body.sync_to_physics = true
	bridge_body.position = bridge["pivot"]
	bridge_body.rotation.z = bridge_closed_angle
	add_child(bridge_body)
	var bridge_center := Vector3(size.x * 0.5, 0.0, 0.0)
	_add_box_collision(bridge_body, bridge_center, size, 0.0, "BridgeCollision")
	_add_box_visual(bridge_body, bridge_center, size, palette["steel"], "BridgeDeck")
	_add_box_visual(bridge_body, bridge_center + Vector3(0.0, size.y * 0.62, size.z * 0.42), Vector3(size.x, 0.08, 0.09), palette["brass"], "BridgeRailNorth")
	_add_box_visual(bridge_body, bridge_center + Vector3(0.0, size.y * 0.62, -size.z * 0.42), Vector3(size.x, 0.08, 0.09), palette["brass"], "BridgeRailSouth")

	var hinge := _add_cylinder_visual(self, bridge["pivot"], 0.23, size.z * 1.18, palette["brass_dark"], "BridgeHinge")
	hinge.rotation.x = PI * 0.5

	var lever_position: Vector3 = lever["position"]
	_add_cylinder_visual(self, lever_position, float(lever["radius"]), 0.07, palette["steel"], "LeverPlate")
	_add_torus_visual(self, lever_position + Vector3.UP * 0.05, float(lever["radius"]) * 0.72, float(lever["radius"]) * 0.95, palette["amber_glow"], "LeverPlateGlow")
	bridge_lever = Node3D.new()
	bridge_lever.name = "BridgeLeverHandle"
	bridge_lever.position = lever_position + Vector3(0.0, 0.18, 0.0)
	bridge_lever.rotation.z = 0.48
	add_child(bridge_lever)
	var handle := _add_cylinder_visual(bridge_lever, Vector3(0.0, 0.30, 0.0), 0.07, 0.64, palette["brass"], "LeverHandle")
	handle.rotation.z = -0.32
	_add_cylinder_visual(bridge_lever, Vector3(0.10, 0.58, 0.0), 0.13, 0.20, palette["rubber"], "LeverGrip")
	var lever_area := _create_area("BridgeLeverTrigger", lever_position + Vector3.UP * 0.24, Vector3(float(lever["radius"]) * 1.55, 0.50, float(lever["radius"]) * 1.55))
	lever_area.body_entered.connect(_on_lever_entered)


func _build_moving_platform(platform: Dictionary) -> void:
	platform_origin = platform["origin"]
	platform_travel = platform["travel"]
	platform_period = float(platform["period"])
	var size: Vector3 = platform["size"]
	moving_platform = AnimatableBody3D.new()
	moving_platform.name = "TransferPlatform"
	moving_platform.sync_to_physics = true
	moving_platform.position = platform_origin
	add_child(moving_platform)
	_add_box_collision(moving_platform, Vector3.ZERO, size, 0.0, "TransferCollision")
	_add_box_visual(moving_platform, Vector3.ZERO, size, palette["steel"], "TransferDeck")
	_add_box_visual(moving_platform, Vector3(0.0, size.y * 0.65, size.z * 0.43), Vector3(size.x, 0.08, 0.08), palette["brass"], "TransferRailA")
	_add_box_visual(moving_platform, Vector3(0.0, size.y * 0.65, -size.z * 0.43), Vector3(size.x, 0.08, 0.08), palette["brass"], "TransferRailB")
	for corner_x in [-1.0, 1.0]:
		for corner_z in [-1.0, 1.0]:
			_add_cylinder_visual(moving_platform, Vector3(corner_x * size.x * 0.38, size.y * 0.65, corner_z * size.z * 0.37), 0.055, 0.08, palette["amber_glow"], "PlatformLamp")


func _build_elevator(elevator: Dictionary) -> void:
	elevator_origin = elevator["position"]
	elevator_height = float(elevator["travel_height"])
	elevator_speed = float(elevator["speed"])
	var size: Vector3 = elevator["size"]
	elevator_body = AnimatableBody3D.new()
	elevator_body.name = "MarbleLift"
	elevator_body.sync_to_physics = true
	elevator_body.position = elevator_origin
	add_child(elevator_body)
	_add_box_collision(elevator_body, Vector3.ZERO, size, 0.0, "LiftCollision")
	_add_box_visual(elevator_body, Vector3.ZERO, size, palette["steel"], "LiftDeck")
	_add_torus_visual(elevator_body, Vector3(0.0, size.y * 0.60, 0.0), 0.35, 0.48, palette["brass"], "LiftCog")
	var lift_area := _create_area_on(elevator_body, "LiftTrigger", Vector3(0.0, 0.32, 0.0), Vector3(size.x * 0.90, 0.58, size.z * 0.90))
	lift_area.body_entered.connect(_on_lift_entered)


func _build_gate(gate: Dictionary, pad: Dictionary) -> void:
	gate_origin = gate["position"]
	gate_lift_height = float(gate["lift_height"])
	gate_speed = float(gate["speed"])
	gate_open_seconds = float(gate["open_seconds"])
	var size: Vector3 = gate["size"]
	gate_body = AnimatableBody3D.new()
	gate_body.name = "TimerGate"
	gate_body.sync_to_physics = true
	gate_body.position = gate_origin
	add_child(gate_body)
	_add_box_collision(gate_body, Vector3.ZERO, size, 0.0, "GateCollision")
	_add_box_visual(gate_body, Vector3.ZERO, size, palette["steel"], "GateSlab")
	for bar_z in [-0.72, -0.24, 0.24, 0.72]:
		_add_box_visual(gate_body, Vector3(-size.x * 0.56, 0.0, bar_z * size.z * 0.5), Vector3(0.10, size.y * 0.92, 0.10), palette["brass"], "GateBar")

	var pad_position: Vector3 = pad["position"]
	_add_cylinder_visual(self, pad_position, float(pad["radius"]), 0.07, palette["steel"], "TimerPad")
	_add_torus_visual(self, pad_position + Vector3.UP * 0.05, float(pad["radius"]) * 0.68, float(pad["radius"]) * 0.94, palette["gate_glow"], "TimerPadGlow")
	var gate_area := _create_area("GateTimerTrigger", pad_position + Vector3.UP * 0.24, Vector3(float(pad["radius"]) * 1.55, 0.50, float(pad["radius"]) * 1.55))
	gate_area.body_entered.connect(_on_gate_pad_entered)
	gate_area.body_exited.connect(_on_gate_pad_exited)
	gate_light = OmniLight3D.new()
	gate_light.name = "GateSignalLamp"
	gate_light.position = gate_origin + Vector3(0.0, size.y * 0.68, 0.0)
	gate_light.light_color = Color("ff5c52")
	gate_light.light_energy = 2.0
	gate_light.omni_range = 2.7
	add_child(gate_light)


func _on_lever_entered(body: Node3D) -> void:
	if body == marble:
		activate_bridge()


func _on_lift_entered(body: Node3D) -> void:
	if body == marble:
		activate_elevator()


func _on_gate_pad_entered(body: Node3D) -> void:
	if body == marble:
		gate_pad_occupied = true
		activate_gate()


func _on_gate_pad_exited(body: Node3D) -> void:
	if body == marble:
		gate_pad_occupied = false


func _create_area(area_name: String, at: Vector3, size: Vector3) -> Area3D:
	return _create_area_on(self, area_name, at, size)


func _create_area_on(parent: Node3D, area_name: String, at: Vector3, size: Vector3) -> Area3D:
	var area := Area3D.new()
	area.name = area_name
	area.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	area.add_child(collision)
	parent.add_child(area)
	return area


func _add_box_collision(parent: Node3D, at: Vector3, size: Vector3, yaw: float, collision_name: String) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	collision.name = collision_name
	collision.position = at
	collision.rotation.y = yaw
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	parent.add_child(collision)
	return collision


func _add_cylinder_collision(parent: Node3D, radius: float, height: float, at: Vector3, collision_name: String) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	collision.name = collision_name
	collision.position = at
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	parent.add_child(collision)
	return collision


func _add_box_visual(parent: Node3D, at: Vector3, size: Vector3, material: Material, part_name: String) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = part_name
	visual.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	parent.add_child(visual)
	return visual


func _add_cylinder_visual(parent: Node3D, at: Vector3, radius: float, height: float, material: Material, part_name: String) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = part_name
	visual.position = at
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	visual.mesh = mesh
	visual.material_override = material
	parent.add_child(visual)
	return visual


func _add_torus_visual(parent: Node3D, at: Vector3, inner_radius: float, outer_radius: float, material: Material, part_name: String) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = part_name
	visual.position = at
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	visual.mesh = mesh
	visual.material_override = material
	parent.add_child(visual)
	return visual
