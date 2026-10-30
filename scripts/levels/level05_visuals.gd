class_name Level05Visuals
extends Node3D
## Level 05 Alpine Watermill, mobile visual build for GL Compatibility.
## Instances the exported GLB (tools/blender/export_level05_mobile.py) and adds
## what glTF cannot carry: water shaders, MultiMesh conifers, box colliders,
## the rendered panorama sky with parallax rings, cheap lantern glow and three
## quality tiers. Mechanisms stay separate GLB nodes with their own pivots, so
## the existing gameplay scripts can drive them later.

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

@export var quality := Quality.HIGH
@export var build_colliders := true

var level_root: Node3D
var scene_data := {}
var water_params := {}
var report := {}


func _ready() -> void:
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
	_build_environment(preset)
	_build_parallax(preset)
	_build_lamps(preset)
	_build_spray(preset)


func _json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _layer(name: String) -> Dictionary:
	return water_params.get("layers", {}).get(name, {})


# Materials ------------------------------------------------------------------

func _apply_materials(root: Node, preset: Dictionary) -> void:
	var channel := _layer("channel")
	var body := _layer("fall_body")
	var foam := _layer("fall_foam")
	var water := ShaderMaterial.new()
	water.shader = WaterShader
	water.set_shader_parameter("foam_texture", load(BASE + "textures/water_foam.jpg"))
	water.set_shader_parameter("normal_texture", load(BASE + "textures/water_normal.png"))
	water.set_shader_parameter("tile_a", channel.get("tile_a", 1.6))
	water.set_shader_parameter("speed_a", channel.get("speed_a", 0.45))
	water.set_shader_parameter("tile_b", channel.get("tile_b", 0.9))
	water.set_shader_parameter("speed_b", channel.get("speed_b", 0.75))
	water.set_shader_parameter("detail", preset["water_detail"])
	var fall_body := _fall_material(0, "textures/waterfall_streaks.png", body)
	var fall_foam := _fall_material(1, "textures/waterfall_foam_mask.png", foam)
	var spray := _fall_material(2, "", {})
	spray.set_shader_parameter("opacity", 0.75)
	var count := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.name.begins_with("Terrain"):
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i)
			if material == null:
				continue
			match material.resource_name:
				"M_Water":
					mesh_instance.set_surface_override_material(i, water)
					mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				"M_FallBody":
					mesh_instance.set_surface_override_material(i, fall_body)
					mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				"M_FallFoam":
					mesh_instance.set_surface_override_material(i, fall_foam)
				"M_Spray":
					mesh_instance.set_surface_override_material(i, spray)
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
			count += 1
	report["surfaces"] = count


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
			var x: Array = keep[i]
			var basis := Basis(Vector3(x[0][0], x[0][1], x[0][2]), Vector3(x[1][0], x[1][1], x[1][2]), Vector3(x[2][0], x[2][1], x[2][2]))
			multimesh.set_instance_transform(i, Transform3D(basis, Vector3(x[3][0], x[3][1], x[3][2])))
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
	var body := StaticBody3D.new()
	body.name = "Level05Colliders"
	add_child(body)
	for entry in data.get("static", []):
		body.add_child(_box_shape(entry, entry.get("tag", "")))
	var dynamic := 0
	for entry in data.get("dynamic", []):
		var node := level_root.find_child(entry["node"], true, false) as Node3D
		if node == null:
			push_warning("Level05: collider node %s missing" % entry["node"])
			continue
		# Mechanism colliders ride on their node, so they move with its pivot.
		var mover := AnimatableBody3D.new()
		mover.name = "Collider"
		mover.sync_to_physics = false
		mover.add_child(_box_shape(entry, "box"))
		node.add_child(mover)
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

func _build_environment(preset: Dictionary) -> void:
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = load(BASE + "parallax/" + str(preset["sky"]))
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
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
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun_data: Dictionary = scene_data.get("sun", {})
	var sun := DirectionalLight3D.new()
	sun.name = "AlpineSun"
	if sun_data.has("xform"):
		sun.transform = _xform(sun_data["xform"])
	var color: Array = sun_data.get("color", [1.0, 0.8, 0.55])
	sun.light_color = Color(color[0], color[1], color[2])
	sun.light_energy = 1.55
	sun.shadow_enabled = preset["shadows"]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if int(preset["shadow_splits"]) <= 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 32.0
	add_child(sun)


func _build_parallax(_preset: Dictionary) -> void:
	# Far snowy Alps and sky are the panorama itself (correct for any camera
	# yaw, including CHASE). The rings in level05_parallax.json add depth
	# between it and the summit.
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
	ring.position = CENTRE + Vector3(0.0, (top + bottom) * 0.5, 0.0)
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
	glow.no_depth_test = false
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
		emitters += 1
	report["spray_emitters"] = emitters


func _xform(x: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(x[0][0], x[0][1], x[0][2]), Vector3(x[1][0], x[1][1], x[1][2]), Vector3(x[2][0], x[2][1], x[2][2])), Vector3(x[3][0], x[3][1], x[3][2]))
