extends Node3D
## First playable level: a real RigidBody3D ball on a tilting static labyrinth.
## Everything is procedurally generated so the repository stays tiny.

const BOARD_SIZE := 9.0
const MAX_TILT := deg_to_rad(16.0)
const TILT_SMOOTH := 5.0
const BALL_START := Vector3(-3.1, 0.65, 3.3)
const GOAL_AT := Vector3(3.25, 0.15, -3.2)

var board: Node3D
var ball: RigidBody3D
var camera: Camera3D
var status_label: Label
var yaw := deg_to_rad(30.0)
var pitch := deg_to_rad(50.0)
var orbit_distance := 13.5
var touch_start: Dictionary = {}
var drag_tilt := Vector2.ZERO
var gyro_enabled := true
var game_won := false
var respawn_queued := false
var elapsed := 0.0


func _ready() -> void:
	_build_lighting()
	board = Node3D.new()
	board.name = "TiltingBoard"
	add_child(board)
	_build_level()
	_build_ball()
	_build_camera()
	_build_hud()
	_update_camera()


func _physics_process(delta: float) -> void:
	if respawn_queued:
		_reset_ball()

	if not game_won:
		elapsed += delta

	var tilt := drag_tilt
	var keys := Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	)
	if keys.length_squared() > 0.01:
		tilt = keys.normalized()
	elif gyro_enabled:
		var gravity_vector := Input.get_gravity()
		if gravity_vector.length_squared() > 1.0:
			# Experimental mapping: calibrate and verify on a real phone.
			tilt = Vector2(gravity_vector.x / 7.0, -gravity_vector.y / 7.0)
	
	tilt = tilt.limit_length(1.0)
	board.rotation.z = lerp_angle(board.rotation.z, -tilt.x * MAX_TILT, delta * TILT_SMOOTH)
	board.rotation.x = lerp_angle(board.rotation.x, -tilt.y * MAX_TILT, delta * TILT_SMOOTH)

	if not game_won:
		_apply_environment_forces()
		if ball.global_position.y < -2.5:
			respawn_queued = true


func _process(_delta: float) -> void:
	_update_camera()
	if not game_won:
		status_label.text = "LABYRINTH 01     %0.1f s     R: restart     G: sensor" % elapsed


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			respawn_queued = true
		if event.keycode == KEY_G:
			gyro_enabled = not gyro_enabled
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.008
		pitch = clampf(pitch + event.relative.y * 0.006, deg_to_rad(20.0), deg_to_rad(80.0))
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_start[event.index] = event.position
		else:
			if touch_start.has(event.index) and touch_start[event.index].x < get_viewport().get_visible_rect().size.x * 0.5:
				drag_tilt = Vector2.ZERO
			touch_start.erase(event.index)
	if event is InputEventScreenDrag and touch_start.has(event.index):
		var start: Vector2 = touch_start[event.index]
		if start.x < get_viewport().get_visible_rect().size.x * 0.5:
			drag_tilt = ((event.position - start) / 170.0).limit_length(1.0)
		else:
			yaw -= event.relative.x * 0.009
			pitch = clampf(pitch + event.relative.y * 0.006, deg_to_rad(20.0), deg_to_rad(80.0))


func _build_lighting() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b1019")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a9b2c9")
	env.ambient_light_energy = 0.72
	environment.environment = env
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, -15)
	sun.light_color = Color("fff0cc")
	sun.light_energy = 1.85
	sun.shadow_enabled = true
	add_child(sun)

	var accent := OmniLight3D.new()
	accent.position = Vector3(-3, 5, -2)
	accent.light_color = Color("58b9ff")
	accent.light_energy = 1.2
	accent.omni_range = 15.0
	add_child(accent)


func _build_level() -> void:
	var graphite := _material(Color("222a37"), 0.6, 0.22)
	var brass := _material(Color("a88444"), 0.75, 0.26)
	var dark_metal := _material(Color("354457"), 0.75, 0.25)

	_static_box(board, Vector3(0, -0.16, 0), Vector3(BOARD_SIZE, 0.30, BOARD_SIZE), graphite, "BoardBase")
	_static_box(board, Vector3(-4.55, 0.22, 0), Vector3(0.25, 0.7, 9.2), brass, "WestWall")
	_static_box(board, Vector3(4.55, 0.22, 0), Vector3(0.25, 0.7, 9.2), brass, "EastWall")
	_static_box(board, Vector3(0, 0.22, -4.55), Vector3(9.2, 0.7, 0.25), brass, "NorthWall")
	_static_box(board, Vector3(0, 0.22, 4.55), Vector3(9.2, 0.7, 0.25), brass, "SouthWall")

	# Narrow corridors with two ways around the central obstruction.
	_static_box(board, Vector3(-1.6, 0.22, 2.4), Vector3(0.25, 0.55, 3.0), dark_metal, "CorridorA")
	_static_box(board, Vector3(0.8, 0.22, 1.0), Vector3(3.0, 0.55, 0.25), dark_metal, "CorridorB")
	_static_box(board, Vector3(-1.25, 0.22, -1.6), Vector3(3.0, 0.55, 0.25), dark_metal, "CorridorC")
	_static_box(board, Vector3(2.4, 0.22, -1.6), Vector3(0.25, 0.55, 2.7), dark_metal, "CorridorD")

	_marker(Vector3(-2.5, 0.015, -1.1), 0.56, Color("55baff"), "AIR PUSH")
	_marker(Vector3(3.0, 0.015, 0.1), 0.6, Color("bb70ff"), "MAGNET")
	_marker(Vector3(0.0, 0.015, -3.1), 0.58, Color("ff5b59"), "TRAP")
	_marker(GOAL_AT, 0.63, Color("65e5a2"), "GOAL")

	var goal := Area3D.new()
	goal.name = "GoalTrigger"
	goal.position = GOAL_AT + Vector3.UP * 0.25
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.68
	shape.shape = sphere
	goal.add_child(shape)
	goal.body_entered.connect(_on_goal_entered)
	board.add_child(goal)

	var trap := Area3D.new()
	trap.name = "TrapTrigger"
	trap.position = Vector3(0, 0.28, -3.1)
	var trap_shape := CollisionShape3D.new()
	var trap_sphere := SphereShape3D.new()
	trap_sphere.radius = 0.54
	trap_shape.shape = trap_sphere
	trap.add_child(trap_shape)
	trap.body_entered.connect(_on_trap_entered)
	board.add_child(trap)


func _build_ball() -> void:
	ball = RigidBody3D.new()
	ball.name = "PlayerMarble"
	ball.mass = 0.3
	ball.continuous_cd = true
	ball.position = BALL_START
	var physical := PhysicsMaterial.new()
	physical.friction = 0.72
	physical.bounce = 0.11
	ball.physics_material_override = physical
	var collider := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.34
	collider.shape = shape
	ball.add_child(collider)
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.34
	sphere.height = 0.68
	mesh.mesh = sphere
	mesh.material_override = _material(Color("dceaf8"), 0.86, 0.11)
	ball.add_child(mesh)
	add_child(ball)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 44.0
	add_child(camera)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	status_label = Label.new()
	status_label.position = Vector2(23, 20)
	status_label.add_theme_font_size_override("font_size", 22)
	status_label.add_theme_color_override("font_color", Color("f7e8c8"))
	canvas.add_child(status_label)
	var hint := Label.new()
	hint.position = Vector2(23, 57)
	hint.text = "Tilt phone / arrows • Left drag: board • Right drag: camera"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color("a9bacc"))
	canvas.add_child(hint)


func _update_camera() -> void:
	var distance := orbit_distance
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.global_position = direction * distance
	camera.look_at(Vector3(0, 0.0, 0), Vector3.UP)


func _apply_environment_forces() -> void:
	var wind_center := board.to_global(Vector3(-2.5, 0.1, -1.1))
	if ball.global_position.distance_to(wind_center) < 1.15:
		ball.apply_central_force(Vector3(7.0, 0.0, -2.0))

	var magnet_center := board.to_global(Vector3(3.0, 0.1, 0.1))
	var pull := magnet_center - ball.global_position
	if pull.length() < 2.3 and pull.length() > 0.15:
		ball.apply_central_force(pull.normalized() * 6.0)


func _marker(at: Vector3, radius: float, color: Color, marker_name: String) -> void:
	var visual := MeshInstance3D.new()
	visual.name = marker_name
	visual.position = at
	var cylinder := CylinderMesh.new()
	cylinder.height = 0.025
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	visual.mesh = cylinder
	var glow := _material(color, 0.15, 0.35)
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 0.9
	visual.material_override = glow
	board.add_child(visual)


func _static_box(parent: Node3D, at: Vector3, size: Vector3, mat: Material, name_: String) -> void:
	var solid := StaticBody3D.new()
	solid.name = name_
	solid.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	solid.add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = mat
	solid.add_child(visual)
	parent.add_child(solid)


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


func _on_goal_entered(body: Node3D) -> void:
	if body == ball and not game_won:
		game_won = true
		status_label.text = "LEVEL COMPLETE — %0.1f s     R: retry" % elapsed
		ball.linear_damp = 4.0


func _on_trap_entered(body: Node3D) -> void:
	if body == ball:
		respawn_queued = true


func _reset_ball() -> void:
	respawn_queued = false
	game_won = false
	elapsed = 0.0
	ball.linear_damp = 0.0
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = BALL_START
	ball.sleeping = false

