class_name SmartCameraController
extends Node
## Chooses between the overview orbit and a behind-the-marble chase view.
## The owner supplies the overview pose each frame; this node checks with physics
## rays whether that pose can actually see the marble, and blends to a chase pose
## behind the marble while level geometry hides it.

signal mode_changed(mode: Mode)

enum Mode { OVERVIEW, ORBIT, CHASE }
enum Preference { AUTO, OVERVIEW, CHASE }

## Hysteresis: brief overlaps (a passing gear, a pillar) never flip the view.
const OCCLUDED_ENTER_SECONDS := 0.35
const VISIBLE_EXIT_SECONDS := 0.90
const BLEND_SPEED := 2.4
const CHASE_DISTANCE := 2.25
const CHASE_HEIGHT := 0.92
const CHASE_LOOK_AHEAD := 1.18
const CAMERA_CLEARANCE := 0.18
const CHASE_FOLLOW_SHARPNESS := 9.0
const HEADING_TURN_RATE := 1.7
const MIN_HEADING_SPEED := 0.55
const REVERSE_CONFIRM_SECONDS := 1.1
const PROBE_TOP_OFFSET := 0.24
## Chase placements tried in order (distance behind, height above the marble).
## A placement is skipped while a moving part (gear hub, shutter) would fill
## the frame; the smoothing below hides the hand-over between placements.
const CHASE_PLACEMENTS: Array[Vector2] = [Vector2(2.55, 1.20), Vector2(2.25, 0.92), Vector2(1.90, 1.05), Vector2(1.55, 0.82), Vector2(1.18, 0.72)]
const SIGHT_RADIUS := 0.14

var camera: Camera3D
var target: RigidBody3D
## Only this body (the level's walls and decks) can hide the marble or push the
## camera. Gears, sweepers and shutters pass through view instead of making the
## camera jump every time an arm sweeps past.
var static_geometry: CollisionObject3D
## Automatic switching is opt-in per level; manual CHASE works everywhere.
var auto_enabled := false
var preference := Preference.AUTO
## True after the player has dragged the overview away from its default angle.
var orbit_active := false
var mode := Mode.OVERVIEW
var chase_blend := 0.0
var auto_chase := false
var overview_occluded := false
var occluded_seconds := 0.0
var visible_seconds := 0.0
var heading := Vector3.FORWARD
var reverse_seconds := 0.0
## Tests can force the probe result: -1 = real raycast, 0 = visible, 1 = hidden.
var probe_override := -1

var _chase_position := Vector3.ZERO
var _chase_initialized := false


func reset_state() -> void:
	auto_chase = false
	overview_occluded = false
	occluded_seconds = 0.0
	visible_seconds = 0.0
	reverse_seconds = 0.0
	chase_blend = 0.0
	_chase_initialized = false
	orbit_active = false
	_set_mode(Mode.OVERVIEW)


func cycle_preference() -> Preference:
	preference = ((preference + 1) % Preference.size()) as Preference
	if preference != Preference.AUTO:
		auto_chase = false
	return preference


func wants_chase() -> bool:
	return preference == Preference.CHASE or (preference == Preference.AUTO and auto_enabled and auto_chase)


## delta == 0 snaps straight to the current target pose (used on level load and
## by callers that need an immediately consistent camera basis).
func update(delta: float, overview_position: Vector3, overview_target: Vector3) -> void:
	if camera == null:
		return
	var has_target := target != null and is_instance_valid(target) and target.is_inside_tree()
	if has_target:
		_update_occlusion(delta, overview_position)
	var chase := has_target and wants_chase()
	if chase and not _chase_initialized:
		_begin_chase(overview_position)
	if delta <= 0.0:
		chase_blend = 1.0 if chase else 0.0
	else:
		chase_blend = move_toward(chase_blend, 1.0 if chase else 0.0, delta * BLEND_SPEED)
	if chase_blend <= 0.0:
		_chase_initialized = false

	var weight := smoothstep(0.0, 1.0, chase_blend)
	var position := overview_position
	var look := overview_target
	if has_target and weight > 0.0:
		_update_heading(delta)
		var chase_pose := _chase_pose(delta)
		position = overview_position.lerp(chase_pose[0], weight)
		look = overview_target.lerp(chase_pose[1], weight)
		# The blend path from high above can cut through an upper deck; keep the
		# camera on the marble's side of any surface.
		position = _clamp_to_clear(target.global_position, position)
	camera.global_position = position
	if position.distance_squared_to(look) > 0.0001:
		var up := Vector3.UP if absf((look - position).normalized().dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
		camera.look_at(look, up)
	_set_mode(Mode.CHASE if chase_blend > 0.5 else (Mode.ORBIT if orbit_active else Mode.OVERVIEW))


func mode_name() -> String:
	match mode:
		Mode.CHASE:
			return "CHASE"
		Mode.ORBIT:
			return "ORBIT"
		_:
			return "OVERVIEW"


func preference_name() -> String:
	match preference:
		Preference.OVERVIEW:
			return "TOP"
		Preference.CHASE:
			return "CHASE"
		_:
			return "AUTO"


func is_marble_occluded_from(origin: Vector3) -> bool:
	if probe_override >= 0:
		return probe_override == 1
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return false
	var space := target.get_world_3d().direct_space_state
	var centre := target.global_position
	# Both the centre and the crown must be hidden: a wall clipping only the
	# lower half of the marble still leaves it readable from above.
	return _ray_blocked(space, origin, centre) and _ray_blocked(space, origin, centre + Vector3.UP * PROBE_TOP_OFFSET)


func _update_occlusion(delta: float, overview_position: Vector3) -> void:
	overview_occluded = is_marble_occluded_from(overview_position)
	if overview_occluded:
		occluded_seconds += delta
		visible_seconds = 0.0
	else:
		visible_seconds += delta
		occluded_seconds = 0.0
	if not auto_enabled or preference != Preference.AUTO:
		auto_chase = false
		return
	if not auto_chase and occluded_seconds >= OCCLUDED_ENTER_SECONDS:
		auto_chase = true
	elif auto_chase and visible_seconds >= VISIBLE_EXIT_SECONDS:
		auto_chase = false


func _begin_chase(overview_position: Vector3) -> void:
	# Start looking the same way the overview camera looked, so the player's
	# screen-relative tilt keeps its meaning at the moment of the switch.
	var forward := target.global_position - overview_position
	forward.y = 0.0
	heading = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	# Labyrinth corridors run along the board axes: start along the axis that
	# leaves room behind the marble, preferring the one closest to the overview.
	heading = _best_start_axis(heading)
	reverse_seconds = 0.0
	_chase_position = overview_position
	_chase_initialized = true


func _update_heading(delta: float) -> void:
	if delta <= 0.0:
		return
	var velocity := target.linear_velocity
	velocity.y = 0.0
	if velocity.length() < MIN_HEADING_SPEED:
		# Stopped or creeping: hold the current view instead of spinning.
		reverse_seconds = 0.0
		return
	var direction := velocity.normalized()
	if direction.dot(heading) < -0.35:
		# Rolling backwards briefly (a bump, a correction) must not whip the
		# camera around; only a sustained reverse turns it.
		reverse_seconds += delta
		if reverse_seconds < REVERSE_CONFIRM_SECONDS:
			return
	else:
		reverse_seconds = 0.0
	var angle := heading.signed_angle_to(direction, Vector3.UP)
	var step := clampf(angle, -HEADING_TURN_RATE * delta, HEADING_TURN_RATE * delta)
	heading = heading.rotated(Vector3.UP, step).normalized()


func _chase_pose(delta: float) -> Array[Vector3]:
	var ball := target.global_position
	var desired := _clamp_to_clear(ball, ball - heading * CHASE_DISTANCE + Vector3.UP * CHASE_HEIGHT)
	var space := target.get_world_3d().direct_space_state
	for placement in CHASE_PLACEMENTS:
		var candidate := _clamp_to_clear(ball, ball - heading * placement.x + Vector3.UP * placement.y)
		if _sight_clear(space, candidate, ball):
			desired = candidate
			break
	if delta <= 0.0 or not _chase_initialized:
		_chase_position = desired
	else:
		_chase_position = _chase_position.lerp(desired, 1.0 - exp(-CHASE_FOLLOW_SHARPNESS * delta))
	_chase_position = _clamp_to_clear(ball, _chase_position)
	var look := ball + heading * CHASE_LOOK_AHEAD + Vector3.UP * 0.10
	var pose: Array[Vector3] = [_chase_position, look]
	return pose


func _best_start_axis(overview_forward: Vector3) -> Vector3:
	var basis := static_geometry.global_basis if static_geometry and static_geometry.is_inside_tree() else Basis.IDENTITY
	var ball := target.global_position
	var best := overview_forward
	var best_score := -INF
	for axis in [basis.x, -basis.x, basis.z, -basis.z]:
		var flat: Vector3 = axis
		flat.y = 0.0
		if flat.length_squared() < 0.0001:
			continue
		flat = flat.normalized()
		var wanted := ball - flat * CHASE_DISTANCE + Vector3.UP * CHASE_HEIGHT
		var room := ball.distance_to(_clamp_to_clear(ball, wanted)) / ball.distance_to(wanted)
		# Room behind the marble dominates: a camera squeezed against a rail
		# shows nothing. Alignment breaks ties so controls change the least.
		var score := room * 2.0 + flat.dot(overview_forward)
		if score > best_score:
			best_score = score
			best = flat
	return best


func _clamp_to_clear(from: Vector3, to: Vector3) -> Vector3:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return to
	var hit := _static_hit(target.get_world_3d().direct_space_state, from, to)
	if hit.is_empty():
		return to
	var hit_position: Vector3 = hit["position"]
	var back := from - hit_position
	if back.length_squared() < 0.0001:
		return from
	return hit_position + back.normalized() * minf(CAMERA_CLEARANCE, back.length())


## A thin sphere sweep from the camera to the marble: true when nothing at all
## (static or moving) blocks the view of it.
func _sight_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var span := to - from
	var length := span.length()
	if length < 0.05:
		return true
	var probe := SphereShape3D.new()
	probe.radius = SIGHT_RADIUS
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.transform = Transform3D(Basis.IDENTITY, from)
	# Stop short of the marble's own surface.
	params.motion = span * maxf(0.0, (length - 0.45) / length)
	params.exclude = [target.get_rid()]
	var result := space.cast_motion(params)
	return result.size() == 2 and result[0] >= 0.999


func _ray_blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	return not _static_hit(space, from, to).is_empty()


func _static_hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclude: Array[RID] = [target.get_rid()]
	for _attempt in range(8):
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty() or static_geometry == null or hit["collider"] == static_geometry:
			return hit
		exclude.append(hit["rid"])
	return {}


func _set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	mode_changed.emit(mode)
