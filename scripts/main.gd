extends Node3D
## Runtime controller for a miniature mechanical labyrinth. Geometry is generated
## from level data, while the marble remains a real RigidBody3D at all times.

const Level01 = preload("res://scripts/levels/level_01.gd")

const MAX_TILT := deg_to_rad(15.0)
const TILT_RESPONSE := 5.5
const BALL_RADIUS := 0.33
const BALL_MASS := 0.34
const BALL_LINEAR_DAMP := 0.12
const BALL_ANGULAR_DAMP := 0.08
const TOUCH_TILT_DISTANCE := 180.0
const SENSOR_RANGE := 5.5

enum ControlMode { AUTO, TOUCH, SENSOR }

var level_data: Dictionary = Level01.definition()
var board: AnimatableBody3D
var ball: RigidBody3D
var camera: Camera3D
var status_label: Label
var hint_label: Label
var mode_button: Button
var wind_rotor: Node3D
var magnet_light: OmniLight3D
var magnet_ring: MeshInstance3D
var trap_ring: MeshInstance3D
var goal_ring: MeshInstance3D

var materials: Dictionary = {}
var touch_start: Dictionary = {}
var drag_tilt := Vector2.ZERO
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


func _ready() -> void:
	_build_materials()
	_build_environment()
	_build_board()
	_build_ball()
	_build_camera()
	_build_hud()
	_calibrate_sensor(false)
	_update_camera()


func _physics_process(delta: float) -> void:
	if respawn_queued:
		_reset_level()

	var tilt := _read_tilt_input()
	var target_rotation := Vector3(-tilt.y * MAX_TILT, 0.0, -tilt.x * MAX_TILT)
	var weight := clampf(delta * TILT_RESPONSE, 0.0, 1.0)
	board.rotation.x = lerp_angle(board.rotation.x, target_rotation.x, weight)
	board.rotation.z = lerp_angle(board.rotation.z, target_rotation.z, weight)

	if not game_won:
		elapsed += delta
		_apply_environment_forces()
		if ball.global_position.y < -2.5 or ball.global_position.length() > 25.0:
			respawn_queued = true


func _process(delta: float) -> void:
	visual_time += delta
	_update_camera()
	_animate_obstacles(delta)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				respawn_queued = true
			KEY_G, KEY_M:
				_cycle_control_mode()
			KEY_C:
				_calibrate_sensor(true)

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_orbit_camera(event.relative, 0.008)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = maxf(10.5, orbit_distance - 0.7)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = minf(17.0, orbit_distance + 0.7)

	if event is InputEventScreenTouch:
		if event.pressed:
			touch_start[event.index] = event.position
		else:
			if touch_start.has(event.index):
				var start: Vector2 = touch_start[event.index]
				if start.x < get_viewport().get_visible_rect().size.x * 0.5:
					drag_tilt = Vector2.ZERO
			touch_start.erase(event.index)
	elif event is InputEventScreenDrag and touch_start.has(event.index):
		var start: Vector2 = touch_start[event.index]
		if start.x < get_viewport().get_visible_rect().size.x * 0.5:
			if control_mode != ControlMode.SENSOR:
				drag_tilt = ((event.position - start) / TOUCH_TILT_DISTANCE).limit_length(1.0)
		else:
			_orbit_camera(event.relative, 0.009)


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


func _sensor_tilt() -> Vector2:
	var gravity := Input.get_gravity()
	if gravity.length_squared() < 1.0:
		return Vector2.ZERO
	var reading := Vector2(gravity.x, -gravity.y)
	if sensor_calibrated:
		reading -= Vector2(sensor_zero.x, -sensor_zero.y)
	return (reading / SENSOR_RANGE).limit_length(1.0)


func _calibrate_sensor(show_feedback: bool) -> void:
	var gravity := Input.get_gravity()
	if gravity.length_squared() >= 1.0:
		sensor_zero = Vector2(gravity.x, gravity.y)
		sensor_calibrated = true
		if show_feedback:
			hint_label.text = "Sensor centred. Hold the phone here to keep the board level."
	elif show_feedback:
		hint_label.text = "No motion sensor detected. Touch, keyboard and mouse remain available."


func _cycle_control_mode() -> void:
	control_mode = ((control_mode + 1) % ControlMode.size()) as ControlMode
	drag_tilt = Vector2.ZERO
	if control_mode == ControlMode.SENSOR:
		_calibrate_sensor(false)
	_update_mode_button()


func _orbit_camera(relative: Vector2, sensitivity: float) -> void:
	yaw -= relative.x * sensitivity
	pitch = clampf(pitch + relative.y * sensitivity * 0.75, deg_to_rad(24.0), deg_to_rad(74.0))


func _build_materials() -> void:
	materials = {
		"frame": _metal(Color("171d26"), 0.88, 0.20),
		"deck": _metal(Color("242d38"), 0.72, 0.28),
		"wall": _metal(Color("354252"), 0.82, 0.22),
		"brass": _metal(Color("b58a43"), 0.92, 0.20),
		"brass_dark": _metal(Color("735126"), 0.86, 0.29),
		"marble": _metal(Color("d9e7ef"), 0.92, 0.08),
		"rubber": _metal(Color("11161c"), 0.15, 0.72),
		"wind": _emissive_material(Color("42c9ff"), 1.5),
		"magnet": _emissive_material(Color("c071ff"), 1.45),
		"trap": _emissive_material(Color("ff4d55"), 1.2),
		"goal": _emissive_material(Color("55e7a0"), 1.4),
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


func _build_board() -> void:
	board = AnimatableBody3D.new()
	board.name = "TiltingBoard"
	board.sync_to_physics = true
	var board_physics := PhysicsMaterial.new()
	board_physics.friction = 0.64
	board_physics.bounce = 0.06
	board.physics_material_override = board_physics
	add_child(board)

	_add_box_part("Board", Vector3(0.0, -0.16, 0.0), Vector3(9.55, 0.36, 9.55), materials.frame, true)
	_add_box_part("DeckInset", Vector3(0.0, 0.035, 0.0), Vector3(9.05, 0.08, 9.05), materials.deck, false)
	_add_box_part("LowerBrassBand", Vector3(0.0, -0.30, 0.0), Vector3(9.75, 0.10, 9.75), materials.brass_dark, false)
	_build_deck_details()

	for wall_spec: Dictionary in level_data["walls"]:
		_add_wall(wall_spec)

	_build_wind_device(level_data["wind"])
	_build_magnet_device(level_data["magnet"])
	_build_trap(level_data["trap"])
	_build_goal(level_data["goal"])


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

	var goal_area := Area3D.new()
	goal_area.name = "GoalTrigger"
	goal_area.position = origin + Vector3(0.0, 0.28, 0.0)
	var goal_shape := CollisionShape3D.new()
	var goal_sphere := SphereShape3D.new()
	goal_sphere.radius = 0.68
	goal_shape.shape = goal_sphere
	goal_area.add_child(goal_shape)
	goal_area.body_entered.connect(_on_goal_entered)
	board.add_child(goal_area)


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

	var info_panel := PanelContainer.new()
	info_panel.position = Vector2(18.0, 16.0)
	info_panel.size = Vector2(660.0, 88.0)
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
	canvas.add_child(info_panel)

	var text_stack := VBoxContainer.new()
	info_panel.add_child(text_stack)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 21)
	status_label.add_theme_color_override("font_color", Color("f3dfb6"))
	text_stack.add_child(status_label)
	hint_label = Label.new()
	hint_label.text = "Arrows / left drag: tilt  •  Right drag: orbit  •  R: reset  •  G: controls  •  C: calibrate"
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color("9fb3c9"))
	text_stack.add_child(hint_label)

	var button_row := HBoxContainer.new()
	button_row.anchor_left = 1.0
	button_row.anchor_right = 1.0
	button_row.offset_left = -396.0
	button_row.offset_right = -18.0
	button_row.offset_top = 16.0
	button_row.offset_bottom = 58.0
	button_row.add_theme_constant_override("separation", 8)
	canvas.add_child(button_row)

	mode_button = _hud_button("CONTROL: AUTO", Vector2(154.0, 42.0))
	mode_button.pressed.connect(_cycle_control_mode)
	button_row.add_child(mode_button)
	var calibrate_button := _hud_button("CALIBRATE", Vector2(106.0, 42.0))
	calibrate_button.pressed.connect(_on_calibrate_pressed)
	button_row.add_child(calibrate_button)
	var reset_button := _hud_button("RESET", Vector2(92.0, 42.0))
	reset_button.pressed.connect(_on_reset_pressed)
	button_row.add_child(reset_button)


func _hud_button(label_text: String, minimum_size: Vector2) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = minimum_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	return button


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
	var wind: Dictionary = level_data["wind"]
	var wind_origin: Vector3 = wind["position"]
	var wind_distance := Vector2(local_ball.x - wind_origin.x, local_ball.z - wind_origin.z).length()
	if wind_distance < float(wind["radius"]) and absf(local_ball.y - wind_origin.y) < 1.4:
		var local_wind_direction: Vector3 = wind["direction"]
		var wind_direction := board.global_basis * local_wind_direction
		var falloff := 1.0 - wind_distance / float(wind["radius"])
		ball.apply_central_force(wind_direction.normalized() * float(wind["force"]) * (0.35 + falloff * 0.65))

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
		status_label.text = "%s   •   COMPLETE IN %0.1f s   •   R TO REPLAY" % [level_data["title"], elapsed]
	else:
		status_label.text = "%s   •   %05.1f s   •   %s" % [level_data["title"], elapsed, _control_mode_name()]


func _update_mode_button() -> void:
	if mode_button:
		mode_button.text = "CONTROL: " + _control_mode_name()


func _control_mode_name() -> String:
	match control_mode:
		ControlMode.TOUCH:
			return "TOUCH"
		ControlMode.SENSOR:
			return "SENSOR"
		_:
			return "AUTO"


func _on_goal_entered(body: Node3D) -> void:
	if body == ball and not game_won:
		game_won = true
		ball.linear_damp = 2.8
		ball.angular_damp = 1.6


func _on_trap_entered(body: Node3D) -> void:
	if body == ball:
		respawn_queued = true


func _on_reset_pressed() -> void:
	respawn_queued = true


func _on_calibrate_pressed() -> void:
	_calibrate_sensor(true)


func _reset_level() -> void:
	respawn_queued = false
	game_won = false
	elapsed = 0.0
	drag_tilt = Vector2.ZERO
	board.rotation = Vector3.ZERO
	ball.linear_damp = BALL_LINEAR_DAMP
	ball.angular_damp = BALL_ANGULAR_DAMP
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	var start_position: Vector3 = level_data["start"]
	ball.global_position = board.to_global(start_position)
	ball.sleeping = false


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
