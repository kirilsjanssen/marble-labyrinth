extends Area3D
class_name SurfaceZone
## Associates a physical contact pair with a lane and applies rolling resistance.

@export var surface_id: StringName = &"stone"
var _bodies: Array[PhysicsBall] = []


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	var profile := PhysicsMaterialCatalog.surface_profile(surface_id)
	var deceleration: float = float(profile.rolling_deceleration)
	for body in _bodies:
		if not is_instance_valid(body):
			continue
		var horizontal := Vector3(body.linear_velocity.x, 0.0, body.linear_velocity.z)
		if horizontal.length() > 0.03 and deceleration > 0.0:
			body.apply_central_force(-horizontal.normalized() * body.mass * deceleration)


func _on_body_entered(body: Node3D) -> void:
	if body is PhysicsBall:
		var ball := body as PhysicsBall
		ball.set_contact_surface(surface_id)
		if not _bodies.has(ball):
			_bodies.append(ball)


func _on_body_exited(body: Node3D) -> void:
	if body is PhysicsBall:
		_bodies.erase(body as PhysicsBall)
