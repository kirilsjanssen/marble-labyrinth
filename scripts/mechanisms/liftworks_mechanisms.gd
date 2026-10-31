class_name LiftworksMechanisms
extends ClockworkMechanisms
## Moving parts of Level 03. Reuses the clockwork gears, lever bridge, transfer
## platform and timer gate, and adds the three-stop lift, rotating sweepers,
## cycling shutters, a physical power cube and the upper lift release.

const PuzzleShapeBodyScript = preload("res://scripts/physics/puzzle_shape_body.gd")
const VerticalLiftScript = preload("res://scripts/mechanisms/vertical_lift.gd")

const SHUTTER_SPEED := 1.8

var lift: VerticalLift
var power_cube: PuzzleShapeBody
var power_plate_area: Area3D
var power_plate_glow: MeshInstance3D
var upper_release_handle: Node3D
var upper_release_glow: MeshInstance3D
var rotor_bodies: Array[AnimatableBody3D] = []
var rotor_speeds: Array[float] = []
var shutter_bodies: Array[AnimatableBody3D] = []
var shutter_specs: Array[Dictionary] = []

var lift_powered := false
var upper_released := false
var secret_found := false
var cube_start := Vector3.ZERO


func setup_liftworks(liftworks_config: Dictionary, materials: Dictionary, player_marble: RigidBody3D, world: Node3D) -> void:
	config = liftworks_config
	palette = materials
	marble = player_marble
	_build_gears(config.get("gears", []))
	_build_bridge(config["bridge"], config["lever"])
	_build_moving_platform(config["moving_platform"])
	_build_gate(config["gate"], config["gate_pad"])
	for rotor_spec: Dictionary in config.get("rotors", []):
		_build_rotor(rotor_spec)
	for shutter_spec: Dictionary in config.get("shutters", []):
		_build_shutter(shutter_spec)

	var riders: Array[RigidBody3D] = [marble]
	lift = VerticalLiftScript.new()
	lift.name = "VerticalLift"
	add_child(lift)
	lift.setup(config["lift"], palette, riders)
	lift.message.connect(func(text: String) -> void: state_changed.emit(text))

	_build_power_plate(config["power_plate"])
	_build_power_cube(config["power_cube"], world)
	_build_upper_release(config["upper_release"])
	_build_secret_sensor(config["secret_sensor"])
	tree_exiting.connect(_free_world_bodies)


func physics_step(delta: float) -> void:
	super.physics_step(delta)
	for index in range(rotor_bodies.size()):
		rotor_bodies[index].rotation.y += rotor_speeds[index] * delta
	for index in range(shutter_bodies.size()):
		var body := shutter_bodies[index]
		body.position.y = move_toward(body.position.y, _shutter_target_y(index), SHUTTER_SPEED * delta)
	if not lift_powered and power_plate_area:
		for body in power_plate_area.get_overlapping_bodies():
			if body.is_in_group("puzzle_bodies") and _resting_on_plate(body as Node3D):
				activate_power()
				break
	if upper_release_handle:
		upper_release_handle.rotation.z = move_toward(upper_release_handle.rotation.z, -0.72 if upper_released else 0.48, 2.6 * delta)
	lift.physics_step(delta)


func reset_state() -> void:
	super.reset_state()
	lift_powered = false
	upper_released = false
	secret_found = false
	lift.reset_lift()
	for body in rotor_bodies:
		body.rotation.y = 0.0
	for index in range(shutter_bodies.size()):
		shutter_bodies[index].position.y = _shutter_target_y(index)
	if upper_release_handle:
		upper_release_handle.rotation.z = 0.48
	_set_glow(power_plate_glow, palette["gate_glow"])
	_set_glow(upper_release_glow, palette["gate_glow"])
	reset_power_cube()


func reset_power_cube() -> void:
	if not is_instance_valid(power_cube):
		return
	power_cube.linear_velocity = Vector3.ZERO
	power_cube.angular_velocity = Vector3.ZERO
	var board := get_parent() as Node3D
	power_cube.global_transform = Transform3D(board.global_basis, board.to_global(cube_start))
	power_cube.sleeping = false


## Overlap lists lag one physics tick behind teleports (reset), so confirm the
## cargo really sits over the plate before latching power.
func _resting_on_plate(body: Node3D) -> bool:
	var plate: Dictionary = config["power_plate"]
	var plate_at: Vector3 = plate["position"]
	var local := (get_parent() as Node3D).to_local(body.global_position)
	return Vector2(local.x - plate_at.x, local.z - plate_at.z).length() <= float(plate["radius"]) + 0.12 and absf(local.y - plate_at.y) < 0.6


func activate_power() -> void:
	if lift_powered:
		return
	lift_powered = true
	lift.unlock_floor(1)
	_set_glow(power_plate_glow, palette["goal"])
	state_changed.emit("POWER PLATE LOADED — LIFT ONLINE")


func activate_upper_release() -> void:
	if upper_released:
		return
	upper_released = true
	lift.unlock_floor(2)
	_set_glow(upper_release_glow, palette["goal"])
	state_changed.emit("UPPER RELEASE PULLED — LIFT CAN REACH FLOOR 3")


func shutters_open() -> Array[bool]:
	var states: Array[bool] = []
	for index in range(shutter_bodies.size()):
		states.append(_shutter_is_open(index))
	return states


func _shutter_is_open(index: int) -> bool:
	var spec := shutter_specs[index]
	var cycle := fposmod(motion_time / float(spec["period"]) + float(spec["phase"]), 1.0)
	return cycle < 0.5


func _shutter_target_y(index: int) -> float:
	var spec := shutter_specs[index]
	var at: Vector3 = spec["position"]
	var size: Vector3 = spec["size"]
	return at.y - size.y * 0.5 - 0.02 if _shutter_is_open(index) else at.y + size.y * 0.5


func _build_rotor(spec: Dictionary) -> void:
	var body := AnimatableBody3D.new()
	body.name = spec["name"]
	body.sync_to_physics = false
	body.position = spec["position"]
	add_child(body)
	rotor_bodies.append(body)
	rotor_speeds.append(float(spec["speed"]))
	var arm := float(spec["arm"])
	var height := float(spec["height"])
	var arm_size := Vector3(arm * 2.0, height, 0.14)
	_add_box_collision(body, Vector3.ZERO, arm_size, 0.0, "SweeperArmCollision")
	_add_box_visual(body, Vector3.ZERO, arm_size, palette["copper"], "SweeperArm")
	_add_cylinder_collision(body, 0.16, height + 0.10, Vector3.ZERO, "SweeperHubCollision")
	_add_cylinder_visual(body, Vector3.ZERO, 0.17, height + 0.12, palette["brass"], "SweeperHub")
	for side in [-1.0, 1.0]:
		_add_cylinder_visual(body, Vector3(side * arm * 0.92, height * 0.5 + 0.02, 0.0), 0.05, 0.05, palette["amber_glow"], "SweeperTipLamp")


func _build_shutter(spec: Dictionary) -> void:
	var size: Vector3 = spec["size"]
	var at: Vector3 = spec["position"]
	var body := AnimatableBody3D.new()
	body.name = spec["name"]
	body.sync_to_physics = false
	body.position = Vector3(at.x, at.y + size.y * 0.5, at.z)
	add_child(body)
	_add_box_collision(body, Vector3.ZERO, size, 0.0, "ShutterCollision")
	_add_box_visual(body, Vector3.ZERO, size, palette["steel"], "ShutterSlab")
	_add_box_visual(body, Vector3(0.0, size.y * 0.5, 0.0), Vector3(size.x + 0.04, 0.05, size.z), palette["gate_glow"], "ShutterEdgeLamp")
	shutter_bodies.append(body)
	shutter_specs.append(spec)


func _build_power_plate(spec: Dictionary) -> void:
	var at: Vector3 = spec["position"]
	var radius := float(spec["radius"])
	_add_cylinder_visual(self, at, radius, 0.06, palette["steel"], "PowerPlate")
	power_plate_glow = _add_torus_visual(self, at + Vector3.UP * 0.04, radius * 0.66, radius * 0.94, palette["gate_glow"], "PowerPlateGlow")
	power_plate_area = _create_area("PowerPlateTrigger", at + Vector3.UP * 0.25, Vector3(radius * 1.6, 0.46, radius * 1.6))


func _build_power_cube(spec: Dictionary, world: Node3D) -> void:
	cube_start = spec["start"]
	power_cube = PuzzleShapeBodyScript.new()
	power_cube.name = "PowerCube"
	power_cube.body_shape = PuzzleShapeBody.BodyShape.CUBE
	power_cube.material_id = spec.get("material", &"wood")
	power_cube.body_size = spec["size"]
	world.add_child(power_cube)
	reset_power_cube()


func _build_upper_release(spec: Dictionary) -> void:
	var at: Vector3 = spec["position"]
	var radius := float(spec["radius"])
	_add_cylinder_visual(self, at, radius, 0.07, palette["steel"], "UpperReleasePlate")
	upper_release_glow = _add_torus_visual(self, at + Vector3.UP * 0.05, radius * 0.72, radius * 0.95, palette["gate_glow"], "UpperReleaseGlow")
	upper_release_handle = Node3D.new()
	upper_release_handle.name = "UpperReleaseHandle"
	upper_release_handle.position = at + Vector3(0.0, 0.18, 0.0)
	upper_release_handle.rotation.z = 0.48
	add_child(upper_release_handle)
	var handle := _add_cylinder_visual(upper_release_handle, Vector3(0.0, 0.30, 0.0), 0.07, 0.64, palette["copper"], "UpperReleaseLever")
	handle.rotation.z = -0.32
	_add_cylinder_visual(upper_release_handle, Vector3(0.10, 0.58, 0.0), 0.13, 0.20, palette["rubber"], "UpperReleaseGrip")
	var area := _create_area("UpperReleaseTrigger", at + Vector3.UP * 0.24, Vector3(radius * 1.55, 0.50, radius * 1.55))
	area.body_entered.connect(func(body: Node3D) -> void:
		if body == marble:
			activate_upper_release()
	)


func _build_secret_sensor(spec: Dictionary) -> void:
	var area := _create_area("SecretRouteSensor", spec["position"], spec["size"])
	area.body_entered.connect(func(body: Node3D) -> void:
		if body == marble and not secret_found:
			secret_found = true
			state_changed.emit("SECRET GEAR RUN — slip past the teeth to skip the gate")
	)


func _set_glow(visual: MeshInstance3D, material: Material) -> void:
	if visual:
		visual.material_override = material


func _free_world_bodies() -> void:
	if is_instance_valid(power_cube):
		power_cube.queue_free()
