class_name WaterWheel
extends AnimatableBody3D
## Overshot mill wheel turned by the simulated flux through its buckets. The
## wheel owns a gear train: every attached gear turns at a fixed ratio of the
## wheel angle, and the drive it delivers to a lift is derived from the same
## angular velocity. No gear spins on its own.

signal state_changed(state: State)

enum State { NO_WATER, LOW_FLOW, WORKING, OVERLOAD }

@export var radius := 0.9
@export var width := 0.42
@export var paddle_count := 12
## Angular speed (rad/s) produced by one unit of flux once the wheel is up to speed.
@export var rad_per_flux := 1.6
@export var low_flux := 0.08
@export var working_flux := 0.45
@export var overload_flux := 2.3
## Inertia: how quickly the wheel follows the water (1/s).
@export var response := 1.4

var flux := 0.0
var angular_speed := 0.0
var wheel_angle := 0.0
var state := State.NO_WATER
var _gears: Array[Node3D] = []
var _gear_ratios: Array[float] = []
var _gear_axes: Array[Vector3] = []


func build(palette: Dictionary) -> void:
	sync_to_physics = false
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = radius * 0.88
	rim_mesh.outer_radius = radius
	for side in [-1.0, 1.0]:
		var rim := MeshInstance3D.new()
		rim.name = "WheelRim"
		rim.mesh = rim_mesh
		rim.rotation.z = PI * 0.5
		rim.position = Vector3(side * width * 0.5, 0.0, 0.0)
		rim.material_override = palette["wood_dark"]
		add_child(rim)
	var hub := MeshInstance3D.new()
	hub.name = "WheelHub"
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = radius * 0.16
	hub_mesh.bottom_radius = radius * 0.16
	hub_mesh.height = width + 0.12
	hub.mesh = hub_mesh
	hub.rotation.z = PI * 0.5
	hub.material_override = palette["bronze"]
	add_child(hub)
	for index in range(paddle_count):
		var angle := index * TAU / paddle_count
		var radial := Vector3(0.0, sin(angle), cos(angle))
		# Spoke.
		var spoke := MeshInstance3D.new()
		spoke.name = "WheelSpoke"
		var spoke_mesh := BoxMesh.new()
		spoke_mesh.size = Vector3(0.05, radius * 0.86, 0.05)
		spoke.mesh = spoke_mesh
		spoke.position = radial * radius * 0.45
		spoke.rotation.x = -angle
		spoke.material_override = palette["wood_dark"]
		add_child(spoke)
		# Bucket paddle with a real collider.
		var paddle_size := Vector3(width, 0.06, radius * 0.30)
		var paddle_at := radial * radius * 0.92
		var paddle := MeshInstance3D.new()
		paddle.name = "WheelPaddle"
		var paddle_mesh := BoxMesh.new()
		paddle_mesh.size = paddle_size
		paddle.mesh = paddle_mesh
		paddle.position = paddle_at
		paddle.rotation.x = -angle
		paddle.material_override = palette["wood"]
		add_child(paddle)
		var collider := CollisionShape3D.new()
		collider.name = "PaddleCollision%02d" % index
		var shape := BoxShape3D.new()
		shape.size = paddle_size
		collider.shape = shape
		collider.position = paddle_at
		collider.rotation.x = -angle
		add_child(collider)


## Registers a gear driven by the wheel axle. `ratio` > 0 turns the same way.
func attach_gear(gear: Node3D, ratio: float, axis: Vector3) -> void:
	_gears.append(gear)
	_gear_ratios.append(ratio)
	_gear_axes.append(axis.normalized())


func physics_step(delta: float, water_flux: float) -> void:
	flux = maxf(water_flux, 0.0)
	var target := 0.0
	if flux >= low_flux:
		target = minf(flux, overload_flux) * rad_per_flux
	# Overload: the brake band slips and clamps speed, protecting the gear train.
	angular_speed = move_toward(angular_speed, target, response * delta * maxf(1.0, absf(target - angular_speed)))
	wheel_angle = fmod(wheel_angle + angular_speed * delta, TAU * 1000.0)
	rotation.x = -fposmod(wheel_angle, TAU)
	for index in range(_gears.size()):
		var gear := _gears[index]
		gear.basis = Basis(_gear_axes[index], fposmod(wheel_angle * _gear_ratios[index], TAU))
	_update_state()


func reset_wheel() -> void:
	flux = 0.0
	angular_speed = 0.0
	wheel_angle = 0.0
	rotation.x = 0.0
	for gear in _gears:
		gear.basis = Basis.IDENTITY
	_update_state()


## 0..1 drive delivered through the gear train; only a working wheel lifts.
func drive_factor() -> float:
	if state != State.WORKING:
		return 0.0
	return clampf(angular_speed / (working_flux * rad_per_flux * 1.6), 0.0, 1.0)


func state_name() -> String:
	match state:
		State.LOW_FLOW:
			return "LOW FLOW"
		State.WORKING:
			return "WORKING"
		State.OVERLOAD:
			return "OVERLOAD"
		_:
			return "NO WATER"


func _update_state() -> void:
	var new_state := State.NO_WATER
	if flux > overload_flux:
		new_state = State.OVERLOAD
	elif flux >= working_flux and angular_speed >= working_flux * rad_per_flux * 0.5:
		new_state = State.WORKING
	elif flux >= low_flux:
		new_state = State.LOW_FLOW
	if new_state != state:
		state = new_state
		state_changed.emit(state)
