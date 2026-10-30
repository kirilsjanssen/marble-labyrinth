extends RefCounted
## Clockwork Factory layout. Static geometry and mechanism parameters live here;
## the shared controller and ClockworkMechanisms component provide behavior.


static func definition() -> Dictionary:
	return {
		"number": 2,
		"id": "clockwork_factory_02",
		"title": "THE CLOCKWORK FACTORY",
		"style": "clockwork",
		"start": Vector3(-3.42, 0.62, 3.78),
		"goal": Vector3(3.62, 1.18, -3.22),
		"floor_tiles": [
			{"name": "StartDeck", "position": Vector3(-3.42, -0.16, 0.00), "size": Vector3(2.05, 0.36, 8.55)},
			{"name": "BridgeIsland", "position": Vector3(-0.45, -0.16, 0.42), "size": Vector3(2.05, 0.36, 1.45)},
			{"name": "UpperFactoryDeck", "position": Vector3(2.50, 0.84, -3.18), "size": Vector3(3.60, 0.36, 2.35), "elevated": true},
		],
		"walls": [
			{"name": "WestOuter", "position": Vector3(-4.55, 0.38, 0.0), "size": Vector3(0.28, 0.76, 9.25), "accent": true},
			{"name": "WestDeckSouth", "position": Vector3(-3.42, 0.35, 4.42), "size": Vector3(2.18, 0.70, 0.28), "accent": true},
			{"name": "WestDeckNorth", "position": Vector3(-3.42, 0.35, -4.42), "size": Vector3(2.18, 0.70, 0.28), "accent": true},
			{"name": "WestDeckEastSouth", "position": Vector3(-2.31, 0.31, 2.62), "size": Vector3(0.26, 0.62, 3.38)},
			{"name": "WestDeckEastNorth", "position": Vector3(-2.31, 0.31, -2.22), "size": Vector3(0.26, 0.62, 3.45)},
			{"name": "GearGuideA", "position": Vector3(-3.95, 0.27, 2.55), "size": Vector3(0.65, 0.54, 0.22)},
			{"name": "GearGuideB", "position": Vector3(-2.88, 0.27, 1.55), "size": Vector3(0.72, 0.54, 0.22)},
			{"name": "IslandNorth", "position": Vector3(-0.45, 0.29, -0.31), "size": Vector3(2.10, 0.58, 0.24)},
			{"name": "IslandSouth", "position": Vector3(-0.45, 0.29, 1.15), "size": Vector3(2.10, 0.58, 0.24)},
			{"name": "UpperNorth", "position": Vector3(2.50, 1.35, -4.43), "size": Vector3(3.75, 0.70, 0.26), "accent": true},
			{"name": "UpperSouth", "position": Vector3(2.50, 1.35, -1.94), "size": Vector3(3.75, 0.70, 0.26), "accent": true},
			{"name": "UpperEast", "position": Vector3(4.43, 1.35, -3.18), "size": Vector3(0.26, 0.70, 2.75), "accent": true},
			{"name": "UpperWestNorth", "position": Vector3(0.64, 1.30, -3.92), "size": Vector3(0.24, 0.60, 0.95)},
			{"name": "UpperWestSouth", "position": Vector3(0.64, 1.30, -2.40), "size": Vector3(0.24, 0.60, 0.70)},
		],
		"holes": [
			{"name": "BridgePit", "position": Vector3(-1.47, -0.40, 0.42), "size": Vector3(1.95, 0.30, 1.30)},
			{"name": "TransferPit", "position": Vector3(0.15, -0.40, -1.35), "size": Vector3(1.55, 0.30, 2.35)},
			{"name": "FactoryVoid", "position": Vector3(2.25, -0.40, 0.15), "size": Vector3(3.80, 0.30, 2.80)},
		],
		"lamps": [
			{"position": Vector3(-4.18, 0.18, 3.62), "color": Color("ffc76b")},
			{"position": Vector3(-4.18, 0.18, -3.55), "color": Color("ffb95a")},
			{"position": Vector3(4.02, 1.18, -2.24), "color": Color("ffcb78")},
		],
		"shafts": [
			{"position": Vector3(-3.43, 0.17, -0.88), "length": 1.55, "speed": 1.8},
			{"position": Vector3(3.30, 1.18, -4.08), "length": 1.35, "speed": -1.5},
		],
		"mechanics": {
			"gears": [
				{"name": "EntryGearA", "position": Vector3(-3.70, 0.27, 2.80), "radius": 0.50, "teeth": 12, "speed": 1.65},
				{"name": "EntryGearB", "position": Vector3(-3.10, 0.27, 1.62), "radius": 0.48, "teeth": 11, "speed": -2.05},
				{"name": "UpperTimingGear", "position": Vector3(3.05, 1.27, -2.55), "radius": 0.47, "teeth": 10, "speed": 1.45},
			],
			"lever": {"position": Vector3(-3.42, 0.11, 0.42), "radius": 0.50},
			"bridge": {
				"pivot": Vector3(-2.28, 0.03, 0.42),
				"size": Vector3(1.65, 0.16, 0.86),
				"closed_angle": -1.5708,
				"open_angle": 0.0,
				"speed": 1.65,
			},
			"moving_platform": {
				"origin": Vector3(0.18, 0.02, -0.54),
				"travel": Vector3(0.0, 0.0, -1.48),
				"size": Vector3(1.12, 0.18, 1.02),
				"period": 4.2,
			},
			"elevator": {
				"position": Vector3(0.18, 0.02, -2.62),
				"size": Vector3(1.10, 0.18, 1.05),
				"travel_height": 1.0,
				"speed": 0.72,
			},
			"gate_pad": {"position": Vector3(1.28, 1.08, -3.18), "radius": 0.48},
			"gate": {
				"position": Vector3(2.18, 1.68, -3.18),
				"size": Vector3(0.24, 1.34, 2.00),
				"lift_height": 1.55,
				"speed": 2.4,
				"open_seconds": 6.5,
			},
		},
	}
