class_name Level06Visuals
extends Node3D
## Runtime wrapper for the committed Orbital Mechanism v2 GLBs. The station is
## mounted on the tilting board. Stars and the planet are attached to the world
## so they never tilt with gameplay geometry.

enum Quality { LOW, HIGH }

const HIGH_GLB := "res://assets/levels/level06/level06_orbital_mechanism_v2_high.glb"
const LOW_GLB := "res://assets/levels/level06/level06_orbital_mechanism_v2_low.glb"

@export var quality := Quality.LOW
@export var build_colliders := true

var collider_parent: CollisionObject3D
var world_parent: Node3D
var level_root: Node3D
var world_nodes: Array[Node] = []
var spin_nodes: Array[Dictionary] = []
var barrier_nodes: Dictionary = {}
var lift_nodes: Dictionary = {}
var report := {}
var visual_time := 0.0


func _ready() -> void:
	tree_exiting.connect(_free_world_nodes)
	build()


func build() -> void:
	var glb_path := HIGH_GLB if quality == Quality.HIGH else LOW_GLB
	var packed := load(glb_path) as PackedScene
	if packed == null:
		push_error("Level06: cannot load %s" % glb_path)
		return
	level_root = packed.instantiate() as Node3D
	level_root.name = "Level06Model"
	add_child(level_root)
	_stop_imported_animation_players()
	_hide_demo_balls()
	_cache_moving_nodes()
	var collider_count_before := collider_parent.get_child_count() if collider_parent else 0
	if build_colliders and collider_parent:
		_build_static_colliders()
	_build_space_backdrop()
	report = {
		"glb": glb_path,
		"colliders": collider_parent.get_child_count() - collider_count_before if collider_parent else 0,
		"quality": "HIGH" if quality == Quality.HIGH else "LOW",
		"world_independent": true,
	}


func _process(delta: float) -> void:
	visual_time += delta
	for entry: Dictionary in spin_nodes:
		var moving_node := entry["node"] as Node3D
		if moving_node and is_instance_valid(moving_node):
			moving_node.rotate_z(float(entry["speed"]) * delta)
	var pulse := 0.08 + 0.92 * (0.5 + 0.5 * sin(visual_time * 2.8))
	for barrier_name: String in barrier_nodes:
		var barrier := barrier_nodes[barrier_name] as Node3D
		if barrier:
			barrier.scale.y = pulse


func node(node_name: String) -> Node3D:
	return level_root.find_child(node_name, true, false) as Node3D if level_root else null


func set_lift_surface(lift_name: String, surface_y: float) -> void:
	var pivot := lift_nodes.get(lift_name) as Node3D
	if pivot:
		# Imported platform cylinder: 0.24 m high, centred on its pivot.
		pivot.position.y = surface_y - 0.12


func set_barrier_open(barrier_name: String, is_open: bool) -> void:
	var pivot := barrier_nodes.get(barrier_name) as Node3D
	if pivot:
		pivot.scale.y = 0.04 if is_open else 1.0


func configure_environment(environment: Environment, sun: DirectionalLight3D) -> void:
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("01030a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("344c72")
	environment.ambient_light_energy = 0.48 if quality == Quality.HIGH else 0.34
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.fog_enabled = false
	environment.glow_enabled = quality == Quality.HIGH
	if sun:
		sun.rotation_degrees = Vector3(-38.0, -28.0, -18.0)
		sun.light_color = Color("c9dcff")
		sun.light_energy = 2.35
		sun.shadow_enabled = quality == Quality.HIGH
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 90.0


func _stop_imported_animation_players() -> void:
	for animation_node: Node in level_root.find_children("*", "AnimationPlayer", true, false):
		var player := animation_node as AnimationPlayer
		player.stop()
		player.active = false


func _hide_demo_balls() -> void:
	for demo_name in ["DEMO_ROUTE_BALL", "P01_DemoBall_Start"]:
		var demo := node(demo_name)
		if demo:
			demo.visible = false


func _cache_moving_nodes() -> void:
	lift_nodes = {
		"L01": node("L01_PLATFORM_PIVOT"),
		"L02": node("L02_PLATFORM_PIVOT"),
	}
	barrier_nodes = {
		"G01": node("G01_BARRIER_PIVOT"),
		"G02": node("G02_BARRIER_PIVOT"),
	}
	for spec in [
		["M01_FLYWHEEL_PIVOT", 0.72],
		["M01_ROTOR_CORE_PIVOT", -1.45],
		["M01_GearA_PIVOT", 1.15],
		["M01_GearB_PIVOT", -1.72],
		["M01_GearC_PIVOT", 2.10],
		["M01_GearD_PIVOT", -2.75],
		["P02_FINISH_PIVOT", 0.65],
		["P02_ActivationRing_0", 0.82],
		["P02_ActivationRing_1", -0.62],
		["P02_ActivationRing_2", 0.48],
	]:
		var moving_node := node(spec[0])
		if moving_node:
			spin_nodes.append({"node": moving_node, "speed": spec[1]})


func _build_static_colliders() -> void:
	_add_cylinder_collider("P01_Collision", P(-17.0, -14.0, 3.75), 3.35, 0.50)
	_add_segment("B01", P(-17.0, -14.0, 4.0), P(-12.0, -14.0, 4.0), 2.60, true)
	_add_segment("B02", P(-12.0, -14.0, 4.0), P(-12.0, -8.0, 4.0), 2.60, true)
	_add_segment("B03", P(-12.0, -8.0, 4.0), P(-16.0, -8.0, 4.0), 2.60, true)
	var tube_1 := [
		P(-16.0, -8.0, 9.0), P(-16.0, -1.0, 9.0), P(-15.3, 3.3, 9.0),
		P(-11.0, 4.0, 9.0), P(4.0, 4.0, 9.0),
	]
	_add_polyline("T01", tube_1, 1.28)
	_add_segment("B04", P(4.0, 4.0, 9.0), P(13.0, 4.0, 9.0), 2.60, true)
	_add_polyline("T02", [P(13.0, 4.0, 12.0), P(13.0, 12.0, 12.0)], 1.28)
	_add_segment("B05", P(13.0, 12.0, 12.0), P(17.0, 12.0, 12.0), 2.60, true)
	_add_cylinder_collider("P02_Collision", P(17.0, 12.0, 11.75), 3.25, 0.50)


func _add_polyline(prefix: String, points: Array, width: float) -> void:
	for index in range(points.size() - 1):
		_add_segment("%s_%02d" % [prefix, index], points[index], points[index + 1], width, true)


func _add_segment(segment_name: String, start: Vector3, finish: Vector3, width: float, add_rails: bool) -> void:
	var flat := finish - start
	flat.y = 0.0
	var length := flat.length()
	if length <= 0.01:
		return
	var direction := flat / length
	var side := Vector3(-direction.z, 0.0, direction.x)
	var centre := (start + finish) * 0.5
	var yaw := atan2(-direction.z, direction.x)
	_add_box_collider(segment_name + "_Floor", centre + Vector3.DOWN * 0.25, Vector3(length + 0.10, 0.50, width), yaw)
	if add_rails:
		for side_sign in [-1.0, 1.0]:
			var rail_position: Vector3 = centre + side * float(side_sign) * (width * 0.5 - 0.04) + Vector3.UP * 0.34
			_add_box_collider(segment_name + "_Rail_%s" % side_sign, rail_position, Vector3(length, 0.68, 0.12), yaw)


func _add_box_collider(collider_name: String, at: Vector3, size: Vector3, yaw: float) -> void:
	var collision := CollisionShape3D.new()
	collision.name = collider_name
	collision.position = at
	collision.rotation.y = yaw
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collider_parent.add_child(collision)


func _add_cylinder_collider(collider_name: String, at: Vector3, radius: float, height: float) -> void:
	var collision := CollisionShape3D.new()
	collision.name = collider_name
	collision.position = at
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	collider_parent.add_child(collision)


func _build_space_backdrop() -> void:
	if world_parent == null:
		return
	var backdrop := Node3D.new()
	backdrop.name = "Level06SpaceBackdrop"
	world_parent.add_child(backdrop)
	world_nodes.append(backdrop)
	_build_stars(backdrop)
	_build_planet(backdrop)
	var rim := DirectionalLight3D.new()
	rim.name = "OrbitalBlueRim"
	rim.rotation_degrees = Vector3(24.0, 146.0, 12.0)
	rim.light_color = Color("4f83ff")
	rim.light_energy = 0.70 if quality == Quality.HIGH else 0.42
	rim.shadow_enabled = false
	backdrop.add_child(rim)


func _build_stars(parent: Node3D) -> void:
	var star_mesh := SphereMesh.new()
	star_mesh.radius = 0.075
	star_mesh.height = 0.15
	star_mesh.radial_segments = 5
	star_mesh.rings = 3
	var star_material := StandardMaterial3D.new()
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_material.albedo_color = Color("d9e8ff")
	star_material.emission_enabled = true
	star_material.emission = Color("8bb8ff")
	star_material.emission_energy_multiplier = 2.0
	star_mesh.material = star_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = star_mesh
	multimesh.instance_count = 150 if quality == Quality.HIGH else 80
	var rng := RandomNumberGenerator.new()
	rng.seed = 6006
	for index in range(multimesh.instance_count):
		var y := rng.randf_range(-0.85, 0.85)
		var angle := rng.randf_range(0.0, TAU)
		var ring := sqrt(1.0 - y * y)
		var direction := Vector3(cos(angle) * ring, y, sin(angle) * ring)
		var scale := rng.randf_range(0.55, 1.65)
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale), direction * rng.randf_range(70.0, 92.0)))
	var stars := MultiMeshInstance3D.new()
	stars.name = "OrbitalStars"
	stars.multimesh = multimesh
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(stars)


func _build_planet(parent: Node3D) -> void:
	var planet := MeshInstance3D.new()
	planet.name = "OrbitalPlanet"
	planet.position = Vector3(38.0, -20.0, -48.0)
	var sphere := SphereMesh.new()
	sphere.radius = 20.0
	sphere.height = 40.0
	sphere.radial_segments = 64 if quality == Quality.HIGH else 32
	sphere.rings = 32 if quality == Quality.HIGH else 16
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded;
void fragment() {
	float bands = sin(UV.y * 54.0 + sin(UV.x * 31.0) * 2.2);
	float continents = sin(UV.x * 41.0 + sin(UV.y * 19.0) * 2.8) * sin(UV.y * 27.0);
	float cloud = smoothstep(0.35, 0.90, bands * 0.55 + continents * 0.45);
	vec3 ocean = vec3(0.015, 0.10, 0.28);
	vec3 land = vec3(0.08, 0.24, 0.32);
	vec3 base = mix(ocean, land, smoothstep(-0.2, 0.4, continents));
	ALBEDO = mix(base, vec3(0.62, 0.76, 0.88), cloud * 0.62);
}
"""
	material.shader = shader
	sphere.material = material
	planet.mesh = sphere
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(planet)
	var atmosphere := MeshInstance3D.new()
	atmosphere.name = "OrbitalAtmosphere"
	atmosphere.position = planet.position
	var atmosphere_mesh := SphereMesh.new()
	atmosphere_mesh.radius = 20.8
	atmosphere_mesh.height = 41.6
	atmosphere_mesh.radial_segments = sphere.radial_segments
	atmosphere_mesh.rings = sphere.rings
	var atmosphere_material := ShaderMaterial.new()
	var atmosphere_shader := Shader.new()
	atmosphere_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);
	ALBEDO = vec3(0.10, 0.42, 1.0);
	ALPHA = rim * 0.72;
}
"""
	atmosphere_material.shader = atmosphere_shader
	atmosphere_mesh.material = atmosphere_material
	atmosphere.mesh = atmosphere_mesh
	atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(atmosphere)


func _free_world_nodes() -> void:
	for world_node: Node in world_nodes:
		if is_instance_valid(world_node):
			world_node.queue_free()
	world_nodes.clear()


static func P(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)
