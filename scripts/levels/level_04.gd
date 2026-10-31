extends RefCounted
## Alpine Watermill: one continuous three-tier board (deck tops 0.02 / 1.42 /
## 2.82). The mountain stream tier, the wheel-driven mill lift, the float
## pontoon and the millhouse terrace are linked by one hydraulic network:
## sluice lever -> wheel turns -> gear train winds the lift; diverter lever ->
## float tank fills -> pontoon carries the marble to the top tier.

const T1 := 0.02
const T2 := 1.42
const T3 := 2.82
const STRIP_Z := 3.49
const DRIVE_Y := 2.22


static func definition() -> Dictionary:
	return {
		"number": 4,
		"id": "alpine_watermill_04",
		"title": "ALPINE WATERMILL",
		"style": "alpine",
		"smart_camera": true,
		"alpine_environment": true,
		"camera_pivot": Vector3(0.4, 1.15, 0.0),
		"camera_distance": 15.8,
		"hint": "Pull the SLUICE lever to drive the wheel, push the cube on the plate, ride the mill lift",
		"start": Vector3(-3.60, 0.55, STRIP_Z),
		"goal": Vector3(2.35, T3 + 0.16, -1.60),
		"floor_tiles": _floor_tiles(),
		"walls": _walls(),
		"holes": [
			{"name": "MillChannel", "position": Vector3(1.30, -0.48, STRIP_Z), "size": Vector3(1.00, 0.10, 1.84), "respawn": Vector3(0.10, T1 + 0.45, STRIP_Z)},
			{"name": "LiftPit", "position": Vector3(3.55, -0.62, -1.50), "size": Vector3(1.25, 0.24, 1.25), "respawn": Vector3(3.85, T1 + 0.45, 0.70)},
			{"name": "TankGap", "position": Vector3(-1.60, 0.62, -3.35), "size": Vector3(1.60, 0.90, 2.10), "respawn": Vector3(2.30, T2 + 0.45, -1.50)},
			{"name": "TankFloor", "position": Vector3(-1.60, 0.40, -1.475), "size": Vector3(1.60, 0.30, 1.40), "respawn": Vector3(2.30, T2 + 0.45, -1.50)},
		],
		"lamps": [
			{"position": Vector3(-4.15, T1 + 0.16, 4.15), "color": Color("ffcf8a")},
			{"position": Vector3(4.15, T1 + 0.16, 2.30), "color": Color("ffc070")},
			{"position": Vector3(-4.05, T2 + 0.16, -0.95), "color": Color("ffd59a")},
			{"position": Vector3(2.55, T3 + 0.16, -0.95), "color": Color("ffc87a")},
		],
		"watermill": _watermill(),
		"route": _route(),
	}


static func _floor_tiles() -> Array:
	var tier2_y := T2 - 0.18
	var tier3_y := T3 - 0.18
	return [
		{"name": "T1West", "position": Vector3(-1.90, -0.16, 0.0), "size": Vector3(5.40, 0.36, 9.20), "material": "wet_stone"},
		{"name": "T1ChannelSpine", "position": Vector3(1.30, -0.16, -1.015), "size": Vector3(1.00, 0.36, 7.17), "material": "wet_stone"},
		{"name": "T1ChannelBed", "position": Vector3(1.30, -0.64, STRIP_Z), "size": Vector3(1.00, 0.18, 1.84), "material": "granite"},
		{"name": "T1WoodBridge", "position": Vector3(1.30, -0.06, STRIP_Z), "size": Vector3(1.00, 0.16, 1.10), "material": "wood"},
		{"name": "T1EastColumn", "position": Vector3(3.20, -0.16, 1.875), "size": Vector3(2.80, 0.36, 5.45), "material": "wet_stone"},
		{"name": "T1LiftWest", "position": Vector3(2.35, -0.16, -2.725), "size": Vector3(1.10, 0.36, 3.75), "material": "wet_stone"},
		{"name": "T1LiftEast", "position": Vector3(4.40, -0.16, -2.725), "size": Vector3(0.40, 0.36, 3.75), "material": "wet_stone"},
		{"name": "T1LiftNorth", "position": Vector3(3.55, -0.16, -3.375), "size": Vector3(1.30, 0.36, 2.45), "material": "wet_stone"},
		{"name": "T1LiftPitFloor", "position": Vector3(3.55, -0.86, -1.50), "size": Vector3(1.30, 0.12, 1.30), "material": "granite"},
		{"name": "T2East", "position": Vector3(1.05, tier2_y, -2.50), "size": Vector3(3.70, 0.36, 3.80), "elevated": true, "material": "wood"},
		{"name": "T2West", "position": Vector3(-3.40, tier2_y, -2.50), "size": Vector3(2.00, 0.36, 3.80), "elevated": true, "material": "wood"},
		{"name": "T3Deck", "position": Vector3(1.05, tier3_y, -2.50), "size": Vector3(3.70, 0.36, 3.80), "elevated": true, "material": "wood"},
	]


static func _walls() -> Array:
	var t1_wall := T1 + 0.36
	var t2_wall := T2 + 0.30
	var t3_wall := T3 + 0.30
	var pillar_t2 := (T1 + T2 - 0.36) * 0.5
	var pillar_t3 := (T2 + T3 - 0.36) * 0.5
	var tank_wall_y := (T2 - 0.36 + T3 + 0.30) * 0.5
	var tank_wall_h := (T3 + 0.30) - (T2 - 0.36)
	return [
		{"name": "T1WestOuter", "position": Vector3(-4.55, t1_wall, 0.0), "size": Vector3(0.28, 0.76, 9.25), "accent": true, "material": "granite"},
		{"name": "T1EastOuter", "position": Vector3(4.55, t1_wall, 0.0), "size": Vector3(0.28, 0.76, 9.25), "accent": true, "material": "granite"},
		{"name": "T1SouthOuter", "position": Vector3(0.0, t1_wall, 4.55), "size": Vector3(9.25, 0.76, 0.28), "accent": true, "material": "granite"},
		{"name": "T1NorthOuter", "position": Vector3(0.0, t1_wall, -4.55), "size": Vector3(9.25, 0.76, 0.28), "accent": true, "material": "granite"},
		# The strip's north wall has a low secret opening into the millrace walkway.
		{"name": "T1StripNorthWest", "position": Vector3(-4.155, T1 + 0.31, 2.45), "size": Vector3(0.51, 0.62, 0.24), "material": "granite"},
		{"name": "T1StripNorth", "position": Vector3(-0.325, T1 + 0.31, 2.45), "size": Vector3(5.35, 0.62, 0.24), "material": "granite"},
		{"name": "T1StreamBank", "position": Vector3(-1.09, T1 + 0.20, 1.00), "size": Vector3(6.64, 0.40, 0.20), "material": "granite"},
		{"name": "T1ColumnWest", "position": Vector3(2.35, T1 + 0.31, -1.575), "size": Vector3(0.24, 0.62, 5.95), "material": "granite"},
		{"name": "T1LaneRail", "position": Vector3(3.30, T1 + 0.25, 0.95), "size": Vector3(0.16, 0.50, 2.00), "material": "wood_dark"},
		{"name": "T1PocketStop", "position": Vector3(2.825, T1 + 0.25, -0.20), "size": Vector3(0.95, 0.50, 0.16), "material": "wood_dark"},
		{"name": "T1LiftHousingWest", "position": Vector3(2.625, t1_wall, -2.725), "size": Vector3(0.55, 0.76, 3.65), "material": "granite"},
		{"name": "T1LiftHousingNorth", "position": Vector3(3.725, t1_wall, -3.375), "size": Vector3(1.65, 0.76, 2.35), "material": "granite"},
		{"name": "T1LiftHousingEast", "position": Vector3(4.375, t1_wall, -1.525), "size": Vector3(0.35, 0.76, 1.35), "material": "granite"},
		{"name": "T2PillarSW", "position": Vector3(-4.30, pillar_t2, -0.70), "size": Vector3(0.22, 1.04, 0.22), "accent": true, "material": "wood_dark"},
		{"name": "T2PillarGapW", "position": Vector3(-2.40, pillar_t2, -0.70), "size": Vector3(0.22, 1.04, 0.22), "accent": true, "material": "wood_dark"},
		{"name": "T2PillarGapE", "position": Vector3(-0.80, pillar_t2, -0.70), "size": Vector3(0.22, 1.04, 0.22), "accent": true, "material": "wood_dark"},
		{"name": "T2PillarNW", "position": Vector3(-4.30, pillar_t2, -4.30), "size": Vector3(0.22, 1.04, 0.22), "accent": true, "material": "wood_dark"},
		{"name": "T3PillarNW", "position": Vector3(-0.70, pillar_t3, -4.30), "size": Vector3(0.22, 1.04, 0.22), "accent": true, "material": "wood_dark"},
		{"name": "T3PillarSE", "position": Vector3(2.80, pillar_t3, -0.70), "size": Vector3(0.22, 1.04, 0.22), "accent": true, "material": "wood_dark"},
		{"name": "T3PillarNE", "position": Vector3(2.80, pillar_t3, -4.30), "size": Vector3(0.22, 1.04, 0.22), "accent": true, "material": "wood_dark"},
		{"name": "T2SouthRailWest", "position": Vector3(-3.40, t2_wall, -0.70), "size": Vector3(2.00, 0.60, 0.20), "accent": true, "material": "wood"},
		{"name": "T2SouthRailEast", "position": Vector3(1.05, t2_wall, -0.70), "size": Vector3(3.70, 0.60, 0.20), "accent": true, "material": "wood"},
		{"name": "T2NorthWall", "position": Vector3(-0.75, t2_wall, -4.30), "size": Vector3(7.30, 0.60, 0.20), "material": "wood"},
		{"name": "T2WestWall", "position": Vector3(-4.30, t2_wall, -2.50), "size": Vector3(0.20, 0.60, 3.80), "material": "wood"},
		{"name": "T2EastNorth", "position": Vector3(2.80, t2_wall, -3.275), "size": Vector3(0.20, 0.60, 2.25), "material": "wood"},
		{"name": "T2CorridorNorth", "position": Vector3(1.05, t2_wall, -2.25), "size": Vector3(3.70, 0.60, 0.20), "material": "wood"},
		{"name": "T2ChokeStub", "position": Vector3(0.65, t2_wall, -1.90), "size": Vector3(0.20, 0.60, 0.50), "material": "wood"},
		# Float tank staves: tall north/south walls hold the pontoon shaft.
		{"name": "TankNorthStaves", "position": Vector3(-1.60, tank_wall_y, -2.25), "size": Vector3(1.60, tank_wall_h, 0.20), "material": "wood_dark"},
		{"name": "TankSouthStaves", "position": Vector3(-1.60, tank_wall_y, -0.70), "size": Vector3(1.60, tank_wall_h, 0.20), "material": "wood_dark"},
		{"name": "T3SouthRail", "position": Vector3(1.05, t3_wall, -0.70), "size": Vector3(3.70, 0.60, 0.20), "accent": true, "material": "wood"},
		# Fascia beam under the terrace edge closes the sight slot above the
		# tier-2 rail, so the corridor below is either clearly visible or hidden.
		{"name": "T3SouthFascia", "position": Vector3(1.05, T3 - 0.48, -0.66), "size": Vector3(3.70, 0.24, 0.12), "material": "wood_dark", "plain": true},
		{"name": "T3NorthWall", "position": Vector3(1.05, t3_wall, -4.30), "size": Vector3(3.70, 0.60, 0.20), "accent": true, "material": "granite"},
		{"name": "T3EastWall", "position": Vector3(2.80, t3_wall, -2.50), "size": Vector3(0.20, 0.60, 3.80), "accent": true, "material": "granite"},
		{"name": "T3WestNorth", "position": Vector3(-0.70, t3_wall, -3.275), "size": Vector3(0.20, 0.60, 2.25), "accent": true, "material": "granite"},
		{"name": "T3Divider", "position": Vector3(1.10, t3_wall, -2.40), "size": Vector3(1.60, 0.60, 0.20), "material": "wood"},
		# The millhouse and its cistern are solid blocks on the terrace.
		{"name": "Millhouse", "position": Vector3(0.90, T3 + 0.45, -3.85), "size": Vector3(1.00, 0.90, 0.70), "material": "wood", "plain": true},
		{"name": "MillCistern", "position": Vector3(2.35, T3 + 0.39, -3.80), "size": Vector3(0.70, 0.78, 0.80), "material": "wood_dark", "plain": true},
	]


static func _watermill() -> Dictionary:
	return {
		"water": {
			"pump_flow": 1.1,
			"reservoirs": [
				{"id": "cistern", "capacity": 8.0, "volume": 6.0, "area": 4.0, "base": 3.0},
				{"id": "race", "capacity": 0.8, "volume": 0.0, "area": 0.6, "base": 2.9},
				{"id": "stream", "capacity": 12.0, "volume": 4.0, "area": 6.0, "base": 0.0},
				{"id": "tank", "capacity": 3.0, "volume": 0.6, "area": 2.0, "base": 1.1},
			],
			"connections": [
				{"id": "sluice", "from": "cistern", "to": "race", "conductance": 1.2, "max_flow": 1.6, "valve": "sluice"},
				{"id": "wheel", "from": "race", "to": "stream", "conductance": 3.0, "max_flow": 2.0},
				{"id": "divert", "from": "cistern", "to": "tank", "conductance": 0.8, "max_flow": 0.9, "valve": "divert"},
				{"id": "drain", "from": "tank", "to": "stream", "conductance": 0.5, "max_flow": 0.6, "valve": "drain"},
				{"id": "ram", "from": "stream", "to": "cistern", "conductance": 0.0, "max_flow": 1.2, "pump": true},
			],
		},
		"lift": {
			"position": Vector3(3.55, 0.0, -1.50),
			"size": Vector3(1.26, 0.18, 1.26),
			"floors": [T1, T2],
			"exit_sides": ["south", "west"],
			"locked": [false, false],
			"speed": 0.8,
			"depart_delay": 0.9,
			"call_pads": [Vector3(3.85, T1 + 0.03, -0.42), Vector3(2.30, T2 + 0.03, -1.50)],
			"landing_gates": [
				{"position": Vector3(3.55, T1, -0.80), "size": Vector3(1.30, 0.50, 0.10)},
				{"position": Vector3(2.85, T2, -1.50), "size": Vector3(0.10, 0.50, 1.30)},
			],
		},
		"wheel": {"position": Vector3(4.98, DRIVE_Y, 0.90), "radius": 0.90, "width": 0.42},
		"transmission": {
			"shafts": [
				{"from": Vector3(4.78, DRIVE_Y, 0.90), "to": Vector3(4.60, DRIVE_Y, 0.90), "radius": 0.07},
				{"from": Vector3(4.60, DRIVE_Y, 0.90), "to": Vector3(4.60, DRIVE_Y, -1.50), "radius": 0.06},
				{"from": Vector3(4.60, DRIVE_Y, -1.50), "to": Vector3(3.75, DRIVE_Y, -1.50), "radius": 0.06},
			],
			"gears": [
				{"name": "WheelBevel", "position": Vector3(4.62, DRIVE_Y, 0.90), "axis": Vector3(1.0, 0.0, 0.0), "radius": 0.26, "teeth": 14, "ratio": 1.0},
				{"name": "LineBevel", "position": Vector3(4.60, DRIVE_Y, 0.66), "axis": Vector3(0.0, 0.0, 1.0), "radius": 0.24, "teeth": 13, "ratio": -1.08},
				{"name": "CornerBevel", "position": Vector3(4.60, DRIVE_Y, -1.26), "axis": Vector3(0.0, 0.0, 1.0), "radius": 0.22, "teeth": 12, "ratio": -1.08},
				{"name": "WinchPinion", "position": Vector3(4.36, DRIVE_Y, -1.50), "axis": Vector3(1.0, 0.0, 0.0), "radius": 0.22, "teeth": 12, "ratio": 1.18},
			],
		},
		"pontoon": {"position": Vector3(-1.60, 0.0, -1.475), "size": Vector3(1.56, 0.20, 1.30), "low_top": T2, "high_top": T3, "fill_low": 0.30, "fill_high": 0.95},
		"mill_gate": {"position": Vector3(3.86, T1, -0.20), "size": Vector3(1.04, 0.50, 0.14)},
		"power_cube": {"start": Vector3(2.85, T1 + 0.25, 1.45), "size": Vector3(0.45, 0.45, 0.45), "material": &"wood"},
		"power_plate": {"position": Vector3(2.85, T1 + 0.03, 0.16), "radius": 0.40},
		"sluice_lever": {"position": Vector3(-2.30, T1 + 0.09, STRIP_Z), "radius": 0.45},
		"divert_lever": {"position": Vector3(-3.55, T2 + 0.09, -3.40), "radius": 0.45},
		"gears": [
			{"name": "TerraceGear", "position": Vector3(1.70, T3 + 0.25, -3.90), "radius": 0.28, "teeth": 9, "speed": 1.6},
		],
		"rotors": [
			# Each rotor sweeps one side of its lane: hug the far side to pass.
			{"name": "StreamPaddle", "position": Vector3(-0.55, T1 + 0.18, 2.95), "arm": 0.50, "height": 0.30, "speed": 1.15},
			{"name": "CorridorCamshaft", "position": Vector3(1.55, T2 + 0.20, -1.92), "arm": 0.40, "height": 0.34, "speed": -1.45},
			{"name": "TerraceSweeper", "position": Vector3(0.15, T3 + 0.18, -1.90), "arm": 0.45, "height": 0.30, "speed": 1.25},
			{"name": "SecretSweeper", "position": Vector3(0.90, T3 + 0.18, -2.95), "arm": 0.40, "height": 0.28, "speed": -1.7},
		],
		"shutters": [
			{"name": "SluiceBoardA", "position": Vector3(0.05, T2, -1.48), "size": Vector3(0.14, 0.55, 1.34), "period": 3.8, "phase": 0.0},
			{"name": "SluiceBoardB", "position": Vector3(-0.50, T2, -1.48), "size": Vector3(0.14, 0.55, 1.34), "period": 3.8, "phase": 0.2},
		],
		"gate_pad": {"position": Vector3(0.90, T3 + 0.06, -1.15), "radius": 0.40},
		"gate": {"position": Vector3(1.90, T3 + 0.36, -1.60), "size": Vector3(0.20, 0.72, 1.60), "lift_height": 0.90, "speed": 2.2, "open_seconds": 7.0},
		"secrets": [
			{"id": "millrace", "position": Vector3(-1.0, T1 + 0.3, 1.70), "size": Vector3(2.0, 0.6, 1.0), "message": "SECRET MILLRACE PASSAGE — skips the channel bridge"},
			{"id": "terrace", "position": Vector3(1.70, T3 + 0.3, -3.00), "size": Vector3(0.8, 0.6, 0.8), "message": "SECRET TERRACE RUN — slip past the sweeper to skip the gate"},
		],
		# Bodies inside these boxes feel buoyancy, drag and the simulated current.
		"channels": [
			{"position": Vector3(1.30, -0.275, STRIP_Z), "size": Vector3(1.00, 0.55, 1.84), "reservoir": "stream", "fill_gain": 2.0, "flux": "ram", "flow": Vector3(0.0, 0.0, 1.0), "flux_to_speed": 0.7},
		],
		"water_surfaces": [
			{"name": "ChannelWater", "position": Vector3(1.30, -0.2, STRIP_Z), "size": Vector2(1.00, 1.84), "direction": Vector2(0.0, 1.0), "flux": "ram", "channel": 0, "foam": 0.45},
			{"name": "MillStream", "position": Vector3(-1.10, T1 + 0.03, 0.22), "size": Vector2(6.60, 1.40), "direction": Vector2(1.0, 0.0), "flux": "ram", "foam": 0.30},
			{"name": "StreamCascade", "position": Vector3(-4.30, 0.66, -0.52), "size": Vector2(0.60, 1.25), "flux": "ram", "waterfall": true},
			{"name": "AqueductNorth", "position": Vector3(3.80, 3.37, -3.80), "size": Vector2(2.30, 0.30), "direction": Vector2(1.0, 0.0), "flux": "sluice"},
			{"name": "AqueductEast", "position": Vector3(4.98, 3.32, -1.45), "size": Vector2(0.30, 4.70), "direction": Vector2(0.0, 1.0), "flux": "sluice"},
			{"name": "WheelFeed", "position": Vector3(4.98, 3.05, 0.45), "size": Vector2(0.34, 0.50), "rotation": Vector3(0.0, PI * 0.5, 0.0), "flux": "sluice", "waterfall": true},
			{"name": "WheelTailrace", "position": Vector3(5.42, 0.15, 0.90), "size": Vector2(0.42, 2.40), "rotation": Vector3(0.0, PI * 0.5, 0.0), "flux": "wheel", "waterfall": true},
			{"name": "LowerPool", "position": Vector3(5.45, -0.95, 0.90), "size": Vector2(1.60, 2.80), "direction": Vector2(0.0, 1.0), "flux": "wheel", "level_of": "stream", "level_range": Vector2(-1.15, -0.75), "wave": 0.015},
			{"name": "CisternPond", "position": Vector3(2.35, 3.40, -3.80), "size": Vector2(0.56, 0.66), "direction": Vector2(1.0, 0.0), "flux": "sluice", "level_of": "cistern", "level_range": Vector2(2.95, 3.58), "wave": 0.01},
			{"name": "DivertFlume", "position": Vector3(0.20, 3.45, -4.48), "size": Vector2(3.70, 0.28), "direction": Vector2(-1.0, 0.0), "flux": "divert"},
			{"name": "DivertDrop", "position": Vector3(-1.60, 3.40, -3.39), "size": Vector2(0.28, 2.18), "direction": Vector2(0.0, 1.0), "flux": "divert"},
			{"name": "TankFall", "position": Vector3(-1.60, 2.75, -2.10), "size": Vector2(0.30, 1.30), "flux": "divert", "waterfall": true},
			{"name": "TankWater", "position": Vector3(-1.60, 0.9, -1.475), "size": Vector2(1.56, 1.30), "direction": Vector2(1.0, 0.0), "flux": "divert", "level_of": "tank", "level_range": Vector2(0.60, 2.55)},
		],
		"structures": [
			{"name": "AqueductNorthTrough", "position": Vector3(3.80, 3.30, -3.80), "size": Vector3(2.40, 0.12, 0.42), "material": "wood"},
			{"name": "AqueductEastTrough", "position": Vector3(4.98, 3.25, -1.45), "size": Vector3(0.42, 0.12, 4.80), "material": "wood"},
			{"name": "AqueductPostA", "position": Vector3(4.98, 1.25, -3.40), "size": Vector3(0.12, 4.00, 0.12), "material": "wood_dark"},
			{"name": "AqueductPostB", "position": Vector3(4.98, 1.25, -1.20), "size": Vector3(0.12, 4.00, 0.12), "material": "wood_dark"},
			{"name": "WheelAxleTrestle", "position": Vector3(5.22, 0.55, 0.90), "size": Vector3(0.12, 3.30, 0.16), "material": "wood_dark"},
			{"name": "DivertFlumeTrough", "position": Vector3(0.20, 3.38, -4.48), "size": Vector3(3.80, 0.12, 0.40), "material": "wood"},
			{"name": "DivertDropTrough", "position": Vector3(-1.60, 3.33, -3.39), "size": Vector3(0.40, 0.12, 2.20), "material": "wood"},
			{"name": "LowerPoolBasin", "position": Vector3(5.45, -1.20, 0.90), "size": Vector3(1.80, 0.20, 3.00), "material": "granite"},
			{"name": "RamPumpPipe", "position": Vector3(5.30, 1.00, -3.95), "size": Vector3(0.10, 4.40, 0.10), "material": "bronze"},
			{"name": "MillhouseRoofLine", "position": Vector3(0.90, T3 + 0.45, -3.85), "size": Vector3(1.00, 0.90, 0.70), "roof": true, "visual": false},
			{"name": "CisternRim", "position": Vector3(2.35, T3 + 0.80, -3.80), "size": Vector3(0.78, 0.06, 0.88), "material": "brass"},
		],
	}


## Ordered physical route used by the autopilot test. "hold" waypoints wait
## for a mechanism condition before rolling on.
static func _route() -> Array:
	return [
		{"at": Vector3(-3.60, T1, STRIP_Z), "via": "roll"},
		{"at": Vector3(-2.30, T1, STRIP_Z), "via": "roll", "event": "sluice"},
		{"at": Vector3(-1.75, T1, STRIP_Z), "via": "roll"},
		{"at": Vector3(-1.20, T1, 3.95), "via": "roll"},
		{"at": Vector3(0.10, T1, 3.95), "via": "roll"},
		{"at": Vector3(0.60, T1, STRIP_Z), "via": "roll"},
		{"at": Vector3(2.10, T1, STRIP_Z), "via": "bridge"},
		{"at": Vector3(2.85, T1, 2.45), "via": "roll"},
		{"at": Vector3(2.85, T1, 0.45), "via": "push_cube"},
		{"at": Vector3(2.85, T1, 2.40), "via": "roll"},
		{"at": Vector3(3.85, T1, 2.40), "via": "roll"},
		{"at": Vector3(3.85, T1, -0.42), "via": "roll", "wait": "mill_gate"},
		{"at": Vector3(3.55, T1, -1.50), "via": "roll"},
		{"at": Vector3(3.55, T2, -1.50), "via": "lift"},
		{"at": Vector3(2.30, T2, -1.48), "via": "roll"},
		{"at": Vector3(1.00, T2, -1.14), "via": "roll"},
		{"at": Vector3(0.40, T2, -1.20), "via": "roll"},
		{"at": Vector3(-0.70, T2, -1.25), "via": "roll", "wait": "sluice_boards"},
		{"at": Vector3(-1.60, T2, -1.48), "via": "pontoon"},
		{"at": Vector3(-2.90, T2, -1.48), "via": "roll"},
		{"at": Vector3(-3.55, T2, -3.40), "via": "roll", "event": "divert"},
		{"at": Vector3(-2.90, T2, -1.48), "via": "roll"},
		{"at": Vector3(-1.60, T2, -1.48), "via": "roll"},
		{"at": Vector3(-1.60, T3, -1.48), "via": "float"},
		{"at": Vector3(-0.45, T3, -1.10), "via": "roll"},
		{"at": Vector3(0.90, T3, -1.10), "via": "roll", "event": "gate"},
		{"at": Vector3(2.35, T3, -1.10), "via": "gate"},
		{"at": Vector3(2.35, T3, -1.60), "via": "roll"},
	]
