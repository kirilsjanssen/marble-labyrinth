extends Node3D
class_name PhysicsLab
## Playable P1 laboratory assembled from the reusable physics components.

var test_balls: Dictionary = {}


func _ready() -> void:
	_build_environment()
	_build_surface_lane("IceLane", Vector3(-4.0, 0.0, 0.0), &"ice", Color("8fdcff"))
	_build_surface_lane("WoodLane", Vector3(0.0, 0.0, 0.0), &"wood", Color("9c6338"))
	_build_surface_lane("StickyLane", Vector3(4.0, 0.0, 0.0), &"sticky", Color("7ab34e"))
	_spawn_lane_ball("IceBall", Vector3(-4.0, 0.58, -5.2), &"magnetic_steel", &"ice")
	_spawn_lane_ball("WoodBall", Vector3(0.0, 0.58, -5.2), &"magnetic_steel", &"wood")
	_spawn_lane_ball("StickyBall", Vector3(4.0, 0.58, -5.2), &"magnetic_steel", &"sticky")
	_build_bounce_station()
	_build_wind_station()
	_build_magnet_station()
	_build_gravity_station()


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101722")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8fa7c4")
	environment.ambient_light_energy = 0.65
	world.environment = environment
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58.0, -28.0, 0.0)
	light.light_energy = 1.8
	light.shadow_enabled = true
	add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(15.0, 18.0, 22.0)
	camera.look_at_from_position(camera.position, Vector3.ZERO)
	camera.current = true
	add_child(camera)


func _build_surface_lane(lane_name: String, at: Vector3, surface_id: StringName, color: Color) -> void:
	var floor := StaticBody3D.new()
	floor.name = lane_name + "Floor"
	floor.position = at
	floor.physics_material_override = _surface_physics_material(surface_id)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 0.25, 13.0)
	collider.shape = box
	floor.add_child(collider)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material
	floor.add_child(mesh_instance)
	add_child(floor)

	var zone := SurfaceZone.new()
	zone.name = lane_name + "SurfaceZone"
	zone.position = at + Vector3.UP * 0.55
	zone.surface_id = surface_id
	var zone_collision := CollisionShape3D.new()
	var zone_box := BoxShape3D.new()
	zone_box.size = Vector3(2.55, 1.0, 13.0)
	zone_collision.shape = zone_box
	zone.add_child(zone_collision)
	add_child(zone)


func _spawn_lane_ball(ball_name: String, at: Vector3, material_id: StringName, surface_id: StringName) -> PhysicsBall:
	var ball := _spawn_ball(ball_name, at, material_id)
	ball.set_contact_surface(surface_id)
	ball.linear_velocity = Vector3(0.0, 0.0, 5.0)
	return ball


func _build_bounce_station() -> void:
	var floor := StaticBody3D.new()
	floor.name = "BounceFloor"
	floor.position = Vector3(8.0, 0.0, -4.0)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(5.0, 0.25, 4.0)
	collider.shape = shape
	floor.add_child(collider)
	floor.physics_material_override = _surface_physics_material(&"metal")
	add_child(floor)
	_spawn_ball("RubberDrop", Vector3(7.0, 4.0, -4.0), &"rubber").set_contact_surface(&"metal")
	_spawn_ball("StoneDrop", Vector3(9.0, 4.0, -4.0), &"stone").set_contact_surface(&"metal")


func _build_wind_station() -> void:
	var field := _make_sphere_field("WindField", Vector3(-9.0, 4.0, 4.0), 2.0)
	field.field_type = FieldZone.FieldType.WIND
	field.direction = Vector3.RIGHT
	field.strength = 1.8
	field.max_force = 1.8
	var ball := _spawn_ball("WindBall", Vector3(-9.0, 4.0, 4.0), &"hollow")
	ball.gravity_scale = 0.0


func _build_magnet_station() -> void:
	var field := _make_sphere_field("MagneticField", Vector3(9.0, 4.0, 5.0), 4.0)
	field.field_type = FieldZone.FieldType.MAGNETIC
	field.strength = 18.0
	field.max_force = 7.0
	var steel := _spawn_ball("MagneticSteelBall", Vector3(6.0, 4.0, 4.4), &"magnetic_steel")
	steel.gravity_scale = 0.0
	var aluminum := _spawn_ball("AluminumBall", Vector3(6.0, 4.0, 5.6), &"aluminum")
	aluminum.gravity_scale = 0.0


func _build_gravity_station() -> void:
	var field := _make_sphere_field("ZeroGravityField", Vector3(-4.0, 7.0, 9.0), 2.0)
	field.field_type = FieldZone.FieldType.LOCAL_GRAVITY
	field.direction = Vector3.ZERO
	field.strength = 0.0
	field.max_force = 20.0
	_spawn_ball("ZeroGravityBall", Vector3(-4.0, 7.0, 9.0), &"glass")
	_spawn_ball("GravityControlBall", Vector3(0.0, 7.0, 9.0), &"glass")


func _make_sphere_field(field_name: String, at: Vector3, radius: float) -> FieldZone:
	var field := FieldZone.new()
	field.name = field_name
	field.position = at
	var collider := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	collider.shape = shape
	field.add_child(collider)
	add_child(field)
	return field


func _spawn_ball(ball_name: String, at: Vector3, material_id: StringName) -> PhysicsBall:
	var ball := PhysicsBall.new()
	ball.name = ball_name
	ball.position = at
	ball.material_id = material_id
	add_child(ball)
	test_balls[ball_name] = ball
	return ball


func _surface_physics_material(surface_id: StringName) -> PhysicsMaterial:
	var profile := PhysicsMaterialCatalog.surface_profile(surface_id)
	var material := PhysicsMaterial.new()
	material.friction = float(profile.friction)
	material.bounce = float(profile.bounce)
	material.rough = surface_id in [&"rubber", &"sand", &"mud", &"sticky"]
	material.absorbent = surface_id in [&"sand", &"mud", &"sticky"]
	return material
