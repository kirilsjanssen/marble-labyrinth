extends RefCounted
## Orbital Mechanism v2 test integration. Blender coordinates are metres with
## Z up; Godot imports glTF as X right, Y up, -Z forward.


static func P(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


static func definition() -> Dictionary:
	return {
		"number": 6,
		"id": "orbital_mechanism_06_test",
		"title": "ORBITAL MECHANISM",
		"style": "orbital",
		"scene": "level06",
		"smart_camera": true,
		"alpine_environment": false,
		"camera_pivot": Vector3(0.0, 7.0, 0.0),
		"camera_distance": 50.0,
		"camera_yaw_deg": -42.0,
		"respawn_radius": 42.0,
		"hint": "TEST LEVEL — follow the blue route, ride both magnetic lifts and reach the golden receiver",
		"start": P(-17.0, -14.0, 4.38),
		"goal": P(17.0, 12.0, 12.0),
		"goal_model": true,
		"walls": [],
		"holes": [],
		"level06": {
			"lifts": [
				{"name": "L01", "position": P(-16.0, -8.0, 0.0), "lower": 4.0, "upper": 9.0, "speed": 2.0},
				{"name": "L02", "position": P(13.0, 4.0, 0.0), "lower": 9.0, "upper": 12.0, "speed": 1.7},
			],
		},
		"route": _route(),
	}


static func _route() -> Array:
	return [
		{"at": P(-17.0, -14.0, 4.35), "via": "start"},
		{"at": P(-12.0, -14.0, 4.35), "via": "bridge"},
		{"at": P(-12.0, -8.0, 4.35), "via": "bridge"},
		{"at": P(-16.0, -8.0, 4.35), "via": "bridge"},
		{"at": P(-16.0, -8.0, 9.35), "via": "lift", "lift": "L01"},
		{"at": P(-16.0, -1.0, 9.35), "via": "tube"},
		{"at": P(-15.3, 3.3, 9.35), "via": "tube"},
		{"at": P(-11.0, 4.0, 9.35), "via": "tube"},
		{"at": P(4.0, 4.0, 9.35), "via": "tube"},
		{"at": P(13.0, 4.0, 9.35), "via": "bridge"},
		{"at": P(13.0, 4.0, 12.35), "via": "lift", "lift": "L02"},
		{"at": P(13.0, 12.0, 12.35), "via": "tube"},
		{"at": P(17.0, 12.0, 12.35), "via": "goal"},
	]
