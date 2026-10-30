extends RigidBody3D
class_name PhysicsBall
## Reusable physical marble. Movement is always produced by forces and contacts.

@export var material_id: StringName = &"magnetic_steel"
@export_range(0.05, 1.5, 0.01) var radius := 0.33
var material_profile: BallMaterialProfile
var temperature_c := 20.0


func _ready() -> void:
	configure(material_id)
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	add_to_group("physics_balls")
	if get_node_or_null("CollisionShape3D") == null:
		var collider := CollisionShape3D.new()
		collider.name = "CollisionShape3D"
		var shape := SphereShape3D.new()
		shape.radius = radius
		collider.shape = shape
		add_child(collider)


func configure(profile_id: StringName) -> void:
	material_id = profile_id
	material_profile = PhysicsMaterialCatalog.ball_profile(profile_id)
	mass = material_profile.mass
	linear_damp = material_profile.linear_damp
	angular_damp = material_profile.angular_damp
	physics_material_override = PhysicsMaterialCatalog.contact_material(material_profile, &"metal")
	set_meta("material_id", material_id)


func set_contact_surface(surface_id: StringName) -> void:
	physics_material_override = PhysicsMaterialCatalog.contact_material(material_profile, surface_id)
	set_meta("surface_id", surface_id)


func magnetic_response() -> float:
	return material_profile.magnetic_response if material_profile else 0.0


func adhesion_response() -> float:
	return material_profile.adhesion if material_profile else 0.0
