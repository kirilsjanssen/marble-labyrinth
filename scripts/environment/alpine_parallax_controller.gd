class_name AlpineParallaxController
extends Node3D
## Layered Alpine surroundings. Far backdrops are cylinders that partly follow
## the camera (follow 1.0 = at infinity, lower = closer), so orbiting and the
## chase camera shift each layer by a different amount. Near layers are real 3D
## rocks, firs and waterfalls built once with MultiMesh. Everything stays
## outside the playable board.

const LayerShader = preload("res://shaders/parallax_layer.gdshader")
const FlowWaterSurfaceScript = preload("res://scripts/water/flow_water_surface.gd")

## Each far layer: radius, height, base y, camera follow factor, procedural
## ridge settings and the maximum distance it may drift from the board, which
## stops near ridges from sliding implausibly far when the camera swings.
const FAR_LAYERS := [
	{"name": "SnowPeaks", "radius": 70.0, "height": 34.0, "y": -2.0, "follow": 0.96, "max_shift": 30.0, "tint": Color("ffffff"), "haze": 0.05, "ridge": 0.62, "snow": 0.16, "seed": 1.0, "repeats": 2.0, "texture": "res://assets/luma/level04/alps_far.jpg"},
	{"name": "NearRidges", "radius": 52.0, "height": 22.0, "y": -2.0, "follow": 0.84, "max_shift": 18.0, "tint": Color("7f93a8"), "haze": 0.38, "ridge": 0.50, "snow": 0.05, "seed": 4.0, "repeats": 3.0},
	{"name": "ForestRidge", "radius": 40.0, "height": 15.0, "y": -1.6, "follow": 0.70, "max_shift": 14.0, "tint": Color("aebfb4"), "haze": 0.34, "ridge": 0.45, "snow": 0.0, "seed": 6.0, "repeats": 4.0, "texture": "res://assets/luma/level04/forest_ridge.png", "solid_below": 0.80},
	{"name": "ForestSlopes", "radius": 28.0, "height": 10.0, "y": -1.4, "follow": 0.50, "max_shift": 9.0, "tint": Color("ffffff"), "haze": 0.10, "ridge": 0.42, "snow": 0.0, "seed": 9.0, "repeats": 5.0, "texture": "res://assets/luma/level04/forest_ridge.png", "solid_below": 0.80},
]
const NEAR_RING_MIN := 7.4
const FIR_COUNT := 96
const ROCK_COUNT := 64
const SHRUB_COUNT := 140
const FOLLOW_SHARPNESS := 5.0

var camera: Camera3D
var anchor := Vector3.ZERO
var far_layers: Array[MeshInstance3D] = []
var layer_follow: Array[float] = []
var layer_max_shift: Array[float] = []
var water_surfaces: Array[FlowWaterSurface] = []
var rng := RandomNumberGenerator.new()


func setup(view_camera: Camera3D, board_anchor: Vector3, materials: Dictionary, seed_value := 4004) -> void:
	camera = view_camera
	anchor = board_anchor
	rng.seed = seed_value
	for spec: Dictionary in FAR_LAYERS:
		_build_far_layer(spec)
	_build_ground(materials)
	_build_cliffs(materials)
	_build_fir_forest()
	_build_rocks(materials)
	_build_shrubs()
	snap_to_camera()


func _process(delta: float) -> void:
	update_layers(delta)


## Moves every far layer towards its camera-relative target; delta <= 0 snaps.
func update_layers(delta: float) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var weight := 1.0 if delta <= 0.0 else 1.0 - exp(-FOLLOW_SHARPNESS * delta)
	for index in range(far_layers.size()):
		var layer := far_layers[index]
		var target := _layer_target(index)
		layer.global_position = layer.global_position.lerp(target, weight)


func snap_to_camera() -> void:
	update_layers(0.0)


## Horizontal offset of each far layer from the board anchor (for tests/debug).
func layer_offsets() -> Array[Vector3]:
	var offsets: Array[Vector3] = []
	for layer in far_layers:
		var offset := layer.global_position - anchor
		offsets.append(Vector3(offset.x, 0.0, offset.z))
	return offsets


func _layer_target(index: int) -> Vector3:
	var to_camera := camera.global_position - anchor
	to_camera.y = 0.0
	var shift := (to_camera * layer_follow[index]).limit_length(layer_max_shift[index])
	var spec: Dictionary = FAR_LAYERS[index]
	return Vector3(anchor.x + shift.x, float(spec["y"]) + float(spec["height"]) * 0.5, anchor.z + shift.z)


func _build_far_layer(spec: Dictionary) -> void:
	var layer := MeshInstance3D.new()
	layer.name = spec["name"]
	var mesh := CylinderMesh.new()
	mesh.top_radius = spec["radius"]
	mesh.bottom_radius = spec["radius"]
	mesh.height = spec["height"]
	mesh.radial_segments = 48
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	layer.mesh = mesh
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = LayerShader
	material.set_shader_parameter("tint", spec["tint"])
	material.set_shader_parameter("haze_color", Color("b9cde0"))
	material.set_shader_parameter("haze", spec["haze"])
	material.set_shader_parameter("ridge_height", spec["ridge"])
	material.set_shader_parameter("snow_line", spec["snow"])
	material.set_shader_parameter("ridge_seed", spec["seed"])
	material.set_shader_parameter("repeats", spec["repeats"])
	if spec.has("texture") and ResourceLoader.exists(spec["texture"]):
		material.set_shader_parameter("layer_texture", load(spec["texture"]))
		material.set_shader_parameter("use_texture", true)
		material.set_shader_parameter("solid_below", spec.get("solid_below", 2.0))
	# Farther layers draw first so nearer silhouettes overlap them.
	material.render_priority = -10 + far_layers.size()
	layer.material_override = material
	add_child(layer)
	far_layers.append(layer)
	layer_follow.append(float(spec["follow"]))
	layer_max_shift.append(float(spec["max_shift"]))


func _build_ground(materials: Dictionary) -> void:
	var meadow := MeshInstance3D.new()
	meadow.name = "AlpineMeadow"
	var disc := CylinderMesh.new()
	disc.top_radius = 34.0
	disc.bottom_radius = 34.0
	disc.height = 0.2
	disc.radial_segments = 40
	meadow.mesh = disc
	meadow.position = anchor + Vector3(0.0, -1.35, 0.0)
	meadow.material_override = materials["meadow"]
	add_child(meadow)

	# A mountain river sweeps past the mill below the board.
	var river: FlowWaterSurface = FlowWaterSurfaceScript.create("MountainRiver", Vector2(5.0, 40.0), Vector2(0.0, 1.0))
	river.position = anchor + Vector3(9.5, -1.22, 0.0)
	river.rotation.y = 0.35
	river.water_material.set_shader_parameter("uv_scale", 6.0)
	river.water_material.set_shader_parameter("wave_height", 0.02)
	add_child(river)
	river.set_flux(0.7)
	water_surfaces.append(river)


func _build_cliffs(materials: Dictionary) -> void:
	# Granite cliffs north of the mill with a falling stream down their face.
	var cliff_specs := [
		[Vector3(-6.0, 1.6, -9.5), Vector3(7.0, 6.0, 3.0), 0.25],
		[Vector3(1.0, 2.6, -10.5), Vector3(6.5, 8.0, 3.2), -0.08],
		[Vector3(8.0, 1.2, -9.0), Vector3(6.0, 5.2, 3.0), -0.32],
		[Vector3(-10.5, 0.8, -3.0), Vector3(3.0, 4.4, 7.0), 0.15],
	]
	for spec in cliff_specs:
		# Low-poly boulder shells read as weathered granite, not crates.
		var cliff := MeshInstance3D.new()
		cliff.name = "GraniteCliff"
		var shell := SphereMesh.new()
		shell.radius = 0.5
		shell.height = 1.0
		shell.radial_segments = 9
		shell.rings = 5
		cliff.mesh = shell
		cliff.position = anchor + spec[0]
		cliff.rotation.y = spec[2]
		cliff.scale = spec[1] * Vector3(1.15, 1.25, 1.15)
		cliff.material_override = materials["granite"]
		add_child(cliff)
	_build_waterfall(anchor + Vector3(0.6, 2.6, -8.85), Vector2(1.4, 7.8))
	_build_waterfall(anchor + Vector3(-9.0, 0.8, -1.6), Vector2(0.9, 4.2), PI * 0.5)


func _build_waterfall(at: Vector3, size: Vector2, yaw := 0.0) -> void:
	var fall: FlowWaterSurface = FlowWaterSurfaceScript.create("CliffWaterfall", size, Vector2(0.0, 1.0), true)
	fall.position = at
	fall.rotation.y = yaw
	fall.water_material.set_shader_parameter("shallow_color", Color(0.80, 0.92, 1.0, 0.85))
	add_child(fall)
	fall.set_flux(2.2)
	water_surfaces.append(fall)
	# Spray cloud where the fall meets the ground.
	var spray := MeshInstance3D.new()
	spray.name = "WaterfallSpray"
	var sphere := SphereMesh.new()
	sphere.radius = size.x * 0.75
	sphere.height = size.x * 0.9
	spray.mesh = sphere
	spray.position = at + Vector3(0.0, -size.y * 0.5, 0.0)
	var spray_material := StandardMaterial3D.new()
	spray_material.albedo_color = Color(0.92, 0.97, 1.0, 0.45)
	spray_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spray_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spray.material_override = spray_material
	add_child(spray)


func _build_fir_forest() -> void:
	var fir := CylinderMesh.new()
	fir.top_radius = 0.0
	fir.bottom_radius = 0.55
	fir.height = 1.8
	fir.radial_segments = 7
	fir.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("23402b")
	material.roughness = 0.9
	fir.material = material
	var transforms: Array[Transform3D] = []
	for _index in range(FIR_COUNT):
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(NEAR_RING_MIN + 1.2, 18.0)
		# Keep the camera-facing south side lower and sparser.
		if cos(angle) > 0.4 and radius < 10.0:
			radius += 3.0
		var size := rng.randf_range(0.8, 1.9) * (1.0 + radius / 30.0)
		var at := anchor + Vector3(sin(angle) * radius, -1.25 + fir.height * 0.5 * size, cos(angle) * radius)
		transforms.append(Transform3D(Basis.from_scale(Vector3(size, size * rng.randf_range(0.9, 1.3), size)), at))
	_add_multimesh("FirForest", fir, transforms)


func _build_rocks(materials: Dictionary) -> void:
	var rock := SphereMesh.new()
	rock.radius = 0.5
	rock.height = 0.7
	rock.radial_segments = 7
	rock.rings = 4
	rock.material = materials["granite"]
	var transforms: Array[Transform3D] = []
	for _index in range(ROCK_COUNT):
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(NEAR_RING_MIN, 14.0)
		var stretch := Vector3(rng.randf_range(0.6, 1.8), rng.randf_range(0.4, 1.1), rng.randf_range(0.6, 1.6))
		var rock_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(stretch)
		transforms.append(Transform3D(rock_basis, anchor + Vector3(sin(angle) * radius, -1.2, cos(angle) * radius)))
	_add_multimesh("BoulderField", rock, transforms)


func _build_shrubs() -> void:
	# Nearest layer: moss tufts and dwarf pines hugging the base of the board.
	var shrub := SphereMesh.new()
	shrub.radius = 0.22
	shrub.height = 0.28
	shrub.radial_segments = 6
	shrub.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("34552a")
	material.roughness = 0.95
	shrub.material = material
	var transforms: Array[Transform3D] = []
	for _index in range(SHRUB_COUNT):
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(6.9, 9.5)
		var size := rng.randf_range(0.7, 1.8)
		transforms.append(Transform3D(Basis.from_scale(Vector3.ONE * size), anchor + Vector3(sin(angle) * radius, -1.22, cos(angle) * radius)))
	_add_multimesh("MossAndShrubs", shrub, transforms)


func _add_multimesh(node_name: String, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
