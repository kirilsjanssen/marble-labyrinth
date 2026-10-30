extends Control
## Draw-only thumb indicator for the board-tilt gesture.
## It never captures touch events or directly moves a RigidBody3D.

var vector := Vector2.ZERO


func set_tilt(value: Vector2) -> void:
	var next := value.limit_length(1.0)
	if vector.distance_squared_to(next) > 0.0001:
		vector = next
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var outer := minf(size.x, size.y) * 0.43
	draw_circle(center, outer, Color(0.045, 0.065, 0.085, 0.60))
	draw_arc(center, outer, 0.0, TAU, 64, Color(0.96, 0.70, 0.33, 0.88), 3.0, true)
	draw_line(center + Vector2(-outer * 0.60, 0.0), center + Vector2(outer * 0.60, 0.0), Color(0.8, 0.8, 0.8, 0.35), 1.0, true)
	draw_line(center + Vector2(0.0, -outer * 0.60), center + Vector2(0.0, outer * 0.60), Color(0.8, 0.8, 0.8, 0.35), 1.0, true)
	var thumb := center + vector * outer * 0.58
	draw_circle(thumb, outer * 0.27, Color(0.99, 0.70, 0.27, 0.94))
	draw_arc(thumb, outer * 0.27, 0.0, TAU, 24, Color(0.18, 0.12, 0.05), 2.0, true)
