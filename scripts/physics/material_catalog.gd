extends RefCounted
class_name PhysicsMaterialCatalog
## Original, gameplay-calibrated ball and surface definitions.

const BALL_IDS: Array[StringName] = [
	&"wood", &"aluminum", &"magnetic_steel", &"rubber", &"glass", &"stone", &"hollow"
]
const SURFACE_IDS: Array[StringName] = [
	&"wood", &"metal", &"rubber", &"ice", &"stone", &"sand", &"oil", &"mud", &"sticky"
]


static func ball_profile(profile_id: StringName) -> BallMaterialProfile:
	var profile := BallMaterialProfile.new()
	profile.id = profile_id
	match profile_id:
		&"wood":
			_set_ball(profile, "Wood", 0.22, 720.0, 0.62, 0.12, 0.10, 0.08, 0.0, 0.20, 170.0)
		&"aluminum":
			_set_ball(profile, "Aluminum", 0.28, 2700.0, 0.42, 0.16, 0.07, 0.05, 0.0, 0.05, 520.0)
		&"magnetic_steel":
			_set_ball(profile, "Magnetic steel", 0.44, 7850.0, 0.50, 0.10, 0.08, 0.05, 1.0, 0.02, 780.0)
		&"rubber":
			_set_ball(profile, "Rubber", 0.24, 1100.0, 0.92, 0.78, 0.11, 0.12, 0.0, 0.70, 150.0)
		&"glass":
			_set_ball(profile, "Glass", 0.31, 2500.0, 0.36, 0.30, 0.06, 0.04, 0.0, 0.02, 240.0)
		&"stone":
			_set_ball(profile, "Stone", 0.52, 3000.0, 0.78, 0.05, 0.14, 0.10, 0.0, 0.12, 900.0)
		&"hollow":
			_set_ball(profile, "Hollow shell", 0.11, 420.0, 0.34, 0.22, 0.18, 0.10, 0.0, 0.08, 210.0)
		_:
			push_warning("Unknown ball material '%s'; using magnetic steel" % profile_id)
			return ball_profile(&"magnetic_steel")
	return profile


static func surface_profile(surface_id: StringName) -> Dictionary:
	match surface_id:
		&"wood": return {"id": surface_id, "friction": 0.62, "bounce": 0.08, "rolling_deceleration": 0.18}
		&"metal": return {"id": surface_id, "friction": 0.40, "bounce": 0.16, "rolling_deceleration": 0.10}
		&"rubber": return {"id": surface_id, "friction": 1.10, "bounce": 0.62, "rolling_deceleration": 0.42}
		&"ice": return {"id": surface_id, "friction": 0.025, "bounce": 0.03, "rolling_deceleration": 0.012}
		&"stone": return {"id": surface_id, "friction": 0.82, "bounce": 0.04, "rolling_deceleration": 0.34}
		&"sand": return {"id": surface_id, "friction": 1.25, "bounce": 0.0, "rolling_deceleration": 1.60}
		&"oil": return {"id": surface_id, "friction": 0.012, "bounce": 0.01, "rolling_deceleration": 0.006}
		&"mud": return {"id": surface_id, "friction": 0.94, "bounce": 0.0, "rolling_deceleration": 2.20}
		&"sticky": return {"id": surface_id, "friction": 1.40, "bounce": 0.0, "rolling_deceleration": 3.20}
		_:
			push_warning("Unknown surface '%s'; using stone" % surface_id)
			return surface_profile(&"stone")


static func contact_material(ball: BallMaterialProfile, surface_id: StringName) -> PhysicsMaterial:
	var surface := surface_profile(surface_id)
	var material := PhysicsMaterial.new()
	# Geometric mean preserves differences in both halves of the contact pair.
	material.friction = sqrt(ball.friction * float(surface.friction))
	material.bounce = clampf(maxf(ball.bounce, float(surface.bounce)), 0.0, 0.92)
	material.rough = surface_id in [&"sand", &"mud", &"sticky", &"rubber"]
	material.absorbent = surface_id in [&"sand", &"mud", &"sticky"]
	return material


static func _set_ball(profile: BallMaterialProfile, title: String, body_mass: float, body_density: float, body_friction: float, body_bounce: float, body_linear_damp: float, body_angular_damp: float, magnetic: float, sticky: float, heat_limit: float) -> void:
	profile.display_name = title
	profile.mass = body_mass
	profile.density = body_density
	profile.friction = body_friction
	profile.bounce = body_bounce
	profile.linear_damp = body_linear_damp
	profile.angular_damp = body_angular_damp
	profile.magnetic_response = magnetic
	profile.adhesion = sticky
	profile.damage_temperature = heat_limit
