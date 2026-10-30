class_name Level05Visuals
extends Node3D
## Level 05 Alpine Watermill, mobile visual build for GL Compatibility.
## Instances the exported GLB (tools/blender/export_level05_mobile.py) and adds
## what glTF cannot carry: flow-driven water shaders, MultiMesh conifers, box
## colliders, the rendered panorama sky with parallax rings, cheap lantern glow
## and quality tiers. Mechanisms stay separate GLB nodes with their own pivots;
## Level05Mechanisms drives them in the game.
##
## Standalone (preview) it builds its own sky, sun and colliders. In the game,
## main.gd mounts it on the tilting board: `collider_parent` receives the box
## shapes (so physics AND the smart camera's occlusion rays see them),
## `world_parent` receives the far parallax rings (they must not tilt with the
## board) and `build_environment` is off (main owns the WorldEnvironment).

enum Quality { LOW, MEDIUM, HIGH }

const BASE := "res://assets/levels/level05/"
const WaterShader = preload("res://shaders/level05_water.gdshader")
const FallShader = preload("res://shaders/level05_waterfall.gdshader")
const ParallaxShader = preload("res://shaders/parallax_layer.gdshader")
## Board centre in Godot space (Blender 6, 6).
const CENTRE := Vector3(6.0, 0.0, -6.0)
const PRESETS := {
	# GL Compatibility draws every omni light as an extra pass over the meshes it
	# touches, so real lamp lights stay few; the halos carry the look.
	Quality.LOW: {"veg": 0.35, "shadows": false, "shadow_splits": 0, "lamp_lights": 0, "spray": 0, "sky": "sky_panorama_low.jpg", "glow": false, "water_detail": 0.0},
	Quality.MEDIUM: {"veg": 0.65, "shadows": true, "shadow_splits": 1, "lamp_lights": 0, "spray": 14, "sky": "sky_panorama_low.jpg", "glow": false, "water_detail": 1.0},
	Quality.HIGH: {"veg": 1.0, "shadows": true, "shadow_splits": 2, "lamp_lights": 3, "spray": 28, "sky": "sky_panorama.jpg", "glow": true, "water_detail": 1.0},
}
## Mechanism nodes whose simple local colliders this class adds by itself. The
## lift, crates and wheels get their physics from Level05Mechanisms instead.
const SELF_COLLIDED := ["Valve_", "Gate_", "Lever_Sluice_Base", "Lever_Secret_Base"]

@export var quality := Quality.HIGH
@export var build_colliders := true
@export var build_environment := true

var collider_parent: CollisionObject3D
var world_parent: Node3D
var level_root: Node3D
var scene_data := {}
var water_params := {}
var report := {}
## name -> {"node", "materials", "kind", "flow", "phase_a", "phase_b", "speed_a", "speed_b", "spray"}
var water_bodies := {}
## Nodes hung on world_parent (they do not tilt); freed together with this level.
var world_nodes: Array[Node] = []


func _ready() -> void:
	tree_exiting.connect(func() -> void:
		for world_node in world_nodes:
			if is_instance_valid(world_node):
				world_node.queue_free()
	)
	build()


func build() -> void:
	var preset: Dictionary = PRESETS[quality]
	scene_data = _json(BASE + "level05_scene.json")
	water_params = _json("res://assets/luma/level05/level05_water_params.json")
	var packed := load(BASE + "level05_mobile.glb") as PackedScene
	level_root = packed.instantiate() as Node3D
	level_root.name = "Level05Model"
	add_child(level_root)
	_apply_materials(level_root, preset)
	_build_vegetation(preset)
	if build_colliders:
		_build_colliders()
	if build_environment:
		var environment := Environment.new()
		var sun := DirectionalLight3D.new()
		sun.name = "AlpineSun"
		configure_environment(environment, sun)
		var world := WorldEnvironment.new()
		world.environment = environment
		add_child(world)
		add_child(sun)
	_build_parallax(preset)
	_build_lamps(preset)
	_build_spray(preset)


func _process(delta: float) -> void:
	# Each water body scrolls by its own live flux (set_flow), never by a clock.
	for body_name in water_bodies:
		var body: Dictionary = water_bodies[body_name]
		var flow: float = body["flow"]
		body["phase_a"] = fmod(float(body["phase_a"]) + float(body["speed_a"]) * flow * delta, 1000.0)
		body["phase_b"] = fmod(float(body["phase_b"]) + float(body["speed_b"]) * flow * delta, 1000.0)
		for material: ShaderMaterial in body["materials"]:
			material.set_shader_parameter("phase_a", body["phase_a"])
			material.set_shader_parameter("phase_b", body["phase_b"])


## Live hydraulic coupling: 0 = dry, 1 = nominal design flow. Falls fade in
## and out with their flow; channels slow down and lose their foam.
func set_flow(body_name: String, flow: float) -> void:
	if not water_bodies.has(body_name):
		return
	var body: Dictionary = water_bodies[body_name]
	body["flow"] = maxf(flow, 0.0)
	var node := body["node"] as Node3D
	if body["kind"] == "fall":
		var opacity := clampf(flow * 1.6, 0.0, 1.0)
		node.visible = opacity > 0.02
		for material: ShaderMaterial in body["materials"]:
			material.set_shader_parameter("opacity", opacity * (0.75 if material.get_shader_parameter("mode") == 2 else 1.0))
		var spray := body.get("spray") as CPUParticles3D
		if spray:
			spray.emitting = flow > 0.08
	else:
		for material: ShaderMaterial in body["materials"]:
			material.set_shader_parameter("flow", clampf(flow, 0.0, 1.5))


func flow_of(body_name: String) -> float:
	return float(water_bodies[body_name]["flow"]) if water_bodies.has(body_name) else 0.0


func phase_of(body_name: String) -> float:
	return float(water_bodies[body_name]["phase_a"]) if water_bodies.has(body_name) else 0.0


func node(node_name: String) -> Node3D:
	return level_root.find_child(node_name, true, false) as Node3D


func _json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _layer(layer_name: String) -> Dictionary:
	return water_params.get("layers", {}).get(layer_name, {})


# Materials ------------------------------------------------------------------

func _apply_materials(root: Node, preset: Dictionary) -> void:
	var channel := _layer("channel")
	var still := _layer("still")
	var fall_layers := {0: _layer("fall_body"), 1: _layer("fall_foam")}
	var count := 0
	for node_ref in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node_ref as MeshInstance3D
		if mesh_instance.name.begins_with("Terrain"):
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		var body_name := String(mesh_instance.name)
		var water_kind := "fall" if body_name.begins_with("Waterfall_") else ("surface" if body_name.begins_with("Water_") else "")
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i)
			if material == null:
				continue
			var shader_material: ShaderMaterial = null
			match material.resource_name:
				"M_Water":
					shader_material = _water_material(channel, preset)
				"M_FallBody":
					shader_material = _fall_material(0, "textures/waterfall_streaks.png", fall_layers[0])
				"M_FallFoam":
					shader_material = _fall_material(1, "textures/waterfall_foam_mask.png", fall_layers[1])
				"M_Spray":
					shader_material = _fall_material(2, "", {})
					shader_material.set_shader_parameter("opacity", 0.75)
				"M_Glow":
					var glow := StandardMaterial3D.new()
					glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					glow.albedo_color = Color(1.0, 0.55, 0.18)
					mesh_instance.set_surface_override_material(i, glow)
				_:
					var standard := material as BaseMaterial3D
					if standard:
						# Role tint, per-piece jitter and baked AO live in COLOR_0.
						standard.vertex_color_use_as_albedo = true
						standard.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			if shader_material:
				mesh_instance.set_surface_override_material(i, shader_material)
				mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if water_kind != "":
					_register_water(body_name, mesh_instance, water_kind, shader_material, channel, still, fall_layers)
			count += 1
	report["surfaces"] = count
	report["water_bodies"] = water_bodies.size()


func _register_water(body_name: String, mesh_instance: MeshInstance3D, kind: String, material: ShaderMaterial, channel: Dictionary, still: Dictionary, fall_layers: Dictionary) -> void:
	if not water_bodies.has(body_name):
		var speed_a := 0.0
		var speed_b := 0.0
		if kind == "fall":
			var body_layer: Dictionary = fall_layers[0]
			speed_a = float(body_layer.get("speed_a", 1.7)) / float(body_layer.get("tile_v", 1.2))
			speed_b = float(body_layer.get("speed_b", 2.4)) / (float(body_layer.get("tile_v", 1.2)) * 1.5)
		else:
			# Pools carry COLOR.r = 0.1 in the mesh, so one channel speed fits all.
			speed_a = float(channel.get("speed_a", 0.45)) / float(channel.get("tile_a", 1.6))
			speed_b = float(channel.get("speed_b", 0.75)) / float(channel.get("tile_b", 0.9))
		water_bodies[body_name] = {"node": mesh_instance, "materials": [], "kind": kind, "flow": 1.0, "phase_a": 0.0, "phase_b": 0.0, "speed_a": speed_a, "speed_b": speed_b, "spray": null}
	(water_bodies[body_name]["materials"] as Array).append(material)


func _water_material(channel: Dictionary, preset: Dictionary) -> ShaderMaterial:
	var water := ShaderMaterial.new()
	water.shader = WaterShader
	water.set_shader_parameter("foam_texture", load(BASE + "textures/water_foam.jpg"))
	water.set_shader_parameter("normal_texture", load(BASE + "textures/water_normal.png"))
	water.set_shader_parameter("tile_a", channel.get("tile_a", 1.6))
	water.set_shader_parameter("tile_b", channel.get("tile_b", 0.9))
	water.set_shader_parameter("detail", preset["water_detail"])
	return water


func _fall_material(mode: int, texture: String, layer: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FallShader
	material.set_shader_parameter("mode", mode)
	if texture != "":
		material.set_shader_parameter("layer_texture", load(BASE + texture))
	for key in ["tile_u", "tile_v", "speed_a", "speed_b"]:
		if layer.has(key):
			material.set_shader_parameter(key, layer[key])
	material.render_priority = mode
	return material


# Vegetation -------------------------------------------------------------------

func _build_vegetation(preset: Dictionary) -> void:
	var data := _json(BASE + "level05_vegetation.json")
	var density: float = preset["veg"]
	var total := 0
	for proto_name in data.get("prototypes", {}):
		var proto := level_root.find_child(proto_name, true, false) as MeshInstance3D
		if proto == null:
			push_warning("Level05: missing prototype %s" % proto_name)
			continue
		proto.visible = false
		var xforms: Array = data["prototypes"][proto_name]
		var keep: Array = []
		for i in xforms.size():
			# Deterministic thinning keeps the same trees on every run.
			if fposmod(float(i) * 0.6180339, 1.0) < density:
				keep.append(xforms[i])
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = proto.mesh
		multimesh.instance_count = keep.size()
		for i in keep.size():
			multimesh.set_instance_transform(i, xform(keep[i]))
		var instance := MultiMeshInstance3D.new()
		instance.name = "MM_" + proto_name
		instance.multimesh = multimesh
		# Hundreds of trees in the shadow pass cost more than they add.
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		total += keep.size()
	report["conifers"] = total


# Colliders --------------------------------------------------------------------

func _build_colliders() -> void:
	var data := _json(BASE + "level05_colliders.json")
	var body := collider_parent
	var offset := Transform3D.IDENTITY
	if body == null:
		body = StaticBody3D.new()
		body.name = "Level05Colliders"
		add_child(body)
	else:
		# Shapes live directly on the board: same transform as this node.
		offset = transform
	for entry in data.get("static", []):
		var shape := _box_shape(entry, String(entry.get("tag", "")))
		shape.transform = offset * shape.transform
		body.add_child(shape)
	var dynamic := 0
	for entry in data.get("dynamic", []):
		var node_name: String = entry["node"]
		if not SELF_COLLIDED.any(func(prefix: String) -> bool: return node_name.begins_with(prefix)):
			continue
		var mechanism := level_root.find_child(node_name, true, false) as Node3D
		if mechanism == null:
			push_warning("Level05: collider node %s missing" % node_name)
			continue
		# Mechanism colliders ride on their node, so they move with its pivot.
		var mover := AnimatableBody3D.new()
		mover.name = "Collider"
		mover.sync_to_physics = false
		mover.add_child(_box_shape(entry, "box"))
		mechanism.add_child(mover)
		dynamic += 1
	report["colliders_static"] = data.get("static", []).size()
	report["colliders_dynamic"] = dynamic


func _box_shape(entry: Dictionary, label: String) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	var s: Array = entry["size"]
	shape.size = Vector3(maxf(s[0], 0.01), maxf(s[1], 0.01), maxf(s[2], 0.01))
	var collision := CollisionShape3D.new()
	collision.name = label.replace(":", "_")
	collision.shape = shape
	var c: Array = entry["center"]
	collision.transform = Transform3D(Basis(Vector3.UP, float(entry.get("yaw", 0.0))), Vector3(c[0], c[1], c[2]))
	return collision


# Environment, sky, parallax -----------------------------------------------------

## Fills a WorldEnvironment + sun with the Level 05 look (panorama sky rendered
## from Blender v4, fog, sun direction and colour of the v4 scene).
func configure_environment(environment: Environment, sun: DirectionalLight3D) -> void:
	var preset: Dictionary = PRESETS[quality]
	if scene_data.is_empty():
		scene_data = _json(BASE + "level05_scene.json")
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = load(BASE + "parallax/" + str(preset["sky"]))
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.62, 0.72, 0.86)
	environment.fog_density = 0.0016
	environment.fog_sky_affect = 0.0
	environment.glow_enabled = preset["glow"]
	environment.glow_intensity = 0.5
	environment.glow_hdr_threshold = 1.1
	var sun_data: Dictionary = scene_data.get("sun", {})
	if sun_data.has("xform"):
		sun.basis = xform(sun_data["xform"]).basis
	var color: Array = sun_data.get("color", [1.0, 0.8, 0.55])
	sun.light_color = Color(color[0], color[1], color[2])
	sun.light_energy = 1.55
	sun.shadow_enabled = preset["shadows"]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if int(preset["shadow_splits"]) <= 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 32.0


func _build_parallax(_preset: Dictionary) -> void:
	# Far snowy Alps and sky are the panorama itself (correct for any camera
	# yaw, including CHASE). The rings in level05_parallax.json add depth
	# between it and the summit; they hang in the world, not on the board.
	var data := _json(BASE + "level05_parallax.json")
	var rings := 0
	for layer in data.get("rings", []):
		if int(layer.get("min_quality", 0)) > int(quality):
			continue
		_ring(layer["name"], layer["texture"], layer["radius"], layer["bottom"], layer["top"], layer["repeats"], layer["haze"])
		rings += 1
	report["parallax_rings"] = rings


func _ring(ring_name: String, texture: String, radius: float, bottom: float, top: float, repeats: float, haze: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = top - bottom
	mesh.cap_top = false
	mesh.cap_bottom = false
	mesh.radial_segments = 48
	mesh.rings = 1
	var material := ShaderMaterial.new()
	material.shader = ParallaxShader
	material.set_shader_parameter("layer_texture", load(BASE + texture))
	material.set_shader_parameter("use_texture", true)
	material.set_shader_parameter("repeats", repeats)
	material.set_shader_parameter("haze", haze)
	material.set_shader_parameter("haze_color", Color(0.62, 0.72, 0.86))
	var ring := MeshInstance3D.new()
	ring.name = ring_name
	ring.mesh = mesh
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var local := CENTRE + Vector3(0.0, (top + bottom) * 0.5, 0.0)
	if world_parent:
		ring.position = world_parent.to_local(to_global(local))
		world_parent.add_child(ring)
		world_nodes.append(ring)
	else:
		ring.position = local
		add_child(ring)


# Lamps and spray ----------------------------------------------------------------

func _build_lamps(preset: Dictionary) -> void:
	var sprite_texture := load(BASE + "textures/soft_sprite.png") as Texture2D
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.albedo_texture = sprite_texture
	glow.albedo_color = Color(1.0, 0.55, 0.2, 0.55)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	quad.material = glow
	var lamps: Array = scene_data.get("lamps", [])
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = lamps.size()
	for i in lamps.size():
		var p: Array = lamps[i]["pos"]
		multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(p[0], p[1], p[2])))
	var halos := MultiMeshInstance3D.new()
	halos.name = "LampHalos"
	halos.multimesh = multimesh
	halos.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halos)
	# A few real lights only: the corridor and the millhouse door first.
	var ranked := lamps.duplicate()
	ranked.sort_custom(func(a, b): return _lamp_rank(a) < _lamp_rank(b))
	var lights := 0
	for lamp in ranked.slice(0, int(preset["lamp_lights"])):
		var p: Array = lamp["pos"]
		var omni := OmniLight3D.new()
		omni.light_color = Color(1.0, 0.58, 0.25)
		omni.light_energy = 1.4
		omni.omni_range = 2.6
		omni.shadow_enabled = false
		omni.position = Vector3(p[0], p[1], p[2])
		add_child(omni)
		lights += 1
	report["lamp_halos"] = lamps.size()
	report["lamp_lights"] = lights


func _lamp_rank(lamp: Dictionary) -> int:
	var kind: String = lamp.get("kind", "")
	return 0 if kind.begins_with("Corridor") else (1 if kind.begins_with("Mill") else 2)


func _build_spray(preset: Dictionary) -> void:
	var amount: int = preset["spray"]
	if amount <= 0:
		report["spray_emitters"] = 0
		return
	var mist := StandardMaterial3D.new()
	mist.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mist.vertex_color_use_as_albedo = true
	mist.albedo_texture = load(BASE + "textures/soft_sprite.png")
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	quad.material = mist
	var emitters := 0
	for fall in scene_data.get("waterfalls", []):
		var p: Array = fall["landing"]
		var particles := CPUParticles3D.new()
		particles.name = "Spray_" + str(fall["name"])
		particles.mesh = quad
		particles.amount = amount
		particles.lifetime = 0.9
		particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		particles.emission_box_extents = Vector3(maxf(0.1, float(fall["width"]) * 0.5), 0.05, 0.12)
		particles.direction = Vector3.UP
		particles.spread = 55.0
		particles.initial_velocity_min = 0.6
		particles.initial_velocity_max = 1.5
		particles.gravity = Vector3(0.0, -3.5, 0.0)
		particles.scale_amount_min = 0.6
		particles.scale_amount_max = 1.6
		particles.color = Color(0.92, 0.97, 1.0, 0.55)
		particles.position = Vector3(p[0], p[1], p[2])
		add_child(particles)
		if water_bodies.has(str(fall["name"])):
			water_bodies[str(fall["name"])]["spray"] = particles
		emitters += 1
	report["spray_emitters"] = emitters


func xform(x: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(x[0][0], x[0][1], x[0][2]), Vector3(x[1][0], x[1][1], x[1][2]), Vector3(x[2][0], x[2][1], x[2][2])), Vector3(x[3][0], x[3][1], x[3][2]))
