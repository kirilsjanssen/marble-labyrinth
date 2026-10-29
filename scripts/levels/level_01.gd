extends RefCounted
## Data-only description of the first labyrinth. New levels can provide the same
## dictionary shape without duplicating input, camera, physics, or presentation.


static func definition() -> Dictionary:
	return {
		"id": "workshop_01",
		"title": "THE BRASS WORKSHOP",
		"start": Vector3(-3.25, 0.62, 3.25),
		"goal": Vector3(3.25, 0.18, -3.20),
		"walls": [
			{"name": "WestWall", "position": Vector3(-4.55, 0.36, 0.0), "size": Vector3(0.28, 0.72, 9.25), "accent": true},
			{"name": "EastWall", "position": Vector3(4.55, 0.36, 0.0), "size": Vector3(0.28, 0.72, 9.25), "accent": true},
			{"name": "NorthWall", "position": Vector3(0.0, 0.36, -4.55), "size": Vector3(9.25, 0.72, 0.28), "accent": true},
			{"name": "SouthWall", "position": Vector3(0.0, 0.36, 4.55), "size": Vector3(9.25, 0.72, 0.28), "accent": true},
			{"name": "CorridorA", "position": Vector3(-1.60, 0.31, 2.40), "size": Vector3(0.30, 0.62, 3.00)},
			{"name": "CorridorB", "position": Vector3(0.80, 0.31, 1.00), "size": Vector3(3.00, 0.62, 0.30)},
			{"name": "CorridorC", "position": Vector3(-1.25, 0.31, -1.60), "size": Vector3(3.00, 0.62, 0.30)},
			{"name": "CorridorD", "position": Vector3(2.40, 0.31, -1.60), "size": Vector3(0.30, 0.62, 2.70)},
			{"name": "CorridorE", "position": Vector3(-3.20, 0.28, -2.75), "size": Vector3(2.10, 0.56, 0.28)},
		],
		"wind": {
			"position": Vector3(-2.50, 0.12, -1.10),
			"direction": Vector3(0.92, 0.08, -0.38),
			"radius": 1.25,
			"force": 7.5,
		},
		"magnet": {
			"position": Vector3(3.00, 0.16, 0.10),
			"radius": 2.35,
			"force": 8.5,
		},
		"trap": {
			"position": Vector3(0.00, 0.18, -3.10),
			"radius": 0.58,
		},
	}
