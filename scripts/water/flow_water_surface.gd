class_name FlowWaterSurface
extends MeshInstance3D
## Visual water sheet driven by the hydraulic simulation. `set_flow` receives
## the simulated flux; the two UV layers integrate their own phases so the
## surface speeds up, slows and stops together with the real water.

const FlowWaterShader = preload("res://shaders/flow_water.gdshader")

## UV units per second for one unit of simulated flux.
@export var flux_to_uv := 0.55
@export var layer_two_ratio := 0.55
@export var direction := Vector2(0.0, 1.0)
var base_direction := Vector2(0.0, 1.0)
@export var max_visual_speed := 2.4
var water_material: ShaderMaterial
var visual_speed := 0.0
var target_speed := 0.0
var phase_a := 0.0
var phase_b := 0.0


static func create(surface_name: String, size: Vector2, flow_direction: Vector2, waterfall := false) -> FlowWaterSurface:
	var surface := FlowWaterSurface.new()
	surface.name = surface_name
	var mesh := QuadMesh.new() if waterfall else PlaneMesh.new()
	mesh.size = size
	surface.mesh = mesh
	surface.base_direction = flow_direction.normalized() if flow_direction.length_squared() > 0.0 else Vector2(0.0, 1.0)
	surface.direction = surface.base_direction
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.water_material = ShaderMaterial.new()
	surface.water_material.shader = FlowWaterShader
	surface.water_material.set_shader_parameter("waterfall", 1.0 if waterfall else 0.0)
	surface.water_material.set_shader_parameter("uv_scale", maxf(1.0, maxf(size.x, size.y) * 0.8) if not waterfall else 1.0)
	surface.material_override = surface.water_material
	return surface


func set_flux(flux: float) -> void:
	target_speed = clampf(absf(flux) * flux_to_uv, 0.0, max_visual_speed)
	# Reverse flow (pump, back-pressure) visibly runs the other way.
	if absf(flux) > 0.001:
		direction = base_direction * signf(flux)


## Simulated phase advance; called every frame (and by tests directly).
func advance(delta: float) -> void:
	visual_speed = move_toward(visual_speed, target_speed, delta * 2.5)
	phase_a = fmod(phase_a + visual_speed * delta, 1000.0)
	phase_b = fmod(phase_b + visual_speed * layer_two_ratio * delta, 1000.0)
	_apply_parameters()


func _process(delta: float) -> void:
	advance(delta)


func uv_speeds() -> Vector2:
	return Vector2(visual_speed, visual_speed * layer_two_ratio)


func _apply_parameters() -> void:
	if not water_material:
		return
	water_material.set_shader_parameter("flow", direction * visual_speed)
	water_material.set_shader_parameter("flow_phase_a", phase_a)
	water_material.set_shader_parameter("flow_phase_b", phase_b)
	water_material.set_shader_parameter("layer_two_ratio", layer_two_ratio)
