extends RefCounted
## Vertical Liftworks: one continuous three-tier board. Tier tops sit at
## y = 0.02 / 1.42 / 2.82 in board space; a physical three-stop lift joins them.
## Static decks and walls are built by the shared controller, every moving part
## by LiftworksMechanisms.

const T1 := 0.02
const T2 := 1.42
const T3 := 2.82


static func definition() -> Dictionary:
	return {
		"number": 3,
		"id": "vertical_liftworks_03",
		"title": "VERTICAL LIFTWORKS",
		"style": "clockwork",
		"smart_camera": true,
		"camera_pivot": Vector3(0.0, 1.15, 0.0),
		"camera_distance": 15.4,
		"hint": "Push the cube onto the POWER plate, ride the lift, find the UPPER RELEASE",
		"start": Vector3(-3.60, 0.55, 3.40),
		"goal": Vector3(0.0, T3 + 0.16, -2.60),
		"floor_tiles": _floor_tiles(),
		"walls": _walls(),
		"holes": [
			{"name": "BridgePit", "position": Vector3(1.30, -0.45, 3.485), "size": Vector3(1.00, 0.30, 2.23)},
			{"name": "LiftPit", "position": Vector3(3.55, -0.62, -1.50), "size": Vector3(1.25, 0.24, 1.25), "respawn": Vector3(3.85, T1 + 0.45, 0.60)},
			# The tier-2 transfer gap drops into a sealed machine room; catch the
			# marble mid-air and return it to the tier-2 lift landing instead.
			{"name": "TransferGap", "position": Vector3(-1.60, 0.62, -2.50), "size": Vector3(1.60, 0.90, 3.80), "respawn": Vector3(2.30, T2 + 0.45, -1.50)},
		],
		"lamps": [
			{"position": Vector3(-4.15, T1 + 0.16, 4.15), "color": Color("ffc76b")},
			{"position": Vector3(4.15, T1 + 0.16, 2.10), "color": Color("ffb95a")},
			{"position": Vector3(-4.05, T2 + 0.16, -0.95), "color": Color("ffcb78")},
			{"position": Vector3(2.45, T3 + 0.16, -0.95), "color": Color("ffd38a")},
			{"position": Vector3(-0.45, T3 + 0.16, -4.00), "color": Color("b48cff")},
		],
		"liftworks": {
			"lift": {
				"position": Vector3(3.55, 0.0, -1.50),
				"size": Vector3(1.26, 0.18, 1.26),
				"floors": [T1, T2, T3],
				"exit_sides": ["south", "west", "west"],
				"locked": [false, true, true],
				"speed": 0.85,
				"depart_delay": 0.9,
				"call_pads": [
					Vector3(3.85, T1 + 0.03, -0.42),
					Vector3(2.30, T2 + 0.03, -1.50),
					Vector3(2.30, T3 + 0.03, -1.50),
				],
				"landing_gates": [
					{"position": Vector3(3.55, T1, -0.80), "size": Vector3(1.30, 0.50, 0.10)},
					{"position": Vector3(2.85, T2, -1.50), "size": Vector3(0.10, 0.50, 1.30)},
					{"position": Vector3(2.85, T3, -1.50), "size": Vector3(0.10, 0.50, 1.30)},
				],
			},
			# Tier 1: physical cargo. A wooden PuzzleShapeBody cube (0.45: its diagonal
			# is narrower than the 0.75 lane, so it cannot wedge) must be shoved
			# into the pocket at the end of the west lane to power the lift.
			"power_cube": {"start": Vector3(2.85, T1 + 0.25, 1.45), "size": Vector3(0.45, 0.45, 0.45), "material": &"wood"},
			"power_plate": {"position": Vector3(2.85, T1 + 0.03, 0.16), "radius": 0.40},
			# Tier 2: lever on the open west deck releases the top lift stop.
			"upper_release": {"position": Vector3(-3.55, T2 + 0.09, -3.40), "radius": 0.45},
			"secret_sensor": {"position": Vector3(2.20, T3 + 0.30, -3.30), "size": Vector3(0.90, 0.60, 1.30)},
			"gears": [
				{"name": "StripGear", "position": Vector3(-1.75, T1 + 0.25, 2.80), "radius": 0.40, "teeth": 10, "speed": 1.55},
				{"name": "SecretGearA", "position": Vector3(1.95, T3 + 0.25, -3.30), "radius": 0.46, "teeth": 11, "speed": 1.35},
				{"name": "SecretGearB", "position": Vector3(1.05, T3 + 0.25, -3.85), "radius": 0.36, "teeth": 9, "speed": -1.85},
			],
			"rotors": [
				{"name": "StripSweeper", "position": Vector3(-0.55, T1 + 0.18, 3.40), "arm": 0.80, "height": 0.30, "speed": 1.25},
				{"name": "CorridorPaddleShaft", "position": Vector3(1.55, T2 + 0.20, -1.48), "arm": 0.58, "height": 0.34, "speed": -1.55},
			],
			"shutters": [
				{"name": "ShutterA", "position": Vector3(0.05, T2, -1.48), "size": Vector3(0.14, 0.55, 1.34), "period": 3.8, "phase": 0.0},
				{"name": "ShutterB", "position": Vector3(-0.50, T2, -1.48), "size": Vector3(0.14, 0.55, 1.34), "period": 3.8, "phase": 0.2},
			],
			"lever": {"position": Vector3(-2.30, T1 + 0.09, 3.40), "radius": 0.45},
			"bridge": {
				"pivot": Vector3(0.80, -0.06, 3.39),
				"size": Vector3(1.10, 0.16, 1.10),
				"closed_angle": 1.35,
				"open_angle": 0.0,
				"speed": 1.6,
			},
			"moving_platform": {
				"origin": Vector3(-1.30, T2 - 0.09, -1.48),
				"travel": Vector3(-0.60, 0.0, 0.0),
				"size": Vector3(1.00, 0.18, 1.30),
				"period": 4.6,
			},
			"gate_pad": {"position": Vector3(1.95, T3 + 0.06, -1.30), "radius": 0.42},
			"gate": {
				"position": Vector3(0.80, T3 + 0.36, -1.60),
				"size": Vector3(0.20, 0.72, 1.60),
				"lift_height": 0.90,
				"speed": 2.2,
				"open_seconds": 6.5,
			},
		},
		# Ordered route used by headless reachability checks. Each step is either
		# a free roll on one deck ("roll") or a ride on a named mechanism.
		"route": [
			{"at": Vector3(-3.60, T1, 3.40), "via": "roll"},
			{"at": Vector3(-2.30, T1, 3.40), "via": "roll"},
			{"at": Vector3(0.40, T1, 3.40), "via": "roll"},
			{"at": Vector3(2.20, T1, 3.40), "via": "bridge"},
			{"at": Vector3(3.85, T1, 3.00), "via": "roll"},
			{"at": Vector3(3.85, T1, -0.42), "via": "roll"},
			{"at": Vector3(3.55, T1, -1.50), "via": "roll"},
			{"at": Vector3(3.55, T2, -1.50), "via": "lift"},
			{"at": Vector3(2.30, T2, -1.48), "via": "roll"},
			{"at": Vector3(1.00, T2, -1.25), "via": "roll"},
			{"at": Vector3(-0.70, T2, -1.25), "via": "roll"},
			{"at": Vector3(-2.80, T2, -1.48), "via": "platform"},
			{"at": Vector3(-3.55, T2, -3.40), "via": "roll"},
			{"at": Vector3(-2.80, T2, -1.48), "via": "roll"},
			{"at": Vector3(-0.70, T2, -1.25), "via": "platform"},
			{"at": Vector3(1.00, T2, -1.25), "via": "roll"},
			{"at": Vector3(2.30, T2, -1.48), "via": "roll"},
			{"at": Vector3(3.55, T2, -1.50), "via": "roll"},
			{"at": Vector3(3.55, T3, -1.50), "via": "lift"},
			{"at": Vector3(1.95, T3, -1.30), "via": "roll"},
			{"at": Vector3(0.0, T3, -1.30), "via": "gate"},
			{"at": Vector3(0.0, T3, -2.60), "via": "roll"},
		],
	}


static func _floor_tiles() -> Array:
	var tier2_y := T2 - 0.18
	var tier3_y := T3 - 0.18
	return [
		# Tier 1 leaves a bridge pit and a lift pit open.
		{"name": "T1West", "position": Vector3(-1.90, -0.16, 0.0), "size": Vector3(5.40, 0.36, 9.20)},
		{"name": "T1BridgeSpine", "position": Vector3(1.30, -0.16, -1.115), "size": Vector3(1.00, 0.36, 6.97)},
		{"name": "T1EastColumn", "position": Vector3(3.20, -0.16, 1.875), "size": Vector3(2.80, 0.36, 5.45)},
		{"name": "T1LiftWest", "position": Vector3(2.35, -0.16, -2.725), "size": Vector3(1.10, 0.36, 3.75)},
		{"name": "T1LiftEast", "position": Vector3(4.40, -0.16, -2.725), "size": Vector3(0.40, 0.36, 3.75)},
		{"name": "T1LiftNorth", "position": Vector3(3.55, -0.16, -3.375), "size": Vector3(1.30, 0.36, 2.45)},
		{"name": "T1LiftPitFloor", "position": Vector3(3.55, -0.86, -1.50), "size": Vector3(1.30, 0.12, 1.30)},
		# Tier 2: an occluded east corridor (under tier 3), a transfer gap, an open west deck.
		{"name": "T2East", "position": Vector3(1.05, tier2_y, -2.50), "size": Vector3(3.70, 0.36, 3.80), "elevated": true},
		{"name": "T2West", "position": Vector3(-3.40, tier2_y, -2.50), "size": Vector3(2.00, 0.36, 3.80), "elevated": true},
		# Tier 3: the upper workshop with the timer gate, secret gear run and socket.
		{"name": "T3Deck", "position": Vector3(1.05, tier3_y, -2.50), "size": Vector3(3.70, 0.36, 3.80), "elevated": true},
	]


static func _walls() -> Array:
	var t1_wall := T1 + 0.36
	var t2_wall := T2 + 0.30
	var t3_wall := T3 + 0.30
	var pillar_t2 := (T1 + T2 - 0.36) * 0.5
	var pillar_t3 := (T2 + T3 - 0.36) * 0.5
	return [
		# Tier 1 perimeter and the south strip / east column route.
		{"name": "T1WestOuter", "position": Vector3(-4.55, t1_wall, 0.0), "size": Vector3(0.28, 0.76, 9.25), "accent": true},
		{"name": "T1EastOuter", "position": Vector3(4.55, t1_wall, 0.0), "size": Vector3(0.28, 0.76, 9.25), "accent": true},
		{"name": "T1SouthOuter", "position": Vector3(0.0, t1_wall, 4.55), "size": Vector3(9.25, 0.76, 0.28), "accent": true},
		{"name": "T1NorthOuter", "position": Vector3(0.0, t1_wall, -4.55), "size": Vector3(9.25, 0.76, 0.28), "accent": true},
		{"name": "T1StripNorth", "position": Vector3(-1.025, T1 + 0.31, 2.25), "size": Vector3(6.75, 0.62, 0.24)},
		{"name": "T1ColumnWest", "position": Vector3(2.35, T1 + 0.31, -1.15), "size": Vector3(0.24, 0.62, 6.80)},
		{"name": "T1LaneRail", "position": Vector3(3.30, T1 + 0.25, 0.95), "size": Vector3(0.16, 0.50, 2.00)},
		{"name": "T1PocketStop", "position": Vector3(2.825, T1 + 0.25, -0.20), "size": Vector3(0.95, 0.50, 0.16)},
		{"name": "T1LiftHousingWest", "position": Vector3(2.625, t1_wall, -2.725), "size": Vector3(0.55, 0.76, 3.65)},
		{"name": "T1LiftHousingNorth", "position": Vector3(3.725, t1_wall, -3.375), "size": Vector3(1.65, 0.76, 2.35)},
		{"name": "T1LiftHousingEast", "position": Vector3(4.375, t1_wall, -1.525), "size": Vector3(0.35, 0.76, 1.35)},
		# Pillars that carry tier 2 and tier 3; they stand outside the playable lanes.
		{"name": "T2PillarSW", "position": Vector3(-4.30, pillar_t2, -0.70), "size": Vector3(0.22, 1.04, 0.22), "accent": true},
		{"name": "T2PillarGapW", "position": Vector3(-2.40, pillar_t2, -0.70), "size": Vector3(0.22, 1.04, 0.22), "accent": true},
		{"name": "T2PillarGapE", "position": Vector3(-0.80, pillar_t2, -0.70), "size": Vector3(0.22, 1.04, 0.22), "accent": true},
		{"name": "T2PillarNW", "position": Vector3(-4.30, pillar_t2, -4.30), "size": Vector3(0.22, 1.04, 0.22), "accent": true},
		{"name": "T3PillarSW", "position": Vector3(-0.70, pillar_t3, -0.70), "size": Vector3(0.22, 1.04, 0.22), "accent": true},
		{"name": "T3PillarNW", "position": Vector3(-0.70, pillar_t3, -4.30), "size": Vector3(0.22, 1.04, 0.22), "accent": true},
		{"name": "T3PillarSE", "position": Vector3(2.80, pillar_t3, -0.70), "size": Vector3(0.22, 1.04, 0.22), "accent": true},
		{"name": "T3PillarNE", "position": Vector3(2.80, pillar_t3, -4.30), "size": Vector3(0.22, 1.04, 0.22), "accent": true},
		# Tier 2 guards, the narrow corridor and its choke stub.
		{"name": "T2SouthRail", "position": Vector3(-0.75, t2_wall, -0.70), "size": Vector3(7.30, 0.60, 0.20), "accent": true},
		{"name": "T2NorthWall", "position": Vector3(-0.75, t2_wall, -4.30), "size": Vector3(7.30, 0.60, 0.20)},
		{"name": "T2WestWall", "position": Vector3(-4.30, t2_wall, -2.50), "size": Vector3(0.20, 0.60, 3.80)},
		{"name": "T2EastNorth", "position": Vector3(2.80, t2_wall, -3.275), "size": Vector3(0.20, 0.60, 2.25)},
		{"name": "T2CorridorNorth", "position": Vector3(1.05, t2_wall, -2.25), "size": Vector3(3.70, 0.60, 0.20)},
		{"name": "T2ChokeStub", "position": Vector3(0.65, t2_wall, -1.90), "size": Vector3(0.20, 0.60, 0.50)},
		# Tier 3 perimeter, main corridor divider and the goal partition.
		{"name": "T3SouthRail", "position": Vector3(1.05, t3_wall, -0.70), "size": Vector3(3.70, 0.60, 0.20), "accent": true},
		# Fascia beam under the tier-3 edge closes the sight slot above the
		# tier-2 rail, so the corridor below is either clearly visible or hidden.
		{"name": "T3SouthFascia", "position": Vector3(1.05, T3 - 0.48, -0.66), "size": Vector3(3.70, 0.24, 0.12), "plain": true},
		{"name": "T3NorthWall", "position": Vector3(1.05, t3_wall, -4.30), "size": Vector3(3.70, 0.60, 0.20), "accent": true},
		{"name": "T3WestWall", "position": Vector3(-0.70, t3_wall, -2.50), "size": Vector3(0.20, 0.60, 3.80), "accent": true},
		{"name": "T3EastNorth", "position": Vector3(2.80, t3_wall, -3.275), "size": Vector3(0.20, 0.60, 2.25), "accent": true},
		{"name": "T3Divider", "position": Vector3(1.325, t3_wall, -2.40), "size": Vector3(1.05, 0.60, 0.20)},
		{"name": "T3GoalPartition", "position": Vector3(0.80, t3_wall, -2.85), "size": Vector3(0.20, 0.60, 0.90)},
	]
