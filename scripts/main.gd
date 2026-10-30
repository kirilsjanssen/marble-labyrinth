extends Node3D
## Runtime controller for a miniature mechanical labyrinth. Geometry is generated
## from level data, while the marble remains a real RigidBody3D at all times.

const Level01 = preload("res://scripts/levels/level_01.gd")
const Level02 = preload("res://scripts/levels/level_02.gd")
const ClockworkMechanismsScript = preload("res://scripts/components/clockwork_mechanisms.gd")
const TiltStickIndicatorScript = preload("res://scripts/components/tilt_stick_indicator.gd")
const GoalSocketDetectorScript = preload("res://scripts/components/goal_socket_detector.gd")
const LEVEL_SOURCES := [Level01, Level02]

const MAX_TILT := deg_to_rad(15.0)
const TILT_RESPONSE := 5.5
# A tilted AnimatableBody3D alone is not guaranteed to wake or drive a rigid marble.
# Apply a board-local gravitational component to the real RigidBody3D every tick.
const TILT_FORCE_MULTIPLIER := 2.5
const BALL_RADIUS := 0.33
const BALL_MASS := 0.34
const BALL_LINEAR_DAMP := 0.12
const BALL_ANGULAR_DAMP := 0.08
const TOUCH_TILT_DISTANCE := 140.0
const SENSOR_RANGE := 5.5

enum ControlMode { AUTO, TOUCH, SENSOR }

var level_data: Dictionary = Level01.definition()
var board: AnimatableBody3D
var ball: RigidBody3D
var camera: Camera3D
var status_label: Label
var hint_label: Label
var mode_button: Button
var calibrate_button: Button
var view_button: Button
var help_button: Button
var help_overlay: ColorRect
var tilt_indicator: Control
var level_selector: OptionButton
var completion_overlay: CenterContainer
var completion_title: Label
var completion_detail: Label
var next_level_button: Button
var hud_root: Control
var info_panel: PanelContainer
var button_row: HBoxContainer
var touch_help_left: Label
var touch_help_right: Label
var wind_rotor: Node3D
var magnet_light: OmniLight3D
var magnet_ring: MeshInstance3D
var trap_ring: MeshInstance3D
var goal_ring: MeshInstance3D
var goal_detector: GoalSocketDetector
var clockwork: ClockworkMechanisms

var materials: Dictionary = {}
var touch_start: Dictionary = {}
var tilt_touch_index := -1
var mouse_tilt_active := false
var mouse_tilt_origin := Vector2.ZERO
var drag_tilt := Vector2.ZERO
var active_tilt := Vector2.ZERO
var sensor_zero := Vector2.ZERO
var sensor_calibrated := false
var control_mode := ControlMode.AUTO
var yaw := deg_to_rad(32.0)
var pitch := deg_to_rad(52.0)
var orbit_distance := 13.6
var elapsed := 0.0
var visual_time := 0.0
var game_won := false
var respawn_queued := false
var current_level_index := 0
var transient_message := ""
var transient_message_time := 0.0


func _ready() -> void:
	control_mode = _default_control_mode(OS.get_name())
	_build_materials()
	_build_environment()
	_build_camera()
	_build_hud()
	_load_level(0)
	_calibrate_sensor(false)
	_update_camera()


func _physics_process(delta: float) -> void:
	if respawn_queued:
		_reset_level()

	var tilt := _read_tilt_input()
	active_tilt = tilt
	var target_rotation := Vector3(-tilt.y * MAX_TILT, 0.0, -tilt.x * MAX_TILT)
	var weight := clampf(delta * TILT_RESPONSE, 0.0, 1.0)
	board.rotation.x = lerp_angle(board.rotation.x, target_rotation.x, weight)
	board.rotation.z = lerp_angle(board.rotation.z, target_rotation.z, weight)
	if not game_won:
		_apply_marble_tilt_force(tilt)
	if clockwork:
		clockwork.physics_step(delta)

	if not game_won:
		elapsed += delta
		_apply_environment_forces()
		if ball.global_position.y < -2.5 or ball.global_position.length() > 25.0:
			respawn_queued = true


func _process(delta: float) -> void:
	visual_time += delta
	transient_message_time = maxf(0.0, transient_message_time - delta)
	_update_camera()
	_animate_obstacles(delta)
	_update_hud()


# Touch events are received before GUI routing. An unhandled-input listener loses
# all drags when the full-screen HUD Control consumes them on Android.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if game_won or _touch_on_hud(event.position):
				return
			touch_start[event.index] = event.position
			if event.position.x < get_viewport().get_visible_rect().size.x * 0.5 and tilt_touch_index == -1:
				tilt_touch_index = event.index
		else:
			touch_start.erase(event.index)
			if event.index == tilt_touch_index:
				tilt_touch_index = -1
				drag_tilt = Vector2.ZERO
	elif event is InputEventScreenDrag and touch_start.has(event.index):
		var start: Vector2 = touch_start[event.index]
		if event.index == tilt_touch_index:
			if control_mode != ControlMode.SENSOR:
				drag_tilt = _screen_drag_to_board_tilt((event.position - start) / TOUCH_TILT_DISTANCE)
		else:
			_orbit_camera(event.relative, 0.009)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		mouse_tilt_active = false
		if OS.get_name() != "Android":
			drag_tilt = Vector2.ZERO


func _touch_on_hud(point: Vector2) -> bool:
	if (completion_overlay and completion_overlay.visible) or (help_overlay and help_overlay.visible):
		return true
	return (info_panel != null and info_panel.get_global_rect().has_point(point)) or (button_row != null and button_row.get_global_rect().has_point(point))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				respawn_queued = true
			KEY_G, KEY_M:
				_cycle_control_mode()
			KEY_C:
				_calibrate_sensor(true)
			KEY_1:
				_load_level(0)
			KEY_2:
				_load_level(1)
			KEY_L:
				_load_level((current_level_index + 1) % LEVEL_SOURCES.size())
			KEY_N, KEY_ENTER:
				if game_won:
					_advance_level()

	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_orbit_camera(event.relative, 0.008)
		elif OS.get_name() != "Android" and mouse_tilt_active and control_mode != ControlMode.SENSOR:
			drag_tilt = _screen_drag_to_board_tilt((event.position - mouse_tilt_origin) / TOUCH_TILT_DISTANCE)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = maxf(10.5, orbit_distance - 0.7)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = minf(17.0, orbit_distance + 0.7)
		elif event.button_index == MOUSE_BUTTON_LEFT and OS.get_name() != "Android" and not _touch_on_hud(event.position):
			mouse_tilt_origin = event.position
			mouse_tilt_active = true


func _apply_marble_tilt_force(tilt: Vector2) -> void:
	# Physical force: the marble still uses mass, real collisions, friction and inertia.
	# Multiplying by sin(MAX_TILT) approximates the downhill gravity component.
	# Boost compensates for the short mobile tilt range and high-friction steel deck.
	if not ball or tilt.length_squared() < 0.0004:
		return
	ball.sleeping = false
	var tangent := board.global_basis * Vector3(tilt.x, 0.0, tilt.y)
	var gravity_strength: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	ball.apply_central_force(tangent * ball.mass * gravity_strength * sin(MAX_TILT) * TILT_FORCE_MULTIPLIER)


func _read_tilt_input() -> Vector2:
	var keyboard := Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	)
	if keyboard.length_squared() > 0.01:
		return keyboard.normalized()

	if control_mode == ControlMode.TOUCH:
		return drag_tilt
	if control_mode == ControlMode.SENSOR:
		return _sensor_tilt()
	if drag_tilt.length_squared() > 0.001:
		return drag_tilt
	return _sensor_tilt()


func _sensor_vector() -> Vector3:
	var gravity := Input.get_gravity()
	# Some Android devices expose the accelerometer but not the gravity sensor.
	if gravity.length_squared() < 1.0:
		gravity = Input.get_accelerometer()
	return gravity


func _tilt_from_gravity(gravity: Vector3) -> Vector2:
	if gravity.length_squared() < 1.0:
		return Vector2.ZERO
	var reading := Vector2(gravity.x, -gravity.y)
	if sensor_calibrated:
		reading -= Vector2(sensor_zero.x, -sensor_zero.y)
	return (reading / SENSOR_RANGE).limit_length(1.0)


func _sensor_tilt() -> Vector2:
	return _tilt_from_gravity(_sensor_vector())


func _calibrate_sensor(show_feedback: bool) -> void:
	var gravity := _sensor_vector()
	if gravity.length_squared() >= 1.0:
		sensor_zero = Vector2(gravity.x, gravity.y)
		sensor_calibrated = true
		if show_feedback:
			_show_message("Sensor calibrated. Tilt the phone to roll.", 3.5)
	else:
		sensor_calibrated = false
		if show_feedback:
			_show_message("Motion sensor unavailable. Choose TOUCH control.", 3.5)


func _default_control_mode(platform_name: String) -> ControlMode:
	# Auto could silently mix drag and phone gyro, making the ball look unpredictable.
	return ControlMode.TOUCH if platform_name == "Android" else ControlMode.AUTO


func _cycle_control_mode() -> void:
	control_mode = ((control_mode + 1) % ControlMode.size()) as ControlMode
	drag_tilt = Vector2.ZERO
	tilt_touch_index = -1
	touch_start.clear()
	if control_mode == ControlMode.SENSOR:
		_calibrate_sensor(false)
	_update_mode_button()
	_update_touch_help()


func _orbit_camera(relative: Vector2, sensitivity: float) -> void:
	yaw -= relative.x * sensitivity
	pitch = clampf(pitch + relative.y * sensitivity * 0.75, deg_to_rad(24.0), deg_to_rad(74.0))


func _screen_drag_to_board_tilt(screen_drag: Vector2) -> Vector2:
	# A direction on the screen must have the same meaning even after orbiting.
	# Convert the projected camera axes into board-local horizontal force axes.
	if camera == null or board == null:
		return screen_drag.limit_length(1.0)
	var screen_right := camera.global_basis.x
	var screen_down := -camera.global_basis.y
	var world_direction := screen_right * screen_drag.x + screen_down * screen_drag.y
	world_direction.y = 0.0
	if world_direction.length_squared() < 0.0001:
		return screen_drag.limit_length(1.0)
	var board_local := board.global_basis.inverse() * world_direction.normalized()
	return Vector2(board_local.x, board_local.z) * minf(screen_drag.length(), 1.0)


func _board_tilt_to_screen(tilt: Vector2) -> Vector2:
	# The on-screen thumb should follow the gesture, not board-local axes.
	if camera == null or board == null or tilt.length_squared() < 0.0001:
		return tilt
	var world_direction := board.global_basis * Vector3(tilt.x, 0.0, tilt.y)
	var screen_direction := Vector2(world_direction.dot(camera.global_basis.x), world_direction.dot(-camera.global_basis.y))
	if screen_direction.length_squared() < 0.0001:
		return Vector2.ZERO
	return screen_direction.normalized() * minf(tilt.length(), 1.0)


func _build_materials() -> void:
	materials = {
		"frame": _metal(Color("171d26"), 0.88, 0.20),
		"deck": _metal(Color("242d38"), 0.72, 0.28),
		"wall": _metal(Color("354252"), 0.82, 0.22),
		"steel": _metal(Color("586675"), 0.90, 0.18),
		"brass": _metal(Color("b58a43"), 0.92, 0.20),
		"brass_dark": _metal(Color("735126"), 0.86, 0.29),
		"copper": _metal(Color("9e5638"), 0.88, 0.24),
		"marble": _metal(Color("d9e7ef"), 0.92, 0.08),
		"rubber": _metal(Color("11161c"), 0.15, 0.72),
		"wind": _emissive_material(Color("42c9ff"), 1.5),
		"magnet": _emissive_material(Color("c071ff"), 1.45),
		"trap": _emissive_material(Color("ff4d55"), 1.2),
		"goal": _emissive_material(Color("55e7a0"), 1.4),
		"amber_glow": _emissive_material(Color("ffb64d"), 1.25),
		"gate_glow": _emissive_material(Color("ff6258"), 1.25),
	}


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	world.name = "WorkshopEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("080c12")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8296ac")
	environment.ambient_light_energy = 0.48
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)

	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.rotation_degrees = Vector3(-58.0, -32.0, -18.0)
	key_light.light_color = Color("ffe2ae")
	key_light.light_energy = 2.15
	key_light.shadow_enabled = true
	add_child(key_light)

	var rim_light := OmniLight3D.new()
	rim_light.name = "CoolRimLight"
	rim_light.position = Vector3(-4.0, 5.2, -3.5)
	rim_light.light_color = Color("62aaff")
	rim_light.light_energy = 3.0
	rim_light.omni_range = 12.0
	rim_light.shadow_enabled = true
	add_child(rim_light)

	var warm_light := OmniLight3D.new()
	warm_light.name = "WarmBenchLight"
	warm_light.position = Vector3(4.5, 3.4, 4.0)
	warm_light.light_color = Color("ffc36b")
	warm_light.light_energy = 2.2
	warm_light.omni_range = 10.0
	add_child(warm_light)


func _load_level(index: int) -> void:
	if index < 0 or index >= LEVEL_SOURCES.size():
		return
	if ball and is_instance_valid(ball):
		remove_child(ball)
		ball.queue_free()
	if board and is_instance_valid(board):
		remove_child(board)
		board.queue_free()

	current_level_index = index
	level_data = LEVEL_SOURCES[index].definition()
	clockwork = null
	wind_rotor = null
	magnet_light = null
	magnet_ring = null
	trap_ring = null
	goal_ring = null
	goal_detector = null
	game_won = false
	respawn_queued = false
	elapsed = 0.0
	drag_tilt = Vector2.ZERO
	tilt_touch_index = -1
	touch_start.clear()
	yaw = deg_to_rad(32.0)
	pitch = deg_to_rad(52.0)
	orbit_distance = 13.6

	_build_board()
	_build_ball()
	goal_detector.target_body = ball
	if level_data.has("mechanics"):
		clockwork = ClockworkMechanismsScript.new()
		clockwork.name = "ClockworkMechanisms"
		board.add_child(clockwork)
		clockwork.setup(level_data["mechanics"], level_data.get("shafts", []), materials, ball)
		clockwork.state_changed.connect(_on_mechanism_message)
	if level_selector:
		level_selector.select(index)
	if completion_overlay:
		completion_overlay.hide()
	_update_level_lighting()
	_update_hud()


func _update_level_lighting() -> void:
	var warm_light := get_node_or_null("WarmBenchLight") as OmniLight3D
	var rim_light := get_node_or_null("CoolRimLight") as OmniLight3D
	if level_data.get("style", "workshop") == "clockwork":
		warm_light.light_color = Color("ffb247")
		warm_light.light_energy = 2.8
		rim_light.light_color = Color("6e9dc8")
	else:
		warm_light.light_color = Color("ffc36b")
		warm_light.light_energy = 2.2
		rim_light.light_color = Color("62aaff")


func _build_board() -> void:
	board = AnimatableBody3D.new()
	board.name = "TiltingBoard"
	board.sync_to_physics = true
	var board_physics := PhysicsMaterial.new()
	board_physics.friction = 0.64
	board_physics.bounce = 0.06
	board.physics_material_override = board_physics
	add_child(board)

	if level_data.has("floor_tiles"):
		_add_box_part("FactoryUnderframe", Vector3(0.0, -0.52, 0.0), Vector3(9.65, 0.12, 9.65), materials.frame, false)
		_add_box_part("FactoryBrassBand", Vector3(0.0, -0.60, 0.0), Vector3(9.82, 0.08, 9.82), materials.brass_dark, false)
		for tile: Dictionary in level_data["floor_tiles"]:
			var tile_material: Material = materials.steel if tile.get("elevated", false) else materials.deck
			_add_box_part(tile["name"], tile["position"], tile["size"], tile_material, true)
			_add_floor_tile_details(tile)
		_build_factory_details()
	else:
		_add_box_part("Board", Vector3(0.0, -0.16, 0.0), Vector3(9.55, 0.36, 9.55), materials.frame, true)
		_add_box_part("DeckInset", Vector3(0.0, 0.035, 0.0), Vector3(9.05, 0.08, 9.05), materials.deck, false)
		_add_box_part("LowerBrassBand", Vector3(0.0, -0.30, 0.0), Vector3(9.75, 0.10, 9.75), materials.brass_dark, false)
		_build_deck_details()

	for wall_spec: Dictionary in level_data["walls"]:
		_add_wall(wall_spec)

	if level_data.has("wind"):
		_build_wind_device(level_data["wind"])
	if level_data.has("magnet"):
		_build_magnet_device(level_data["magnet"])
	if level_data.has("trap"):
		_build_trap(level_data["trap"])
	for hole: Dictionary in level_data.get("holes", []):
		_build_hole(hole)
	_build_goal(level_data["goal"])


func _add_floor_tile_details(tile: Dictionary) -> void:
	var at: Vector3 = tile["position"]
	var size: Vector3 = tile["size"]
	var surface_y := at.y + size.y * 0.5 + 0.012
	_add_box_visual(board, Vector3(at.x, surface_y, at.z - size.z * 0.34), Vector3(size.x * 0.90, 0.025, 0.025), materials.brass_dark, tile["name"] + "SeamA")
	_add_box_visual(board, Vector3(at.x, surface_y, at.z + size.z * 0.34), Vector3(size.x * 0.90, 0.025, 0.025), materials.brass_dark, tile["name"] + "SeamB")
	for corner_x in [-1.0, 1.0]:
		for corner_z in [-1.0, 1.0]:
			var fastener := Vector3(at.x + corner_x * size.x * 0.42, surface_y + 0.025, at.z + corner_z * size.z * 0.42)
			_add_cylinder_visual(board, fastener, 0.055, 0.045, materials.brass, tile["name"] + "Rivet")


func _build_factory_details() -> void:
	for lamp: Dictionary in level_data.get("lamps", []):
		_build_factory_lamp(lamp)
	for brace_x in [-4.45, -2.35, 0.65, 4.40]:
		_add_box_visual(board, Vector3(brace_x, -0.34, 0.0), Vector3(0.13, 0.28, 8.70), materials.steel, "UnderframeBrace")


func _build_factory_lamp(spec: Dictionary) -> void:
	var at: Vector3 = spec["position"]
	var color: Color = spec["color"]
	_add_cylinder_visual(board, at + Vector3.UP * 0.52, 0.055, 1.04, materials.brass_dark, "FactoryLampPost")
	var shade := MeshInstance3D.new()
	shade.name = "FactoryLampShade"
	shade.position = at + Vector3.UP * 1.03
	var shade_mesh := CylinderMesh.new()
	shade_mesh.top_radius = 0.08
	shade_mesh.bottom_radius = 0.24
	shade_mesh.height = 0.22
	shade.mesh = shade_mesh
	shade.material_override = materials.brass
	board.add_child(shade)
	var light := OmniLight3D.new()
	light.name = "FactoryLampLight"
	light.position = at + Vector3.UP * 0.90
	light.light_color = color
	light.light_energy = 1.65
	light.omni_range = 3.4
	light.shadow_enabled = true
	board.add_child(light)


func _build_hole(spec: Dictionary) -> void:
	var at: Vector3 = spec["position"]
	var size: Vector3 = spec["size"]
	var rim_y := at.y + size.y * 0.5 + 0.37
	_add_box_visual(board, Vector3(at.x, rim_y, at.z - size.z * 0.5), Vector3(size.x + 0.16, 0.07, 0.09), materials.brass_dark, spec["name"] + "RimNorth")
	_add_box_visual(board, Vector3(at.x, rim_y, at.z + size.z * 0.5), Vector3(size.x + 0.16, 0.07, 0.09), materials.brass_dark, spec["name"] + "RimSouth")
	_add_box_visual(board, Vector3(at.x - size.x * 0.5, rim_y, at.z), Vector3(0.09, 0.07, size.z), materials.brass_dark, spec["name"] + "RimWest")
	_add_box_visual(board, Vector3(at.x + size.x * 0.5, rim_y, at.z), Vector3(0.09, 0.07, size.z), materials.brass_dark, spec["name"] + "RimEast")
	var hole_area := Area3D.new()
	hole_area.name = spec["name"] + "Trigger"
	hole_area.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	hole_area.add_child(collision)
	hole_area.body_entered.connect(_on_trap_entered)
	board.add_child(hole_area)


func _build_deck_details() -> void:
	for offset in [-3.0, 0.0, 3.0]:
		_add_box_visual(board, Vector3(offset, 0.082, 0.0), Vector3(0.025, 0.012, 8.65), materials.brass_dark, "DeckSeamX")
		_add_box_visual(board, Vector3(0.0, 0.083, offset), Vector3(8.65, 0.012, 0.025), materials.brass_dark, "DeckSeamZ")

	for corner in [Vector3(-4.15, 0.12, -4.15), Vector3(4.15, 0.12, -4.15), Vector3(-4.15, 0.12, 4.15), Vector3(4.15, 0.12, 4.15)]:
		_add_cylinder_visual(board, corner, 0.11, 0.08, materials.brass, "BrassFastener")
		_add_cylinder_visual(board, corner + Vector3(0.0, 0.045, 0.0), 0.045, 0.025, materials.frame, "FastenerSlot")


func _add_wall(spec: Dictionary) -> void:
	var wall_name: String = spec["name"]
	var at: Vector3 = spec["position"]
	var size: Vector3 = spec["size"]
	var accent: bool = spec.get("accent", false)
	_add_box_part(wall_name, at, size, materials.wall, true)

	var rail_size := Vector3(maxf(0.16, size.x * 0.86), 0.075, maxf(0.16, size.z * 0.86))
	var rail_material: Material = materials.brass if accent else materials.brass_dark
	_add_box_visual(board, at + Vector3(0.0, size.y * 0.52, 0.0), rail_size, rail_material, wall_name + "TopRail")

	var long_on_x := size.x > size.z
	var end_offset := Vector3(size.x * 0.5, 0.0, 0.0) if long_on_x else Vector3(0.0, 0.0, size.z * 0.5)
	var post_radius := minf(0.17, minf(size.x, size.z) * 0.48)
	_add_cylinder_visual(board, at - end_offset, post_radius, size.y + 0.08, rail_material, wall_name + "PostA")
	_add_cylinder_visual(board, at + end_offset, post_radius, size.y + 0.08, rail_material, wall_name + "PostB")


func _build_wind_device(config: Dictionary) -> void:
	var origin: Vector3 = config["position"]
	_add_cylinder_visual(board, origin, 0.66, 0.055, materials.rubber, "WindVent")
	_add_torus_visual(board, origin + Vector3(0.0, 0.045, 0.0), 0.47, 0.64, materials.wind, "WindGlowRing")
	wind_rotor = Node3D.new()
	wind_rotor.name = "WindRotor"
	wind_rotor.position = origin + Vector3(0.0, 0.09, 0.0)
	board.add_child(wind_rotor)
	_add_cylinder_visual(wind_rotor, Vector3.ZERO, 0.12, 0.10, materials.brass, "WindHub")
	for index in range(4):
		var angle := index * TAU / 4.0
		var blade_position := Vector3(cos(angle) * 0.32, 0.0, -sin(angle) * 0.32)
		var blade := _add_box_visual(wind_rotor, blade_position, Vector3(0.48, 0.045, 0.16), materials.wind, "WindBlade")
		blade.rotation.y = angle


func _build_magnet_device(config: Dictionary) -> void:
	var origin: Vector3 = config["position"]
	_add_cylinder_visual(board, origin, 0.58, 0.08, materials.brass_dark, "MagnetBase")
	_add_torus_visual(board, origin + Vector3(0.0, 0.08, 0.0), 0.30, 0.52, materials.brass, "MagnetCoil")
	magnet_ring = _add_torus_visual(board, origin + Vector3(0.0, 0.13, 0.0), 0.53, 0.59, materials.magnet, "MagnetField")
	magnet_light = OmniLight3D.new()
	magnet_light.name = "MagnetGlow"
	magnet_light.position = origin + Vector3(0.0, 0.55, 0.0)
	magnet_light.light_color = Color("c071ff")
	magnet_light.light_energy = 1.8
	magnet_light.omni_range = 3.2
	board.add_child(magnet_light)


func _build_trap(config: Dictionary) -> void:
	var origin: Vector3 = config["position"]
	_add_cylinder_visual(board, origin, 0.56, 0.045, materials.frame, "ResetHatch")
	trap_ring = _add_torus_visual(board, origin + Vector3(0.0, 0.045, 0.0), 0.42, 0.57, materials.trap, "TrapWarning")
	for index in range(6):
		var angle := index * TAU / 6.0
		var tooth_position := origin + Vector3(cos(angle) * 0.43, 0.085, sin(angle) * 0.43)
		var tooth := _add_box_visual(board, tooth_position, Vector3(0.18, 0.04, 0.08), materials.brass_dark, "TrapTooth")
		tooth.rotation.y = -angle

	var trap_area := Area3D.new()
	trap_area.name = "TrapTrigger"
	trap_area.position = origin + Vector3(0.0, 0.25, 0.0)
	var trap_shape := CollisionShape3D.new()
	var trap_sphere := SphereShape3D.new()
	trap_sphere.radius = config["radius"]
	trap_shape.shape = trap_sphere
	trap_area.add_child(trap_shape)
	trap_area.body_entered.connect(_on_trap_entered)
	board.add_child(trap_area)


func _build_goal(origin: Vector3) -> void:
	_add_cylinder_visual(board, origin, 0.65, 0.055, materials.frame, "GoalSocket")
	_add_torus_visual(board, origin + Vector3(0.0, 0.055, 0.0), 0.38, 0.62, materials.brass, "GoalBrassRing")
	goal_ring = _add_torus_visual(board, origin + Vector3(0.0, 0.085, 0.0), 0.27, 0.36, materials.goal, "GoalGlow")

	# Proximity detection is intentionally broad, but does NOT complete a level.
	# The reusable socket requires the ball CENTRE to be inside and held steady.
	goal_detector = GoalSocketDetectorScript.new()
	goal_detector.name = "GoalTrigger"
	goal_detector.position = origin + Vector3(0.0, 0.28, 0.0)
	var goal_shape := CollisionShape3D.new()
	var goal_sphere := SphereShape3D.new()
	goal_sphere.radius = 0.68
	goal_shape.shape = goal_sphere
	goal_detector.add_child(goal_shape)
	goal_detector.body_captured.connect(_on_goal_entered)
	board.add_child(goal_detector)


func _build_ball() -> void:
	ball = RigidBody3D.new()
	ball.name = "PlayerMarble"
	ball.mass = BALL_MASS
	ball.continuous_cd = true
	ball.linear_damp = BALL_LINEAR_DAMP
	ball.angular_damp = BALL_ANGULAR_DAMP
	ball.position = level_data["start"]
	var ball_physics := PhysicsMaterial.new()
	ball_physics.friction = 0.58
	ball_physics.rough = true
	ball_physics.bounce = 0.08
	ball.physics_material_override = ball_physics

	var collider := CollisionShape3D.new()
	collider.name = "MarbleCollision"
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = BALL_RADIUS
	collider.shape = sphere_shape
	ball.add_child(collider)

	var shell := MeshInstance3D.new()
	shell.name = "PolishedMarble"
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = BALL_RADIUS
	sphere_mesh.height = BALL_RADIUS * 2.0
	shell.mesh = sphere_mesh
	shell.material_override = materials.marble
	ball.add_child(shell)

	var band := MeshInstance3D.new()
	band.name = "MarbleBrassBand"
	var band_mesh := TorusMesh.new()
	band_mesh.inner_radius = BALL_RADIUS * 0.82
	band_mesh.outer_radius = BALL_RADIUS * 0.99
	band.mesh = band_mesh
	band.material_override = materials.brass
	ball.add_child(band)
	add_child(ball)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "OrbitCamera"
	camera.current = true
	camera.fov = 43.0
	add_child(camera)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "Interface"
	add_child(canvas)
	hud_root = Control.new()
	hud_root.name = "SafeAreaHUD"
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud_root)

	info_panel = PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.04, 0.065, 0.88)
	panel_style.border_color = Color("a67a38")
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 16.0
	panel_style.content_margin_right = 16.0
	panel_style.content_margin_top = 10.0
	panel_style.content_margin_bottom = 9.0
	info_panel.add_theme_stylebox_override("panel", panel_style)
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(info_panel)

	var text_stack := VBoxContainer.new()
	info_panel.add_child(text_stack)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 21)
	status_label.add_theme_color_override("font_color", Color("f3dfb6"))
	text_stack.add_child(status_label)
	hint_label = Label.new()
	hint_label.text = _ui_text("LEFT: TILT BOARD  •  RIGHT: CAMERA", "СЛЕВА: НАКЛОН ДОСКИ  •  СПРАВА: КАМЕРА", "LINKS: BRETT NEIGEN  •  RECHTS: KAMERA")
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color("9fb3c9"))
	text_stack.add_child(hint_label)

	touch_help_left = Label.new()
	touch_help_left.text = "TILT BOARD\nBall rolls on its own"
	touch_help_left.add_theme_font_size_override("font_size", 17)
	touch_help_left.add_theme_color_override("font_color", Color("d1a05a", 0.83))
	touch_help_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_help_left.visible = OS.get_name() == "Android"
	hud_root.add_child(touch_help_left)
	touch_help_right = Label.new()
	touch_help_right.text = _ui_text("CAMERA\nDrag to look around", "КАМЕРА\nПроведи для обзора", "KAMERA\nWischen zum Drehen")
	touch_help_right.add_theme_font_size_override("font_size", 17)
	touch_help_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	touch_help_right.add_theme_color_override("font_color", Color("a6bad1", 0.78))
	touch_help_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_help_right.visible = OS.get_name() == "Android"
	hud_root.add_child(touch_help_right)

	tilt_indicator = TiltStickIndicatorScript.new()
	tilt_indicator.name = "TiltThumbIndicator"
	tilt_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tilt_indicator.size = Vector2(180.0, 180.0)
	tilt_indicator.visible = OS.get_name() == "Android"
	hud_root.add_child(tilt_indicator)

	button_row = HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	hud_root.add_child(button_row)

	level_selector = OptionButton.new()
	level_selector.custom_minimum_size = Vector2(140.0, 44.0)
	level_selector.focus_mode = Control.FOCUS_NONE
	level_selector.add_item("LEVEL 1 — WORKSHOP")
	level_selector.add_item("LEVEL 2 — FACTORY")
	level_selector.item_selected.connect(_on_level_selected)
	button_row.add_child(level_selector)
	mode_button = _hud_button("BOARD: DRAG", Vector2(155.0, 44.0))
	mode_button.pressed.connect(_cycle_control_mode)
	button_row.add_child(mode_button)
	calibrate_button = _hud_button(_ui_text("CALIBRATE", "КАЛИБР.", "KALIBR."), Vector2(94.0, 44.0))
	calibrate_button.pressed.connect(_on_calibrate_pressed)
	button_row.add_child(calibrate_button)
	view_button = _hud_button(_ui_text("VIEW", "ВИД", "ANS."), Vector2(55.0, 44.0))
	view_button.pressed.connect(_reset_camera_view)
	button_row.add_child(view_button)
	help_button = _hud_button("?", Vector2(42.0, 44.0))
	help_button.pressed.connect(_show_controls_help)
	button_row.add_child(help_button)
	var reset_button := _hud_button(_ui_text("RESET", "СБРОС", "NEUSTART"), Vector2(80.0, 44.0))
	reset_button.pressed.connect(_on_reset_pressed)
	button_row.add_child(reset_button)

	completion_overlay = CenterContainer.new()
	completion_overlay.name = "CompletionOverlay"
	completion_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	completion_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(completion_overlay)
	var completion_panel := PanelContainer.new()
	completion_panel.custom_minimum_size = Vector2(470.0, 210.0)
	var completion_style := panel_style.duplicate() as StyleBoxFlat
	completion_style.bg_color = Color(0.02, 0.035, 0.055, 0.97)
	completion_style.border_color = Color("d4a454")
	completion_style.set_border_width_all(2)
	completion_style.content_margin_left = 28.0
	completion_style.content_margin_right = 28.0
	completion_style.content_margin_top = 24.0
	completion_style.content_margin_bottom = 24.0
	completion_panel.add_theme_stylebox_override("panel", completion_style)
	completion_overlay.add_child(completion_panel)
	var completion_stack := VBoxContainer.new()
	completion_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	completion_stack.add_theme_constant_override("separation", 12)
	completion_panel.add_child(completion_stack)
	completion_title = Label.new()
	completion_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	completion_title.add_theme_font_size_override("font_size", 28)
	completion_title.add_theme_color_override("font_color", Color("f5d79c"))
	completion_stack.add_child(completion_title)
	completion_detail = Label.new()
	completion_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	completion_detail.add_theme_font_size_override("font_size", 17)
	completion_detail.add_theme_color_override("font_color", Color("aebfd0"))
	completion_stack.add_child(completion_detail)
	next_level_button = _hud_button("NEXT LEVEL", Vector2(210.0, 48.0))
	next_level_button.pressed.connect(_advance_level)
	completion_stack.add_child(next_level_button)
	completion_overlay.hide()
	_build_controls_help(panel_style)
	get_viewport().size_changed.connect(_layout_hud)
	_update_mode_button()
	_update_touch_help()
	_layout_hud()
	if OS.get_name() == "Android" and not FileAccess.file_exists("user://controls_help_seen.cfg"):
		_show_controls_help()


func _build_controls_help(panel_style: StyleBoxFlat) -> void:
	help_overlay = ColorRect.new()
	help_overlay.name = "ControlsHelpOverlay"
	help_overlay.color = Color(0.0, 0.0, 0.0, 0.74)
	help_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	help_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.add_child(help_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	help_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580.0, 280.0)
	var style := panel_style.duplicate() as StyleBoxFlat
	style.bg_color = Color(0.035, 0.055, 0.083, 0.98)
	style.border_color = Color("e4ae59")
	style.set_border_width_all(2)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	panel.add_child(stack)
	var title := Label.new()
	title.text = _ui_text("HOW TO CONTROL THE MARBLE", "КАК УПРАВЛЯТЬ ШАРИКОМ", "SO STEUERST DU DIE KUGEL")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("ffd28a"))
	stack.add_child(title)
	var content := Label.new()
	content.text = _ui_text(
		"LEFT: drag to TILT THE WHOLE BOARD. The ball rolls by itself.\nRIGHT: drag to rotate the CAMERA only.\nDRAG = finger control (recommended).\nPHONE = phone tilt (calibrate first).\nVIEW = restore the starting camera angle.",
		"СЛЕВА: веди пальцем — наклоняется ВСЯ ДОСКА.\nШар катится сам, ты не толкаешь его напрямую.\nСПРАВА: веди пальцем — поворачивается только КАМЕРА.\nРЕЖИМ «ПАЛЕЦ» — рекомендуемый.\n«ТЕЛЕФОН» — наклон корпуса после калибровки.\n«ВИД» — вернуть исходную камеру.",
		"LINKS: Mit dem Finger das BRETT NEIGEN. Die Kugel rollt selbst.\nRECHTS: Nur die KAMERA drehen.\nFINGER = empfohlen.\nHANDY = Neigungssensor (vorher kalibrieren).\nANSICHT = Kamera zurücksetzen."
	)
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.custom_minimum_size = Vector2(500.0, 0.0)
	content.add_theme_font_size_override("font_size", 18)
	content.add_theme_color_override("font_color", Color("dde5ef"))
	stack.add_child(content)
	var close := _hud_button(_ui_text("GOT IT / PLAY", "ПОНЯТНО / ИГРАТЬ", "VERSTANDEN / SPIELEN"), Vector2(210.0, 52.0))
	close.pressed.connect(_close_controls_help)
	stack.add_child(close)
	help_overlay.hide()


func _show_controls_help() -> void:
	if help_overlay:
		help_overlay.show()


func _close_controls_help() -> void:
	if help_overlay:
		help_overlay.hide()
	var file := FileAccess.open("user://controls_help_seen.cfg", FileAccess.WRITE)
	if file:
		file.store_string("seen=1")


func _reset_camera_view() -> void:
	yaw = deg_to_rad(32.0)
	pitch = deg_to_rad(52.0)
	orbit_distance = 13.6


func _ui_text(english: String, russian: String, german: String) -> String:
	var locale := TranslationServer.get_locale().left(2).to_lower()
	if locale == "ru":
		return russian
	if locale == "de":
		return german
	return english


func _update_touch_help() -> void:
	if touch_help_left:
		touch_help_left.text = _ui_text("PHONE TILT\nFinger drag off", "НАКЛОН ТЕЛЕФОНА\nЖест слева отключён", "HANDY NEIGEN\nFingersteuerung aus") if control_mode == ControlMode.SENSOR else _ui_text("TILT THE BOARD\nBall rolls naturally", "НАКЛОН ДОСКИ\nШар катится по уклону", "BRETT NEIGEN\nKugel rollt selbst")
	if touch_help_right:
		touch_help_right.text = _ui_text("CAMERA\nDrag to look around", "КАМЕРА\nПроведи для обзора", "KAMERA\nWischen zum Drehen")


func _hud_button(label_text: String, minimum_size: Vector2) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = minimum_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	return button


func _layout_hud(override_size := Vector2.ZERO) -> void:
	if not info_panel or not button_row:
		return
	var view_size: Vector2 = override_size if override_size != Vector2.ZERO else get_viewport().get_visible_rect().size
	var margins := _safe_viewport_margins(view_size)
	var left := margins.x + 16.0
	var top := margins.y + 14.0
	var right := margins.z + 16.0
	var available_width := maxf(200.0, view_size.x - left - right)
	var controls_width := maxf(466.0, button_row.get_combined_minimum_size().x)
	button_row.size = Vector2(controls_width, 46.0)
	button_row.scale = Vector2.ONE * minf(1.0, available_width / controls_width)
	if available_width >= 1050.0:
		info_panel.position = Vector2(left, top)
		info_panel.size = Vector2(minf(510.0, available_width - controls_width - 32.0), 76.0)
		button_row.position = Vector2(view_size.x - right - controls_width, top + 8.0)
	else:
		info_panel.position = Vector2(left, top)
		info_panel.size = Vector2(available_width, 76.0)
		button_row.position = Vector2(left, top + 84.0)
	# Scale the touch indicator to 150% of the original 120 px on ordinary
	# landscape displays, but keep it inside short screens and safe areas.
	var thumb_diameter := minf(180.0, maxf(118.0, view_size.y * 0.275))
	if tilt_indicator:
		tilt_indicator.size = Vector2.ONE * thumb_diameter
		tilt_indicator.position = Vector2(left + 6.0, view_size.y - margins.w - thumb_diameter - 18.0)
	if touch_help_left:
		touch_help_left.position = Vector2(left + thumb_diameter + 18.0, view_size.y - margins.w - 83.0)
	if touch_help_right:
		touch_help_right.position = Vector2(view_size.x - right - 235.0, view_size.y - margins.w - 83.0)


func _safe_viewport_margins(view_size: Vector2) -> Vector4:
	var screen_size := Vector2(DisplayServer.screen_get_size())
	var safe_area := DisplayServer.get_display_safe_area()
	if screen_size.x <= 0.0 or screen_size.y <= 0.0 or safe_area.size.x <= 0:
		return Vector4.ZERO
	var safe_scale := Vector2(view_size.x / screen_size.x, view_size.y / screen_size.y)
	var left := float(safe_area.position.x) * safe_scale.x
	var top := float(safe_area.position.y) * safe_scale.y
	var right := float(screen_size.x - safe_area.end.x) * safe_scale.x
	var bottom := float(screen_size.y - safe_area.end.y) * safe_scale.y
	return Vector4(left, top, right, bottom)


func _update_camera() -> void:
	if not camera:
		return
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.global_position = direction * orbit_distance
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)


func _animate_obstacles(delta: float) -> void:
	if wind_rotor:
		wind_rotor.rotation.y += delta * 3.8
	var pulse := 0.5 + 0.5 * sin(visual_time * 3.2)
	if magnet_light:
		magnet_light.light_energy = 1.25 + pulse * 1.0
	if magnet_ring:
		magnet_ring.scale = Vector3.ONE * (0.94 + pulse * 0.12)
	if trap_ring:
		trap_ring.rotation.y -= delta * 1.4
		trap_ring.scale = Vector3.ONE * (0.96 + pulse * 0.07)
	if goal_ring:
		goal_ring.rotation.y += delta * 1.2
		goal_ring.scale = Vector3.ONE * (0.96 + pulse * 0.10)


func _apply_environment_forces() -> void:
	var local_ball := board.to_local(ball.global_position)
	if level_data.has("wind"):
		var wind: Dictionary = level_data["wind"]
		var wind_origin: Vector3 = wind["position"]
		var wind_distance := Vector2(local_ball.x - wind_origin.x, local_ball.z - wind_origin.z).length()
		if wind_distance < float(wind["radius"]) and absf(local_ball.y - wind_origin.y) < 1.4:
			var local_wind_direction: Vector3 = wind["direction"]
			var wind_direction := board.global_basis * local_wind_direction
			var falloff := 1.0 - wind_distance / float(wind["radius"])
			ball.apply_central_force(wind_direction.normalized() * float(wind["force"]) * (0.35 + falloff * 0.65))

	if level_data.has("magnet"):
		var magnet: Dictionary = level_data["magnet"]
		var local_magnet_position: Vector3 = magnet["position"]
		var magnet_center := board.to_global(local_magnet_position)
		var pull := magnet_center - ball.global_position
		var magnet_distance := pull.length()
		if magnet_distance < float(magnet["radius"]) and magnet_distance > 0.12:
			var strength := float(magnet["force"]) * pow(1.0 - magnet_distance / float(magnet["radius"]), 1.35)
			ball.apply_central_force(pull.normalized() * strength)


func _update_hud() -> void:
	if not status_label:
		return
	if game_won:
		status_label.text = "L%02d  •  COMPLETE  •  %0.1f s" % [level_data["number"], elapsed]
	else:
		status_label.text = "L%02d  •  %s  •  %0.1f s" % [level_data["number"], level_data["title"].replace("THE ", ""), elapsed]
	if transient_message_time > 0.0:
		hint_label.text = transient_message
	else:
		if OS.get_name() == "Android":
			if control_mode == ControlMode.SENSOR:
				hint_label.text = _ui_text("TILT PHONE = ROLL BALL  •  RIGHT = CAMERA", "НАКЛОНИ ТЕЛЕФОН — ШАР ПОКАТИТСЯ  •  СПРАВА КАМЕРА", "HANDY NEIGEN = KUGEL ROLLT  •  RECHTS KAMERA")
			else:
				hint_label.text = _ui_text("LEFT = TILT BOARD  •  RIGHT = CAMERA", "СЛЕВА НАКЛОН ДОСКИ  •  СПРАВА КАМЕРА", "LINKS = BRETT NEIGEN  •  RECHTS = KAMERA")
		else:
			hint_label.text = "Arrows / left drag: tilt the board  •  Right drag: camera"
	if tilt_indicator and tilt_indicator.visible:
		tilt_indicator.call("set_tilt", _board_tilt_to_screen(active_tilt))


func _update_mode_button() -> void:
	if mode_button:
		mode_button.text = _ui_text("BOARD: ", "ДОСКА: ", "BRETT: ") + _control_mode_name()
	if calibrate_button:
		calibrate_button.visible = control_mode != ControlMode.TOUCH
	if button_row:
		_layout_hud()


func _control_mode_name() -> String:
	match control_mode:
		ControlMode.TOUCH:
			return _ui_text("DRAG", "ПАЛЕЦ", "FINGER")
		ControlMode.SENSOR:
			return _ui_text("PHONE", "ТЕЛЕФОН", "HANDY")
		_:
			return _ui_text("AUTO", "АВТО", "AUTO")


func _on_goal_entered(body: RigidBody3D) -> void:
	# Never trust an Area3D body_entered signal: its wide collision can overlap
	# a sphere that is still visibly OUTSIDE the goal socket.
	if body == ball and goal_detector and goal_detector.capture_complete and not game_won:
		game_won = true
		ball.linear_damp = 2.8
		ball.angular_damp = 1.6
		completion_title.text = "LEVEL %02d COMPLETE" % level_data["number"]
		completion_detail.text = "%s\nTime: %0.1f seconds" % [level_data["title"], elapsed]
		next_level_button.text = "NEXT: CLOCKWORK FACTORY" if current_level_index + 1 < LEVEL_SOURCES.size() else "REPLAY FACTORY"
		completion_overlay.show()


func _on_trap_entered(body: Node3D) -> void:
	if body == ball:
		respawn_queued = true


func _on_reset_pressed() -> void:
	respawn_queued = true


func _on_calibrate_pressed() -> void:
	_calibrate_sensor(true)


func _on_level_selected(index: int) -> void:
	if index != current_level_index:
		_load_level(index)


func _advance_level() -> void:
	if current_level_index + 1 < LEVEL_SOURCES.size():
		_load_level(current_level_index + 1)
	else:
		_load_level(current_level_index)


func _on_mechanism_message(message: String) -> void:
	_show_message(message, 4.0)


func _show_message(message: String, duration: float) -> void:
	transient_message = message
	transient_message_time = duration


func _reset_level() -> void:
	respawn_queued = false
	game_won = false
	elapsed = 0.0
	transient_message_time = 0.0
	drag_tilt = Vector2.ZERO
	tilt_touch_index = -1
	touch_start.clear()
	board.rotation = Vector3.ZERO
	if goal_detector:
		goal_detector.reset_capture()
	if clockwork:
		clockwork.reset_state()
	ball.linear_damp = BALL_LINEAR_DAMP
	ball.angular_damp = BALL_ANGULAR_DAMP
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	var start_position: Vector3 = level_data["start"]
	ball.global_position = board.to_global(start_position)
	ball.sleeping = false
	if completion_overlay:
		completion_overlay.hide()


func _add_box_part(part_name: String, at: Vector3, size: Vector3, material: Material, with_collision: bool) -> MeshInstance3D:
	if with_collision:
		var collision := CollisionShape3D.new()
		collision.name = part_name + "Collision"
		collision.position = at
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		board.add_child(collision)
	return _add_box_visual(board, at, size, material, part_name)


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


func _metal(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := _metal(color.darkened(0.38), 0.46, 0.22)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
