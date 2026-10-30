extends SceneTree
## Level 05 mobile asset check (headless): the exported GLB imports, keeps
## metric scale and Y-up, every mechanism is its own node with the right
## pivot, materials carry textures, vegetation and colliders are built.
## godot --headless --path . -s res://tests/level05_visuals_test.gd

const MECHANISMS := ["Lift_Cage", "Lift_Gate_West", "Lift_Gate_North", "Lift_Tower", "Wheel_Main", "Wheel_East", "Wheel_Stream",
	"Gear_PitWheel", "Gear_Wallower", "Gear_EastBevel", "Gear_WinchBevel", "Gear_PillarCrown", "Gear_CrankPinion",
	"Shaft_Line", "Shaft_Mast", "Shaft_Winch", "Axle_Main", "Axle_East", "Valve_Diverter", "Valve_PoolSluice",
	"Gate_StreamSluice", "Gate_MiddleShutter", "Crate_Cube", "Bridge_StreamWest", "Bridge_Spillway", "Bridge_LiftMiddle"]
const PLATFORMS := ["L_Start", "L_Front", "L_FrontEast", "L_HiddenCorridor", "L_SecretAlcove", "M_Workshop", "M_GearTerrace",
	"U_LiftWalk", "U_PoolDeck", "U_ValveDeck", "U_GoalDeck"]

var failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures.append(message)


func _run() -> void:
	var visuals := Level05Visuals.new()
	root.add_child(visuals)
	await process_frame
	var model := visuals.level_root
	_check(model != null, "GLB instanced")
	for node_name in MECHANISMS + PLATFORMS:
		_check(model.find_child(node_name, true, false) != null, "node present: " + node_name)
	# Scale and orientation: Godot +Y up, metres. Blender (x, y, z) -> (x, z, -y).
	var goal: Array = visuals.scene_data["markers"]["Marker_Goal"]
	_check(absf(goal[1] - 2.75) < 0.02, "goal marker at 2.75 m (Y up, 1 unit = 1 m): %s" % str(goal))
	var cage := model.find_child("Lift_Cage", true, false) as Node3D
	_check(cage != null and cage.global_position.distance_to(Vector3(9.8, 0.0, -1.0)) < 0.02, "lift cage pivot at shaft centre, floor 0: %s" % str(cage.global_position if cage else null))
	var wheel := model.find_child("Wheel_Main", true, false) as Node3D
	_check(wheel != null and wheel.global_position.distance_to(Vector3(9.3, 1.3, -6.125)) < 0.02, "main wheel pivot on its axle: %s" % str(wheel.global_position if wheel else null))
	var gear := model.find_child("Gear_PillarCrown", true, false) as Node3D
	_check(gear != null and gear.has_meta("extras"), "gear keeps its axis metadata (glTF extras)")
	var textured := 0
	var untextured: PackedStringArray = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i) as BaseMaterial3D
			if material == null:
				continue
			if material.resource_name in ["M_WoodBeam", "M_WoodBoard", "M_Stone", "M_Rock", "M_Meadow", "M_Roof", "M_Fir", "M_Brass"]:
				if material.albedo_texture != null and material.normal_texture != null:
					textured += 1
				else:
					untextured.append(material.resource_name)
	_check(untextured.is_empty(), "every PBR surface has albedo + normal textures (%d surfaces) %s" % [textured, str(untextured)])
	_check(visuals.report.get("conifers", 0) > 300, "conifer MultiMesh instances: %d" % visuals.report.get("conifers", 0))
	_check(visuals.report.get("colliders_static", 0) > 150, "static box colliders: %d" % visuals.report.get("colliders_static", 0))
	_check(visuals.report.get("colliders_dynamic", 0) >= 10, "mechanism colliders: %d" % visuals.report.get("colliders_dynamic", 0))
	print("REPORT ", JSON.stringify(visuals.report))
	print("RESULT ", "OK" if failures.is_empty() else "FAILED %d" % failures.size())
	quit(0 if failures.is_empty() else 1)
