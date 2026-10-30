extends Node3D
## Level 05 mobile preview: the Level05Visuals build seen from the Blender v4
## camera angles (level05_scene.json). Keys 1-7 switch cameras, Q cycles the
## quality tier. Capture mode renders every camera to PNG and prints render
## statistics, for the Blender v4 <-> Godot comparison:
##   godot --path . --rendering-method gl_compatibility res://scenes/levels/level05_preview.tscn -- --capture=<dir> [--quality=0|1|2]

const CAMERAS := ["Cam_01_Isometric", "Cam_02_Top", "Cam_03_Side", "Cam_04_Mill", "Cam_05_Corridor", "Cam_06_Wheel", "Cam_07_Lift"]

var visuals: Level05Visuals
var camera: Camera3D
var index := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	visuals = Level05Visuals.new()
	for arg in args:
		if arg.begins_with("--quality="):
			visuals.quality = int(arg.get_slice("=", 1))
	add_child(visuals)
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.far = 900.0
	add_child(camera)
	_use_camera(0)
	for arg in args:
		if arg.begins_with("--capture="):
			_capture(arg.get_slice("=", 1))


func _use_camera(i: int) -> void:
	index = posmod(i, CAMERAS.size())
	var data: Dictionary = visuals.scene_data.get("cameras", {}).get(CAMERAS[index], {})
	if data.is_empty():
		return
	camera.transform = visuals.xform(data["xform"])
	if data.get("ortho_size") != null:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = float(data["ortho_size"])
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = float(data["hfov_deg"])
	camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_7:
		_use_camera(key.keycode - KEY_1)


func _capture(out_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var lines: PackedStringArray = []
	for i in CAMERAS.size():
		_use_camera(i)
		for frame in 40:
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		image.save_png(out_dir.path_join("godot_%s.png" % CAMERAS[i]))
		lines.append("%s draw_calls=%d primitives=%d objects=%d" % [CAMERAS[i],
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	lines.append("video_mem_mb=%.1f texture_mem_mb=%.1f buffer_mem_mb=%.1f fps_desktop=%d" % [
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.TIME_FPS)])
	lines.append("report=" + JSON.stringify(visuals.report))
	var file := FileAccess.open(out_dir.path_join("godot_stats.txt"), FileAccess.WRITE)
	file.store_string("\n".join(lines))
	print("\n".join(lines))
	get_tree().quit()
