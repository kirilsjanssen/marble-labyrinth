extends Node3D
class_name WaterLab
## Interactive two-reservoir P2 laboratory.

var network := WaterNetwork.new()
var valve := WaterValve.new()
var pump := WaterPump.new()
var connection := WaterConnection.new()
var force_system := WaterBallForces.new()
var volume_a: WaterVolume
var volume_b: WaterVolume
var visual_a: WaterSurfaceVisual
var visual_b: WaterSurfaceVisual
var balls: Dictionary = {}
var tilt := 0.0
var status_label: Label


func _ready() -> void:
	_build_environment()
	_setup_hydraulics()
	_build_tank("ReservoirA", Vector3(-3.0, 0.0, 0.0), &"A")
	_build_tank("ReservoirB", Vector3(3.0, 0.0, 0.0), &"B")
	_build_channel()
	_spawn_balls()
	_build_hud()


func _physics_process(delta: float) -> void:
	var keyboard_tilt := Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	if absf(keyboard_tilt) > 0.01:
		set_tilt(keyboard_tilt)
	network.step(delta)
	var flux := connection.last_flux
	volume_a.flow_velocity = Vector3.RIGHT * flux * 0.35
	volume_b.flow_velocity = Vector3.RIGHT * flux * 0.35


func _process(_delta: float) -> void:
	if status_label:
		status_label.text = "WATER LAB  |  A %.2f  B %.2f  Total %.2f\nValve %s  Pump %s  Tilt %+.1f  Flux %+.2f" % [
			network.volume(&"A"), network.volume(&"B"), network.total_volume(),
			"OPEN" if valve.is_open() else "CLOSED", "ON" if pump.enabled else "OFF", tilt, connection.last_flux
		]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_V: toggle_valve()
			KEY_P: toggle_pump()
			KEY_R: reset_lab()


func _setup_hydraulics() -> void:
	add_child(network)
	network.add_reservoir(&"A", 10.0, 8.0, 5.0, 0.0)
	network.add_reservoir(&"B", 10.0, 2.0, 5.0, 0.0)
	valve.openness = 0.0
	pump.enabled = false
	pump.direction = -1.0
	pump.flow_rate = 1.4
	pump.max_head = 5.0
	connection.reservoir_a = &"A"
	connection.reservoir_b = &"B"
	connection.conductance = 1.2
	connection.max_flow = 2.2
	connection.valve = valve
	connection.pump = pump
	network.add_connection(connection)
	add_child(force_system)


func _build_tank(tank_name: String, at: Vector3, reservoir_id: StringName) -> void:
	_add_static_box(tank_name + "Floor", at + Vector3(0.0, -1.1, 0.0), Vector3(4.2, 0.2, 4.2), Color("364657"))
	_add_static_box(tank_name + "NorthWall", at + Vector3(0.0, 0.0, -2.05), Vector3(4.2, 2.2, 0.15), Color("52687c"))
	_add_static_box(tank_name + "SouthWall", at + Vector3(0.0, 0.0, 2.05), Vector3(4.2, 2.2, 0.15), Color("52687c"))
	_add_static_box(tank_name + "OuterWall", at + Vector3(-2.05 if reservoir_id == &"A" else 2.05, 0.0, 0.0), Vector3(0.15, 2.2, 4.2), Color("52687c"))
	var volume := WaterVolume.new()
	volume.name = tank_name + "WaterVolume"
	volume.position = at
	volume.setup(network, reservoir_id, Vector3(4.0, 2.0, 4.0))
	add_child(volume)
	force_system.register_volume(volume)
	var visual := WaterSurfaceVisual.new()
	visual.name = tank_name + "WaterVisual"
	add_child(visual)
	visual.setup(volume)
	if reservoir_id == &"A":
		volume_a = volume
		visual_a = visual
	else:
		volume_b = volume
		visual_b = visual


func _build_channel() -> void:
	_add_static_box("ChannelFloor", Vector3(0.0, -0.72, 0.0), Vector3(2.0, 0.12, 1.0), Color("8a633b"))
	_add_static_box("ChannelNorthRail", Vector3(0.0, -0.32, -0.52), Vector3(2.0, 0.8, 0.12), Color("b88a4b"))
	_add_static_box("ChannelSouthRail", Vector3(0.0, -0.32, 0.52), Vector3(2.0, 0.8, 0.12), Color("b88a4b"))


func _spawn_balls() -> void:
	balls["WoodBall"] = _spawn_ball("WoodBall", Vector3(-3.6, 0.25, 0.0), &"wood")
	balls["HollowBall"] = _spawn_ball("HollowBall", Vector3(-2.4, 0.25, 0.0), &"hollow")
	balls["SteelBall"] = _spawn_ball("SteelBall", Vector3(3.0, 0.25, 0.0), &"magnetic_steel")


func _spawn_ball(ball_name: String, at: Vector3, material_id: StringName) -> PhysicsBall:
	var ball := PhysicsBall.new()
	ball.name = ball_name
	ball.position = at
	ball.material_id = material_id
	add_child(ball)
	ball.set_meta("initial_position", at)
	return ball


func set_tilt(value: float) -> void:
	tilt = clampf(value, -1.0, 1.0)
	network.set_tilt_head(&"A", tilt * 1.1)
	network.set_tilt_head(&"B", -tilt * 1.1)


func toggle_valve() -> void:
	valve.openness = 0.0 if valve.is_open() else 1.0


func toggle_pump() -> void:
	pump.enabled = not pump.enabled


func reset_lab() -> void:
	network.reset()
	valve.openness = 0.0
	pump.enabled = false
	tilt = 0.0
	for ball_name in balls:
		var ball: PhysicsBall = balls[ball_name]
		ball.global_position = ball.get_meta("initial_position")
		ball.linear_velocity = Vector3.ZERO
		ball.angular_velocity = Vector3.ZERO
		ball.sleeping = false


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0a1119")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8ea9c2")
	environment.ambient_light_energy = 0.72
	world.environment = environment
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -28.0, 0.0)
	light.light_energy = 1.8
	light.shadow_enabled = true
	add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(10.5, 10.0, 13.5)
	camera.look_at_from_position(camera.position, Vector3(0.0, -0.2, 0.0))
	camera.current = true
	add_child(camera)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(520.0, 100.0)
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	status_label = Label.new()
	box.add_child(status_label)
	var row := HBoxContainer.new()
	box.add_child(row)
	_add_button(row, "TILT LEFT", func() -> void: set_tilt(-1.0))
	_add_button(row, "LEVEL", func() -> void: set_tilt(0.0))
	_add_button(row, "TILT RIGHT", func() -> void: set_tilt(1.0))
	_add_button(row, "VALVE", toggle_valve)
	_add_button(row, "PUMP", toggle_pump)
	_add_button(row, "RESET", reset_lab)


func _add_button(parent: Control, title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(84.0, 46.0)
	button.pressed.connect(callback)
	parent.add_child(button)


func _add_static_box(node_name: String, at: Vector3, box_size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	collision.shape = shape
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	body.add_child(visual)
	add_child(body)
