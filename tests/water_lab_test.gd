extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/labs/water_lab.tscn") as PackedScene
	if not _require(packed != null, "Water Lab scene must load"):
		return
	var lab := packed.instantiate() as WaterLab
	root.add_child(lab)
	await process_frame
	await physics_frame
	var initial_a := lab.network.volume(&"A")
	var initial_b := lab.network.volume(&"B")
	await _wait_frames(60)
	if not _require(is_equal_approx(lab.network.volume(&"A"), initial_a), "closed lab valve must hold initial volumes"):
		return
	lab.toggle_valve()
	lab.set_tilt(1.0)
	await _wait_frames(180)
	if not _require(lab.network.volume(&"A") < initial_a - 0.5 and lab.network.volume(&"B") > initial_b + 0.5, "tilt and open valve must transfer water"):
		return
	var expected_height := lab.volume_a.size.y * lab.network.fill_ratio(&"A")
	var actual_height := (lab.visual_a.mesh as BoxMesh).size.y
	if not _require(absf(expected_height - actual_height) < 0.02, "water visual height must follow hydraulic data"):
		return
	var before_pump := lab.network.volume(&"A")
	lab.valve.openness = 0.0
	lab.pump.enabled = true
	await _wait_frames(120)
	if not _require(lab.network.volume(&"A") > before_pump + 0.5, "reverse pump must return water to reservoir A"):
		return
	lab.reset_lab()
	await physics_frame
	if not _require(is_equal_approx(lab.network.volume(&"A"), 8.0) and is_equal_approx(lab.network.volume(&"B"), 2.0), "Reset must restore exact volumes"):
		return
	if not _require(not lab.valve.is_open() and not lab.pump.enabled and is_zero_approx(lab.tilt), "Reset must restore controls"):
		return
	for ball_name in lab.balls:
		if not _require(lab.balls[ball_name] is PhysicsBall and not lab.balls[ball_name].freeze, "Water Lab balls must remain live PhysicsBall"):
			return

	print("WATER LAB PASS: scene, controls, data-driven visual, pump, reset and live PhysicsBall")
	quit(0)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("WATER LAB FAIL: " + message)
	quit(1)
	return false
