extends Area3D
class_name WaterVolume
## World-space water boundary backed by one reservoir in WaterNetwork.

@export var reservoir_id: StringName
@export var size := Vector3(3.0, 2.0, 3.0)
@export var water_density := 1000.0
@export var viscosity := 1.0
var network: WaterNetwork
var flow_velocity := Vector3.ZERO


func setup(source_network: WaterNetwork, id: StringName, volume_size: Vector3) -> void:
	network = source_network
	reservoir_id = id
	size = volume_size
	if get_node_or_null("CollisionShape3D") == null:
		var collider := CollisionShape3D.new()
		collider.name = "CollisionShape3D"
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		add_child(collider)


func surface_world_y() -> float:
	if not network or not network.reservoirs.has(reservoir_id):
		return global_position.y - size.y * 0.5
	var bottom := global_position.y - size.y * 0.5
	return bottom + clampf(network.fill_ratio(reservoir_id), 0.0, 1.0) * size.y


func submerged_fraction(ball: PhysicsBall) -> float:
	var sphere_bottom := ball.global_position.y - ball.radius
	var submerged_height := clampf(surface_world_y() - sphere_bottom, 0.0, ball.radius * 2.0)
	if submerged_height <= 0.0:
		return 0.0
	if submerged_height >= ball.radius * 2.0:
		return 1.0
	# Exact spherical-cap fraction for a sphere intersected by a horizontal plane.
	var cap_volume := PI * submerged_height * submerged_height * (ball.radius - submerged_height / 3.0)
	var sphere_volume := 4.0 * PI * pow(ball.radius, 3.0) / 3.0
	return clampf(cap_volume / sphere_volume, 0.0, 1.0)
