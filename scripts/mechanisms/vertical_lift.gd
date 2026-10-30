class_name VerticalLift
extends Node3D
## Multi-stop marble lift. The deck is an AnimatableBody3D, so riders (the marble,
## cubes, pyramids) are carried by real contacts rather than teleported. Doors on
## the deck and gates at every landing stay closed unless the deck is parked there.

signal floor_changed(floor_index: int)
signal message(text: String)

const SIDES := {
	"north": Vector3(0.0, 0.0, -1.0),
	"south": Vector3(0.0, 0.0, 1.0),
	"east": Vector3(1.0, 0.0, 0.0),
	"west": Vector3(-1.0, 0.0, 0.0),
}
const LIP_HEIGHT := 0.30
const LIP_THICKNESS := 0.08
const GATE_SPEED := 1.6
const DOOR_SPEED := 2.2
const RIDER_MAX_SPEED := 0.8

var palette: Dictionary
var deck: AnimatableBody3D
var deck_size := Vector3(1.26, 0.18, 1.26)
var floors: Array[float] = []
var exit_sides: Array[String] = []
var initial_locks: Array[bool] = []
var locked: Array[bool] = []
var speed := 0.85
var depart_delay := 0.9
var trigger_bodies: Array[RigidBody3D] = []
## 0..1 power from an external drive (e.g. a water wheel). Upward travel scales
## with it and pauses at 0; downward travel is a braked gravity descent at a
## fixed fraction of speed, so the deck can always come back down.
var drive_factor := 1.0
var requires_drive := false
var gravity_descent_ratio := 0.6
var winch_drum: MeshInstance3D
var drive_notice_shown := false
## Optional finished model riding on the deck instead of the primitive plate
## (config "skin": {"deck": Node3D, "doors": {side: Node3D}}). Physics is the
## same; only the visuals come from the level's own art.
var skin_deck: Node3D
var skin_doors: Dictionary = {}
var skin_door_rest_y: Dictionary = {}

var current_floor := 0
var target_floor := 0
var moving := false
var travel_progress := 0.0
var travel_from_y := 0.0
var travel_to_y := 0.0
var rider_seconds := 0.0
var locked_notice_floor := -1

var door_shapes: Dictionary = {}
var door_visuals: Dictionary = {}
var landing_gates: Array[AnimatableBody3D] = []
var landing_closed_y: Array[float] = []
var landing_open_y: Array[float] = []
var rider_area: Area3D
var signal_lamp: OmniLight3D
var floor_label: Label3D


func setup(config: Dictionary, materials: Dictionary, triggers: Array[RigidBody3D]) -> void:
	palette = materials
	trigger_bodies = triggers
	deck_size = config["size"]
	speed = float(config.get("speed", speed))
	depart_delay = float(config.get("depart_delay", depart_delay))
	for height in config["floors"]:
		floors.append(float(height))
	for side in config["exit_sides"]:
		exit_sides.append(String(side))
	for is_locked in config.get("locked", []):
		initial_locks.append(bool(is_locked))
	while initial_locks.size() < floors.size():
		initial_locks.append(false)
	locked = initial_locks.duplicate()
	var at: Vector3 = config["position"]
	var skin: Dictionary = config.get("skin", {})
	skin_deck = skin.get("deck") as Node3D
	skin_doors = skin.get("doors", {})
	_build_deck(Vector3(at.x, _deck_y(0), at.z))
	_build_shaft(at)
	if skin_deck:
		# The art keeps its world pose at floor 1 and from then on rides the deck.
		skin_deck.reparent(deck, true)
		for side: String in skin_doors:
			var door := skin_doors[side] as Node3D
			door.reparent(deck, true)
			skin_door_rest_y[side] = door.position.y
	var gates: Array = config.get("landing_gates", [])
	for index in range(gates.size()):
		_build_landing_gate(index, gates[index])
	var pads: Array = config.get("call_pads", [])
	for index in range(pads.size()):
		_build_call_pad(index, pads[index])
	_apply_doors(0.0, true)
	_update_indicator()


func physics_step(delta: float) -> void:
	if moving:
		var distance := absf(travel_to_y - travel_from_y)
		var previous_y := deck.position.y
		travel_progress = minf(1.0, travel_progress + delta * _travel_speed() / maxf(distance, 0.01))
		# Smoothstep keeps the start and stop gentle so the marble is neither
		# launched upwards nor left behind by a sudden deceleration.
		var eased := smoothstep(0.0, 1.0, travel_progress)
		deck.position.y = lerpf(travel_from_y, travel_to_y, eased)
		if winch_drum:
			# The drum winds exactly the rope length the deck travelled.
			winch_drum.rotation.x += (deck.position.y - previous_y) / 0.2
		if travel_progress >= 1.0:
			moving = false
			current_floor = target_floor
			rider_seconds = 0.0
			floor_changed.emit(current_floor)
			message.emit("LIFT ARRIVED: FLOOR %d" % (current_floor + 1))
	else:
		_update_departure(delta)
	_apply_doors(delta, false)
	_update_indicator()


func go_to(floor_index: int) -> bool:
	if moving or floor_index == current_floor or floor_index < 0 or floor_index >= floors.size():
		return false
	if floor_index > current_floor and not has_drive():
		if not drive_notice_shown:
			drive_notice_shown = true
			message.emit("LIFT NEEDS POWER — the mill wheel is not driving the winch")
		return false
	drive_notice_shown = false
	if locked[floor_index]:
		if locked_notice_floor != floor_index:
			locked_notice_floor = floor_index
			message.emit("LIFT LOCKED: FLOOR %d needs power" % (floor_index + 1))
		return false
	target_floor = floor_index
	travel_from_y = deck.position.y
	travel_to_y = _deck_y(floor_index)
	travel_progress = 0.0
	rider_seconds = 0.0
	moving = true
	# Close the deck doors before the first tick of travel.
	_apply_doors(0.0, true)
	message.emit("LIFT MOVING %s FLOOR %d" % ["UP TO" if floor_index > current_floor else "DOWN TO", floor_index + 1])
	return true


func unlock_floor(floor_index: int) -> void:
	if floor_index < 0 or floor_index >= locked.size() or not locked[floor_index]:
		return
	locked[floor_index] = false
	locked_notice_floor = -1
	message.emit("LIFT STOP %d UNLOCKED" % (floor_index + 1))


func has_drive() -> bool:
	return not requires_drive or drive_factor > 0.05


func _travel_speed() -> float:
	if not requires_drive:
		return speed
	if target_floor < current_floor:
		return speed * gravity_descent_ratio
	return speed * drive_factor


func is_powered() -> bool:
	return locked.size() > 1 and not locked[1]


func deck_top() -> float:
	return deck.position.y + deck_size.y * 0.5


func reset_lift() -> void:
	moving = false
	current_floor = 0
	target_floor = 0
	travel_progress = 0.0
	rider_seconds = 0.0
	locked_notice_floor = -1
	drive_notice_shown = false
	locked = initial_locks.duplicate()
	deck.position.y = _deck_y(0)
	_apply_doors(0.0, true)
	_update_indicator()


## Every rigid body currently standing on the deck, not only the marble.
func riders() -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	for body in rider_area.get_overlapping_bodies():
		if body is RigidBody3D and _is_centered_rider(body):
			result.append(body)
	return result


func door_open(side: String) -> bool:
	return door_shapes.has(side) and (door_shapes[side] as CollisionShape3D).disabled


func _update_departure(delta: float) -> void:
	var rider_ready := false
	for body in trigger_bodies:
		if is_instance_valid(body) and _is_centered_rider(body):
			rider_ready = true
			break
	rider_seconds = rider_seconds + delta if rider_ready else 0.0
	if rider_seconds < depart_delay:
		return
	rider_seconds = 0.0
	var next_floor := current_floor + 1
	if next_floor < floors.size():
		go_to(next_floor)


func _is_centered_rider(body: RigidBody3D) -> bool:
	var local := deck.to_local(body.global_position)
	var limit_x := deck_size.x * 0.5 - LIP_THICKNESS - 0.30
	var limit_z := deck_size.z * 0.5 - LIP_THICKNESS - 0.30
	var relative_speed := body.linear_velocity.length()
	return absf(local.x) <= limit_x and absf(local.z) <= limit_z and local.y > 0.0 and local.y < 0.85 and relative_speed < RIDER_MAX_SPEED


func _apply_doors(delta: float, snap: bool) -> void:
	for side: String in door_shapes:
		var open := not moving and current_floor < exit_sides.size() and exit_sides[current_floor] == side
		var shape := door_shapes[side] as CollisionShape3D
		if shape.disabled != open:
			# Doors may toggle from an Area3D callback while physics is flushing.
			shape.set_deferred("disabled", open)
		var visual: Node3D = door_visuals[side]
		var target_y := deck_size.y * 0.5 + (-LIP_HEIGHT * 0.5 + 0.01 if open else LIP_HEIGHT * 0.5)
		if skin_door_rest_y.has(side):
			# Skinned doors drop through a slot in the deck when they open.
			target_y = float(skin_door_rest_y[side]) - (LIP_HEIGHT + 0.02 if open else 0.0)
		visual.position.y = target_y if snap else move_toward(visual.position.y, target_y, DOOR_SPEED * delta)
	for index in range(landing_gates.size()):
		var open_here := not moving and current_floor == index
		var target := landing_open_y[index] if open_here else landing_closed_y[index]
		var gate := landing_gates[index]
		gate.position.y = target if snap else move_toward(gate.position.y, target, GATE_SPEED * delta)


func _update_indicator() -> void:
	if floor_label:
		var arrow := ""
		if moving:
			arrow = "▲ " if target_floor > current_floor else "▼ "
		floor_label.text = "LIFT %sFLOOR %d" % [arrow, (target_floor if moving else current_floor) + 1]
	if signal_lamp:
		if moving:
			signal_lamp.light_color = Color("58e59a")
		elif is_powered() and has_drive():
			signal_lamp.light_color = Color("ffb64d")
		else:
			signal_lamp.light_color = Color("ff5c52")


func _deck_y(floor_index: int) -> float:
	return floors[floor_index] - deck_size.y * 0.5


func _build_deck(at: Vector3) -> void:
	deck = AnimatableBody3D.new()
	deck.name = "LiftDeck"
	deck.sync_to_physics = false
	deck.position = at
	var deck_physics := PhysicsMaterial.new()
	deck_physics.friction = 0.9
	deck_physics.bounce = 0.0
	deck.physics_material_override = deck_physics
	add_child(deck)
	_add_box_collision(deck, Vector3.ZERO, deck_size, "LiftDeckCollision")
	if not skin_deck:
		_add_box_visual(deck, Vector3.ZERO, deck_size, palette["steel"], "LiftDeckPlate")
		_add_torus_visual(deck, Vector3(0.0, deck_size.y * 0.52, 0.0), 0.30, 0.44, palette["brass"], "LiftDeckCog")
	for side: String in SIDES:
		var normal: Vector3 = SIDES[side]
		var along_x := absf(normal.z) > 0.5
		var size := Vector3(deck_size.x if along_x else LIP_THICKNESS, LIP_HEIGHT, LIP_THICKNESS if along_x else deck_size.z)
		var offset := Vector3(normal.x * (deck_size.x * 0.5 - LIP_THICKNESS * 0.5), deck_size.y * 0.5 + LIP_HEIGHT * 0.5, normal.z * (deck_size.z * 0.5 - LIP_THICKNESS * 0.5))
		var is_door := exit_sides.has(side)
		var shape := _add_box_collision(deck, offset, size, ("Door" if is_door else "Lip") + side.capitalize() + "Collision")
		if skin_deck:
			if is_door:
				door_shapes[side] = shape
				door_visuals[side] = skin_doors[side] if skin_doors.has(side) else _add_marker(deck, side)
			continue
		var visual := _add_box_visual(deck, offset, size, palette["brass"] if is_door else palette["brass_dark"], ("Door" if is_door else "Lip") + side.capitalize())
		if is_door:
			door_shapes[side] = shape
			door_visuals[side] = visual
	rider_area = Area3D.new()
	rider_area.name = "LiftRiderSensor"
	rider_area.position = Vector3(0.0, deck_size.y * 0.5 + 0.40, 0.0)
	var sensor := CollisionShape3D.new()
	var sensor_shape := BoxShape3D.new()
	sensor_shape.size = Vector3(deck_size.x, 0.80, deck_size.z)
	sensor.shape = sensor_shape
	rider_area.add_child(sensor)
	deck.add_child(rider_area)


func _add_marker(parent: Node3D, side: String) -> Node3D:
	var marker := Node3D.new()
	marker.name = "Door" + side.capitalize()
	parent.add_child(marker)
	return marker


func _build_shaft(at: Vector3) -> void:
	var top := floors[floors.size() - 1] + 1.05
	if skin_deck:
		# The level's own tower, drum and chain are the shaft; keep the signal.
		_build_signal(at, top + 0.75)
		return
	var bottom := floors[0] - 0.20
	var post_height := top - bottom
	for corner_x in [-1.0, 1.0]:
		for corner_z in [-1.0, 1.0]:
			var post_at := Vector3(at.x + corner_x * (deck_size.x * 0.5 + 0.07), bottom + post_height * 0.5, at.z + corner_z * (deck_size.z * 0.5 + 0.07))
			_add_cylinder_visual(self, post_at, 0.045, post_height, palette["brass_dark"], "LiftShaftPost")
	_add_box_visual(self, Vector3(at.x, top, at.z), Vector3(deck_size.x + 0.24, 0.10, deck_size.z + 0.24), palette["brass"], "LiftCrown")
	winch_drum = _add_cylinder_visual(self, Vector3(at.x, top - 0.25, at.z), 0.20, 0.36, palette["copper"], "LiftWinchDrum")
	winch_drum.rotation.z = PI * 0.5
	_build_signal(at, top)


func _build_signal(at: Vector3, top: float) -> void:
	signal_lamp = OmniLight3D.new()
	signal_lamp.name = "LiftSignalLamp"
	signal_lamp.position = Vector3(at.x, top + 0.25, at.z)
	signal_lamp.light_energy = 2.2
	signal_lamp.omni_range = 3.2
	add_child(signal_lamp)
	floor_label = Label3D.new()
	floor_label.name = "LiftFloorIndicator"
	floor_label.position = Vector3(at.x, top + 0.42, at.z)
	floor_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	floor_label.pixel_size = 0.0055
	floor_label.font_size = 54
	floor_label.outline_size = 10
	floor_label.modulate = Color("ffd28a")
	add_child(floor_label)


func _build_landing_gate(index: int, spec: Dictionary) -> void:
	var at: Vector3 = spec["position"]
	var size: Vector3 = spec["size"]
	var gate := AnimatableBody3D.new()
	gate.name = "LandingGate%d" % (index + 1)
	gate.sync_to_physics = false
	var closed_y := at.y + size.y * 0.5
	gate.position = Vector3(at.x, closed_y, at.z)
	add_child(gate)
	_add_box_collision(gate, Vector3.ZERO, size, "LandingGateCollision")
	_add_box_visual(gate, Vector3.ZERO, size, palette["steel"], "LandingGateSlab")
	_add_box_visual(gate, Vector3(0.0, size.y * 0.5, 0.0), Vector3(maxf(size.x, 0.12), 0.06, maxf(size.z, 0.12)), palette["gate_glow"], "LandingGateWarning")
	landing_gates.append(gate)
	landing_closed_y.append(closed_y)
	landing_open_y.append(at.y - size.y * 0.5 - 0.02)


func _build_call_pad(index: int, at: Vector3) -> void:
	_add_cylinder_visual(self, at, 0.34, 0.05, palette["steel"], "LiftCallPad%d" % (index + 1))
	_add_torus_visual(self, at + Vector3.UP * 0.03, 0.22, 0.32, palette["amber_glow"], "LiftCallGlow%d" % (index + 1))
	var area := Area3D.new()
	area.name = "LiftCallTrigger%d" % (index + 1)
	area.position = at + Vector3.UP * 0.25
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.62, 0.50, 0.62)
	collision.shape = shape
	area.add_child(collision)
	add_child(area)
	area.body_entered.connect(_on_call_pad_entered.bind(index))


func _on_call_pad_entered(body: Node3D, floor_index: int) -> void:
	if body is RigidBody3D and trigger_bodies.has(body) and not moving and current_floor != floor_index:
		go_to(floor_index)


func _add_box_collision(parent: Node3D, at: Vector3, size: Vector3, collision_name: String) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	collision.name = collision_name
	collision.position = at
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	parent.add_child(collision)
	return collision


func _add_box_visual(parent: Node3D, at: Vector3, size: Vector3, material: Material, part_name: String) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = part_name
	visual.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	parent.add_child(visual)
	return visual


func _add_cylinder_visual(parent: Node3D, at: Vector3, radius: float, height: float, material: Material, part_name: String) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = part_name
	visual.position = at
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	visual.mesh = mesh
	visual.material_override = material
	parent.add_child(visual)
	return visual


func _add_torus_visual(parent: Node3D, at: Vector3, inner_radius: float, outer_radius: float, material: Material, part_name: String) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = part_name
	visual.position = at
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	visual.mesh = mesh
	visual.material_override = material
	parent.add_child(visual)
	return visual
