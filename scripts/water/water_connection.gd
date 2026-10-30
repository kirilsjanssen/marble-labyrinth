extends Resource
class_name WaterConnection
## Bidirectional channel between two reservoir IDs.

@export var reservoir_a: StringName
@export var reservoir_b: StringName
@export_range(0.0, 20.0, 0.01) var conductance := 1.0
@export_range(0.0, 50.0, 0.01) var max_flow := 2.0
@export var outlet_height_a := 0.0
@export var outlet_height_b := 0.0
@export var valve: WaterValve
@export var pump: WaterPump
var last_flux := 0.0


func openness() -> float:
	return valve.openness if valve else 1.0
