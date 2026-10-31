extends RigidBody3D
class_name PuzzleShapeBody
## Reusable non-spherical dynamic obstacle/puzzle body.
## Same material catalogue as P1 marbles; colliders are real convex physics shapes.
## Shape-specific buoyancy is a later feature; no assumption that every item is a ball.

enum BodyShape { CUBE, PYRAMID }

@export var body_shape := BodyShape.CUBE
@export var material_id: StringName = &"wood"
@export var body_size := Vector3(0.75, 0.75, 0.75)

var material_profile: BallMaterialProfile


func _ready() -> void:
	configure(material_id)
	_build_shape()
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	add_to_group("puzzle_bodies")


func configure(profile_id: StringName) -> void:
	material_id = profile_id
	material_profile = PhysicsMaterialCatalog.ball_profile(profile_id)
	mass = material_profile.mass
	linear_damp = material_profile.linear_damp
	angular_damp = material_profile.angular_damp
	physics_material_override = PhysicsMaterialCatalog.contact_material(material_profile, &"metal")
	set_meta("material_id", profile_id)


func magnetic_response() -> float:
	return material_profile.magnetic_response if material_profile else 0.0


func adhesion_response() -> float:
	return material_profile.adhesion if material_profile else 0.0


func geometric_volume() -> float:
	var volume := body_size.x * body_size.y * body_size.z
	return volume if body_shape == BodyShape.CUBE else volume / 3.0


func _build_shape() -> void:
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var visual := MeshInstance3D.new()
	visual.name = "VisibleShape"
	if body_shape == BodyShape.CUBE:
		var box := BoxShape3D.new()
		box.size = body_size
		collision.shape = box
		var box_mesh := BoxMesh.new()
		box_mesh.size = body_size
		visual.mesh = box_mesh
	else:
		var half_width := body_size.x * 0.5
		var half_depth := body_size.z * 0.5
		var base_height := -body_size.y * 0.5
		var corners := PackedVector3Array([
			Vector3(-half_width, base_height, -half_depth),
			Vector3(half_width, base_height, -half_depth),
			Vector3(half_width, base_height, half_depth),
			Vector3(-half_width, base_height, half_depth),
			Vector3(0.0, body_size.y * 0.5, 0.0)
		])
		var pyramid := ConvexPolygonShape3D.new()
		pyramid.points = corners
		collision.shape = pyramid
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in [0, 2, 1, 0, 3, 2, 0, 1, 4, 1, 2, 4, 2, 3, 4, 3, 0, 4]:
			surface.add_vertex(corners[index])
		surface.generate_normals()
		visual.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b58a43") if material_id == &"magnetic_steel" else Color("b28a5b")
	material.metallic = 0.65 if material_id == &"magnetic_steel" else 0.05
	material.roughness = 0.48
	visual.material_override = material
	add_child(collision)
	add_child(visual)
