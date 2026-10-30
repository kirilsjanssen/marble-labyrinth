extends Resource
class_name WaterPump
## Pump flow is positive from a connection's A reservoir to B.

@export var enabled := false
@export_range(-1.0, 1.0, 1.0) var direction := 1.0
@export_range(0.0, 20.0, 0.01) var flow_rate := 1.0
@export_range(0.0, 20.0, 0.01) var max_head := 4.0


func requested_flow(head_difference: float) -> float:
	if not enabled or is_zero_approx(direction):
		return 0.0
	# A pump cannot exceed its configured head. It also cannot create liquid;
	# source availability is limited later by WaterNetwork.
	if direction > 0.0 and -head_difference > max_head:
		return 0.0
	if direction < 0.0 and head_difference > max_head:
		return 0.0
	return flow_rate * signf(direction)
