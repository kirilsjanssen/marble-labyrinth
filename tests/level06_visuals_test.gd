extends SceneTree
## Structural check for the committed v2 art and its Android-friendly runtime wrapper.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var board := StaticBody3D.new()
	world.add_child(board)
	var visuals := Level06Visuals.new()
	visuals.quality = Level06Visuals.Quality.LOW
	visuals.collider_parent = board
	visuals.world_parent = world
	board.add_child(visuals)
	await process_frame

	if not _require(visuals.level_root != null, "LOW v2 GLB must instantiate"):
		return
	if not _require(String(visuals.report.get("glb", "")).ends_with("level06_orbital_mechanism_v2_low.glb"), "Android profile must use the committed v2 LOW GLB"):
		return
	for node_name in ["P01_Deck", "L01_PLATFORM_PIVOT", "L02_PLATFORM_PIVOT", "M01_FLYWHEEL_PIVOT", "P02_FINISH_PIVOT"]:
		if not _require(visuals.node(node_name) != null, "GLB engineering node %s must exist" % node_name):
			return
	for demo_name in ["DEMO_ROUTE_BALL", "P01_DemoBall_Start"]:
		var demo := visuals.node(demo_name)
		if demo and not _require(not demo.visible, "Imported demo ball %s must be hidden" % demo_name):
			return
	var collision_count := board.get_children().filter(func(child: Node) -> bool: return child is CollisionShape3D).size()
	if not _require(collision_count >= 30 and collision_count == int(visuals.report["colliders"]), "Simplified route must have Android-safe colliders (%d)" % collision_count):
		return
	if not _require(world.get_node_or_null("Level06SpaceBackdrop/OrbitalStars") != null and world.get_node_or_null("Level06SpaceBackdrop/OrbitalPlanet") != null, "World-independent planet and stars must exist"):
		return
	print("LEVEL 6 VISUALS PASS: v2 LOW GLB, key engineering nodes, hidden demo balls, %d simplified colliders, independent planet/stars" % collision_count)
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("LEVEL 6 VISUALS FAIL: " + message)
	quit(1)
	return false
