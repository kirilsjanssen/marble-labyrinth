extends SceneTree
## Simulate phone input without an Android emulator. The actual hardware sensor
## still needs to be validated on a physical device.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if not _require(scene != null, "Main scene must load"):
		return
	var game := scene.instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame
	if not _require(game._default_control_mode("Android") == game.ControlMode.TOUCH, "Android must start in explicit finger-drag mode, not mixed AUTO"):
		return
	game._cycle_control_mode() # Linux test starts in AUTO; first step is TOUCH
	if not _require(game.mode_button.text.find("DRAG") >= 0 or game.mode_button.text.find("ПАЛЕЦ") >= 0 or game.mode_button.text.find("FINGER") >= 0, "Mode button must describe gesture clearly"):
		return
	if not _require(game.tilt_indicator != null and game.help_overlay != null, "Gesture pad and help overlay must exist"):
		return
	game._show_controls_help()
	if not _require(game._touch_on_hud(Vector2(350.0, 350.0)), "Tutorial must intercept background touches"):
		return
	game._close_controls_help()
	var tilt_first: Vector2 = game._screen_drag_to_board_tilt(Vector2.RIGHT)
	game.yaw = deg_to_rad(130.0)
	game._update_camera()
	var tilt_rotated: Vector2 = game._screen_drag_to_board_tilt(Vector2.RIGHT)
	if not _require(tilt_first.distance_to(tilt_rotated) > 0.5, "Board tilt direction must respond to camera orbit"):
		return
	game._reset_camera_view()
	game._update_camera()
	game._layout_hud(Vector2(1280.0, 720.0))

	if not _require(game.hud_root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Full-screen HUD must not intercept touchscreen drags"):
		return
	if not _require(game.info_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Status panel must not block touch"):
		return
	if not _require(game.info_panel.position.x + game.info_panel.size.x < game.button_row.position.x, "Desktop HUD panels must not overlap"):
		return
	if not _require(game.button_row.position.x + game.button_row.size.x * game.button_row.scale.x <= 1280.0, "HUD buttons must fit within landscape viewport"):
		return

	var outside_ui := InputEventScreenTouch.new()
	outside_ui.index = 0
	outside_ui.position = Vector2(30.0, 30.0)
	outside_ui.pressed = true
	Input.parse_input_event(outside_ui)
	await process_frame
	if not _require(game.tilt_touch_index == -1, "HUD touches must not tilt the board"):
		return

	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = Vector2(80.0, 390.0)
	touch.pressed = true
	Input.parse_input_event(touch)
	await process_frame
	if not _require(game.tilt_touch_index == 0, "Left-side touch must be captured"):
		return

	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(220.0, 390.0)
	drag.relative = Vector2(140.0, 0.0)
	Input.parse_input_event(drag)
	await process_frame
	if not _require(game.drag_tilt.x > 0.80, "Left drag must produce a strong physical tilt"):
		return

	var marble_before: Vector3 = game.ball.global_position
	await _wait_physics_frames(30)
	if not _require(game.board.rotation.z < -0.12, "Screen drag must rotate the physics board"):
		return
	if not _require(game.ball.global_position.distance_to(marble_before) > 0.10, "Touch tilt must physically MOVE the rigid marble, not only rotate the board"):
		return
	if not _require(game.ball.linear_velocity.length() > 0.08, "Physical marble must have measurable momentum"):
		return

	var camera_touch := InputEventScreenTouch.new()
	camera_touch.index = 1
	camera_touch.position = Vector2(1100.0, 400.0)
	camera_touch.pressed = true
	Input.parse_input_event(camera_touch)
	await process_frame
	var yaw_before: float = game.yaw
	var camera_drag := InputEventScreenDrag.new()
	camera_drag.index = 1
	camera_drag.position = Vector2(1030.0, 410.0)
	camera_drag.relative = Vector2(-70.0, 10.0)
	Input.parse_input_event(camera_drag)
	await process_frame
	if not _require(absf(game.yaw - yaw_before) > 0.1, "Right-hand swipe must orbit camera while left finger tilts"):
		return
	if not _require(game.drag_tilt.x > 0.8, "Second finger must not cancel first finger tilt"):
		return

	touch.pressed = false
	Input.parse_input_event(touch)
	await process_frame
	if not _require(game.drag_tilt == Vector2.ZERO and game.tilt_touch_index == -1, "Releasing left touch must centre board input"):
		return
	camera_touch.pressed = false
	Input.parse_input_event(camera_touch)
	await process_frame

	game.sensor_calibrated = true
	game.sensor_zero = Vector2.ZERO
	var simulated_gravity_tilt: Vector2 = game._tilt_from_gravity(Vector3(3.0, -2.0, 8.0))
	if not _require(simulated_gravity_tilt.x > 0.4 and simulated_gravity_tilt.y > 0.2, "Sensor mapping must respond to simulated gravity"):
		return

	game._layout_hud(Vector2(800.0, 600.0))
	if not _require(game.button_row.position.y > game.info_panel.position.y + 70.0, "HUD controls must use second row on narrow screens"):
		return
	print("MOBILE CONTROLS PASS: touch capture, REAL MARBLE MOTION, camera orbit, simultaneous multitouch, release, HUD layout and sensor mapping")
	quit(0)


func _wait_physics_frames(count: int) -> void:
	for _i in range(count):
		await physics_frame


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("MOBILE CONTROLS FAIL: " + message)
	quit(1)
	return false
