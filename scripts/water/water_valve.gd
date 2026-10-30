extends Resource
class_name WaterValve
## A deterministic hydraulic restriction. Openness is clamped to 0..1.

@export_range(0.0, 1.0, 0.01) var openness := 1.0:
	set(value):
		openness = clampf(value, 0.0, 1.0)


func is_open() -> bool:
	return openness > 0.0001
