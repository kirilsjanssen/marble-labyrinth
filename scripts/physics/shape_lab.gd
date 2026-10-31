extends Node3D
class_name PuzzleShapeLab
## Sandbox for future non-ball puzzle weights and obstacles: cube, pyramid, ball.

var cube: PuzzleShapeBody
var pyramid: PuzzleShapeBody
var marble: PhysicsBall


func _ready() -> void:
	var floor := StaticBody3D.new()
	floor.name = "TestFloor"
	floor.position.y = -0.2
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(8.0, 0.4, 6.0)
	floor_collision.shape = floor_shape
	floor.add_child(floor_collision)
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = floor_shape.size
	floor_mesh.mesh = floor_box
	floor.add_child(floor_mesh)
	add_child(floor)

	cube = PuzzleShapeBody.new()
	cube.name = "MagneticSteelCube"
	cube.body_shape = PuzzleShapeBody.BodyShape.CUBE
	cube.material_id = &"magnetic_steel"
	cube.position = Vector3(-2.0, 3.0, 0.0)
	add_child(cube)

	pyramid = PuzzleShapeBody.new()
	pyramid.name = "WoodenPyramid"
	pyramid.body_shape = PuzzleShapeBody.BodyShape.PYRAMID
	pyramid.material_id = &"wood"
	pyramid.position = Vector3(1.8, 3.0, 0.0)
	add_child(pyramid)

	marble = PhysicsBall.new()
	marble.name = "StoneSphere"
	marble.material_id = &"stone"
	marble.position = Vector3(0.0, 3.0, 0.0)
	add_child(marble)
	var visible_marble := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = marble.radius
	mesh.height = marble.radius * 2.0
	visible_marble.mesh = mesh
	marble.add_child(visible_marble)

	var camera := Camera3D.new()
	camera.name = "ShapeLabCamera"
	camera.position = Vector3(8.0, 7.0, 10.0)
	camera.look_at_from_position(camera.position, Vector3.ZERO)
	camera.current = true
	add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60.0, 20.0, 0.0)
	add_child(light)
