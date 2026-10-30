extends MeshInstance3D
class_name WaterSurfaceVisual
## Low-cost Compatibility renderer driven strictly by WaterNetwork data.

var water_volume: WaterVolume
var _box := BoxMesh.new()


func setup(volume: WaterVolume, color := Color(0.12, 0.52, 0.78, 0.68)) -> void:
	water_volume = volume
	mesh = _box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.roughness = 0.22
	material.metallic = 0.05
	material_override = material
	_update_from_model()


func _process(_delta: float) -> void:
	_update_from_model()


func _update_from_model() -> void:
	if not water_volume or not water_volume.network:
		return
	var ratio := clampf(water_volume.network.fill_ratio(water_volume.reservoir_id), 0.0, 1.0)
	var height := maxf(0.01, water_volume.size.y * ratio)
	_box.size = Vector3(water_volume.size.x * 0.96, height, water_volume.size.z * 0.96)
	global_position = Vector3(water_volume.global_position.x, water_volume.global_position.y - water_volume.size.y * 0.5 + height * 0.5, water_volume.global_position.z)
