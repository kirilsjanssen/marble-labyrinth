extends RefCounted
## Alpine Cascade: the finished Blender v4 model (mobile GLB, Level05Visuals) on
## the tilting board. Three tiers (deck tops 0 / 1.4 / 2.8 m) are linked by one
## hydraulic network and a wheel-driven three-stop lift:
##   start ring -> headgate opens -> aqueduct -> upper channel -> spill
##   notches -> middle channel -> shutter -> mill wheel -> millstone
##   aqueduct branch -> upper pool -> pool sluice -> east wheel -> bevel train
##   -> lift winch;  crate on the plate unlocks the lift; the terrace crank
##   (or the secret alcove lever) releases its top stop.
## Coordinates are written in the Blender design frame of
## tools/blender/build_level05.py (x, y, z up) and converted with P():
## board-local Godot = (x - 6, z, 6 - y); the board centre is Blender (6, 6).

const Z0 := 0.0
const Z1 := 1.4
const Z2 := 2.8


static func P(x: float, y: float, z: float) -> Vector3:
	return Vector3(x - 6.0, z, 6.0 - y)


## Blender axis -> Godot axis (same mapping, no translation).
static func A(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


static func definition() -> Dictionary:
	return {
		"number": 5,
		"id": "alpine_cascade_05",
		"title": "ALPINE CASCADE",
		"style": "alpine",
		"scene": "level05",
		"smart_camera": true,
		"alpine_environment": false,
		"camera_pivot": P(6.6, 5.4, 1.2),
		"camera_distance": 18.5,
		"camera_yaw_deg": -44.0,
		"hint": "Roll over the brass start ring to open the headgate, push the crate onto the plate, ride the mill lift",
		"start": P(0.8, 4.0, 0.36),
		"goal": P(2.4, 8.6, Z2 - 0.05),
		"goal_model": true,
		"walls": [],
		"holes": [
			# Swept down the spillway: back to the start lane, solved machinery kept.
			{"name": "SpillwayDrop", "position": P(6.4, 0.9, -0.55), "size": Vector3(0.9, 0.5, 1.8), "respawn": P(3.9, 4.0, 0.45), "plain": true},
			{"name": "WheelPitDrop", "position": P(9.3, 6.12, 0.2), "size": Vector3(2.4, 1.2, 0.9), "respawn": P(9.8, 3.0, Z1 + 0.45), "plain": true},
		],
		"level05": _mechanisms(),
		"route": _route(),
		"secret_route": _secret_route(),
	}


static func _mechanisms() -> Dictionary:
	return {
		# Volumes in m3, heads in board metres. One closed loop: the ram pump and
		# the mountain spring return the valley water, so volume is conserved.
		"water": {
			"reservoirs": [
				{"id": "pond", "capacity": 3.0, "volume": 2.8, "area": 3.0, "base": 3.4},
				{"id": "upper", "capacity": 0.54, "volume": 0.0, "area": 1.8, "base": 2.75},
				{"id": "pool", "capacity": 0.6, "volume": 0.0, "area": 1.85, "base": 2.8},
				{"id": "middle", "capacity": 0.15, "volume": 0.0, "area": 0.5, "base": 1.35},
				{"id": "pit", "capacity": 0.48, "volume": 0.0, "area": 2.4, "base": -0.2},
				{"id": "spring", "capacity": 0.4, "volume": 0.4, "area": 0.8, "base": -0.3},
				{"id": "stream", "capacity": 1.0, "volume": 0.3, "area": 5.0, "base": -0.45},
				{"id": "valley", "capacity": 40.0, "volume": 12.0, "area": 40.0, "base": -8.0},
			],
			"connections": [
				{"id": "head_main", "from": "pond", "to": "upper", "conductance": 0.8, "max_flow": 0.9, "valve": "headgate"},
				{"id": "head_branch", "from": "pond", "to": "pool", "conductance": 0.8, "max_flow": 0.9, "valve": "headgate"},
				{"id": "spill", "from": "upper", "to": "middle", "conductance": 2.0, "max_flow": 0.9, "valve": "diverter"},
				{"id": "mill_wheel", "from": "middle", "to": "pit", "conductance": 2.5, "max_flow": 1.0, "valve": "shutter"},
				{"id": "tailrace", "from": "pit", "to": "stream", "conductance": 4.0, "max_flow": 1.2},
				{"id": "pool_out", "from": "pool", "to": "valley", "conductance": 1.2, "max_flow": 0.9, "valve": "pool_sluice"},
				{"id": "stream_gate", "from": "spring", "to": "stream", "conductance": 2.0, "max_flow": 0.8, "valve": "stream_sluice"},
				{"id": "spill_out", "from": "stream", "to": "valley", "conductance": 1.5, "max_flow": 2.0},
				{"id": "pond_overflow", "from": "pond", "to": "valley", "conductance": 1.0, "max_flow": 0.25},
				{"id": "ram", "from": "valley", "to": "pond", "conductance": 0.0, "max_flow": 2.2, "pump": 2.2},
				{"id": "spring_in", "from": "valley", "to": "spring", "conductance": 0.0, "max_flow": 0.8, "pump": 0.8},
			],
			# Valves at reset; the start ring opens the headgate, the lever the stream sluice.
			"valves": {"headgate": 0.0, "diverter": 1.0, "shutter": 1.0, "pool_sluice": 1.0, "stream_sluice": 0.0},
			"nominal_flux": 0.85,
		},
		# Water bodies of the GLB and the connections whose flux drives them.
		"water_bodies": {
			"Water_MillPond": {"flux": ["head_main", "head_branch"], "gain": 0.25},
			"Water_PondLink": {"flux": ["head_main", "head_branch"], "gain": 0.6},
			"Waterfall_PondLink": {"flux": ["head_main", "head_branch"], "gain": 0.6},
			"Water_PondFeed": {"flux": ["head_main", "head_branch"], "gain": 0.6},
			"Waterfall_PondDrop": {"flux": ["head_main"]},
			"Water_PoolBranch": {"flux": ["head_branch"]},
			"Water_PoolDownFlume": {"flux": ["head_branch"]},
			"Waterfall_PoolFeed": {"flux": ["head_branch"]},
			"Water_UpperChannel": {"flux": ["head_main"]},
			"Waterfall_UpperWest": {"flux": ["spill"]},
			"Waterfall_UpperEast": {"flux": ["spill"]},
			"Water_MiddleChannel": {"flux": ["mill_wheel"]},
			"Waterfall_WheelFeed": {"flux": ["mill_wheel"]},
			"Water_WheelPit": {"flux": ["tailrace"]},
			"Water_UpperPool": {"flux": ["pool_out"], "gain": 0.5},
			"Water_EastFlume": {"flux": ["pool_out"]},
			"Waterfall_EastFeed": {"flux": ["pool_out"]},
			"Waterfall_EastWheel": {"flux": ["pool_out"]},
			"Water_Stream": {"flux": ["stream_gate", "tailrace"]},
			"Water_Spillway": {"flux": ["spill_out"]},
			"Waterfall_Spillway": {"flux": ["spill_out"]},
			"Waterfall_Spring": {"flux": ["spring_in"]},
			"Waterfall_PoolOverflow": {"flux": ["pond_overflow"], "gain": 3.0},
		},
		# Bodies inside these boxes feel buoyancy, drag and the stream current.
		"channels": [
			{"position": P(3.0, 2.5, -0.33), "size": Vector3(6.0, 0.3, 0.88), "reservoir": "stream", "flux": "spill_out", "flow": A(1.0, 0.0, 0.0), "flux_to_speed": 0.6},
		],
		# Beds the static layout data does not cover (loose slabs in v4).
		"extra_colliders": [
			{"name": "StreamBed", "position": P(3.4, 2.5, -0.48), "size": Vector3(6.8, 0.06, 1.0)},
			{"name": "SpillwayBed", "position": P(6.4, 1.0, -0.48), "size": Vector3(0.8, 0.06, 2.0)},
		],
		# Water wheels: GLB node, axis (Godot), sign so the wheel turns WITH its
		# water, and the connection whose flux drives it.
		"wheels": {
			"mill": {"node": "Wheel_Main", "axis": A(0.0, 1.0, 0.0), "sign": -1.0, "flux": "mill_wheel", "radius": 1.02},
			"east": {"node": "Wheel_East", "axis": A(1.0, 0.0, 0.0), "sign": 1.0, "flux": "pool_out", "radius": 0.74},
			"stream": {"node": "Wheel_Stream", "axis": A(0.0, 1.0, 0.0), "sign": -1.0, "flux": "stream_gate", "radius": 0.48},
		},
		# Rigid gear trains: angle = ratio * driver angle about the node's axis.
		# Bevel pairs (axes towards a common apex): w_b = -w_a * N_a / N_b.
		"train": [
			{"node": "Axle_Main", "source": "mill", "axis": A(0.0, 1.0, 0.0), "ratio": 1.0},
			{"node": "Gear_PitWheel", "source": "mill", "axis": A(0.0, 1.0, 0.0), "ratio": 1.0},
			# Pit wheel 16 -> wallower 7 (axis -Z towards apex): x16/7 about +Z.
			{"node": "Gear_Wallower", "source": "mill", "axis": A(0.0, 0.0, 1.0), "ratio": -16.0 / 7.0},
			{"node": "Shaft_Millstone", "source": "mill", "axis": A(0.0, 0.0, 1.0), "ratio": -16.0 / 7.0},
			{"node": "Millstone_Runner", "source": "mill", "axis": A(0.0, 0.0, 1.0), "ratio": -16.0 / 7.0},
			{"node": "Axle_East", "source": "east", "axis": A(1.0, 0.0, 0.0), "ratio": 1.0},
			{"node": "Gear_EastBevel", "source": "east", "axis": A(1.0, 0.0, 0.0), "ratio": 1.0},
			# East bevel 10 -> line bevel 10: 1:1, axis X -> Y.
			{"node": "Gear_LineBevelNorth", "source": "east", "axis": A(0.0, 1.0, 0.0), "ratio": 1.0},
			{"node": "Shaft_Line", "source": "east", "axis": A(0.0, 1.0, 0.0), "ratio": 1.0},
			{"node": "Gear_LineBevelSouth", "source": "east", "axis": A(0.0, 1.0, 0.0), "ratio": 1.0},
			# Line bevel 10 -> mast bevel 10: 1:1, axis Y -> Z.
			{"node": "Gear_MastBevelLow", "source": "east", "axis": A(0.0, 0.0, 1.0), "ratio": -1.0},
			{"node": "Shaft_Mast", "source": "east", "axis": A(0.0, 0.0, 1.0), "ratio": -1.0},
			{"node": "Gear_MastBevelTop", "source": "east", "axis": A(0.0, 0.0, 1.0), "ratio": -1.0},
			# Mast bevel 8 -> winch bevel 16: 2:1 reduction, axis Z -> X.
			{"node": "Gear_WinchBevel", "source": "east", "axis": A(1.0, 0.0, 0.0), "ratio": 0.5},
			{"node": "Shaft_Winch", "source": "east", "axis": A(1.0, 0.0, 0.0), "ratio": 0.5},
			# Crank pinion 9 -> pillar crown 22 (spur, parallel axes).
			{"node": "Gear_CrankPinion", "source": "crank", "axis": A(0.0, 0.0, 1.0), "ratio": 1.0},
			{"node": "Crank_Handle", "source": "crank", "axis": A(0.0, 0.0, 1.0), "ratio": 1.0, "pivot": P(4.368, 6.95, 2.35)},
			{"node": "Gear_PillarCrown", "source": "crank", "axis": A(0.0, 0.0, 1.0), "ratio": -9.0 / 22.0},
		],
		"lift": {
			"position": P(9.8, 1.0, Z0),
			"size": Vector3(1.44, 0.12, 1.44),
			"floors": [Z0, Z1, Z2],
			"exit_sides": ["west", "north", "north"],
			"locked": [false, true, true],
			"speed": 0.7,
			"depart_delay": 1.0,
			"call_pads": [P(8.4, 0.65, Z0 + 0.03), P(9.8, 2.95, Z1 + 0.03), P(10.1, 2.6, Z2 + 0.03)],
			"landing_gates": [
				{"position": P(8.95, 1.0, Z0), "size": Vector3(0.08, 0.5, 1.4)},
				{"position": P(9.8, 1.86, Z1), "size": Vector3(1.1, 0.5, 0.08)},
				{"position": P(10.1, 1.86, Z2), "size": Vector3(1.28, 0.5, 0.08)},
			],
			"skin": {"deck": "Lift_Cage", "doors": {"west": "Lift_Gate_West", "north": "Lift_Gate_North"}, "chain": "Lift_Chain"},
		},
		"cube": {"node": "Crate_Cube", "start": P(5.0, 1.0, 0.235), "size": Vector3(0.44, 0.44, 0.44)},
		# Stacked cargo is lashed to the decks: loose, the 15-degree board tilt
		# slid it into the lanes (stack top fell into the workshop lane, the
		# valve-deck crate slid 2.5 m onto the upper route). Only the puzzle
		# crate above is a free rigid body.
		"props": [
			{"node": "Crate_Workshop", "start": P(6.3, 3.0, Z1 + 0.25), "size": Vector3(0.48, 0.48, 0.48)},
			{"node": "Crate_Stack_A", "start": P(5.95, 3.62, Z1 + 0.25), "size": Vector3(0.48, 0.48, 0.48)},
			{"node": "Crate_Stack_B", "start": P(5.95, 3.62, Z1 + 0.745), "size": Vector3(0.48, 0.48, 0.48), "yaw": 0.3},
			{"node": "Crate_ValveDeck", "start": P(8.1, 9.2, Z2 + 0.25), "size": Vector3(0.48, 0.48, 0.48)},
		],
		"cube_plate": {"node": "Plate_Cube", "position": P(7.9, 1.35, Z0), "radius": 0.42},
		"start_ring": {"node": "Gear_StartRing", "position": P(3.3, 4.0, Z0), "radius": 0.45},
		"sluice_lever": {"node": "Lever_Sluice", "position": P(2.2, 4.55, Z0), "radius": 0.42},
		"crank": {"position": P(4.6, 6.1, Z1), "radius": 0.42, "turns": 3.0, "seconds": 2.4},
		"secret_ring": {"node": "Gear_CorridorTrigger", "position": P(8.2, 4.0, Z0), "radius": 0.4},
		"secret_lever": {"node": "Lever_Secret", "position": P(9.9, 4.4, Z0), "radius": 0.42},
		# At the channel edge, off the deck route (y 8.6): only a deliberate roll
		# toward the valve closes the spill notches.
		"diverter": {"node": "Valve_Diverter", "position": P(6.6, 7.98, Z2), "radius": 0.22},
		"valve_wheels": {"Valve_Diverter": "diverter", "Valve_PoolSluice": "pool_sluice"},
		# Sluice boards slide up in their grooves when their valve opens.
		"gates": {"Gate_StreamSluice": {"valve": "stream_sluice", "lift": 0.45}, "Gate_MiddleShutter": {"valve": "shutter", "lift": 0.3}},
	}


## Ordered physical route for the autopilot test (board-local targets).
static func _route() -> Array:
	return [
		{"at": P(0.8, 4.0, Z0), "via": "roll"},
		{"at": P(2.0, 4.0, Z0), "via": "roll"},
		{"at": P(3.3, 4.0, Z0), "via": "roll", "event": "headgate"},
		{"at": P(4.6, 4.0, Z0), "via": "roll"},
		{"at": P(4.6, 3.05, Z0), "via": "roll"},
		{"at": P(4.6, 1.95, Z0), "via": "roll"},
		{"at": P(4.35, 1.0, Z0), "via": "roll"},
		{"at": P(7.9, 1.35, Z0), "via": "push_cube"},
		{"at": P(7.2, 0.6, Z0), "via": "roll"},
		{"at": P(8.5, 0.6, Z0), "via": "roll"},
		{"at": P(9.8, 1.0, Z0), "via": "roll"},
		{"at": P(9.8, 1.0, Z1), "via": "lift", "floor": 1},
		{"at": P(9.8, 2.4, Z1), "via": "roll"},
		{"at": P(9.8, 3.0, Z1), "via": "roll"},
		{"at": P(8.0, 3.0, Z1), "via": "roll"},
		{"at": P(6.9, 4.0, Z1), "via": "roll"},
		{"at": P(6.3, 5.0, Z1), "via": "roll"},
		{"at": P(6.0, 5.85, Z1), "via": "roll"},
		{"at": P(5.0, 5.85, Z1), "via": "roll"},
		{"at": P(4.6, 6.1, Z1), "via": "crank"},
		{"at": P(5.0, 5.85, Z1), "via": "roll"},
		{"at": P(6.0, 5.85, Z1), "via": "roll"},
		{"at": P(6.3, 5.0, Z1), "via": "roll"},
		{"at": P(6.9, 4.0, Z1), "via": "roll"},
		{"at": P(8.0, 3.0, Z1), "via": "roll"},
		{"at": P(9.8, 3.0, Z1), "via": "roll"},
		{"at": P(9.8, 2.4, Z1), "via": "roll"},
		{"at": P(9.8, 1.0, Z1), "via": "roll"},
		{"at": P(9.8, 1.0, Z2), "via": "lift", "floor": 2},
		{"at": P(10.1, 1.8, Z2), "via": "roll"},
		{"at": P(10.1, 5.6, Z2), "via": "roll"},
		{"at": P(10.1, 6.5, Z2), "via": "roll"},
		{"at": P(10.1, 8.6, Z2), "via": "roll"},
		{"at": P(9.4, 8.6, Z2), "via": "roll"},
		{"at": P(8.5, 8.6, Z2), "via": "roll"},
		{"at": P(6.6, 8.6, Z2), "via": "roll"},
		{"at": P(4.5, 8.6, Z2), "via": "roll"},
		{"at": P(2.4, 8.6, Z2), "via": "goal"},
	]


## Hidden corridor: arch off the start lane -> corridor ring -> alcove lever.
static func _secret_route() -> Array:
	return [
		{"at": P(0.8, 4.0, Z0), "via": "roll"},
		{"at": P(3.3, 4.0, Z0), "via": "roll"},
		{"at": P(5.0, 4.0, Z0), "via": "roll"},
		{"at": P(6.0, 4.0, Z0), "via": "roll"},
		{"at": P(8.2, 4.0, Z0), "via": "roll", "event": "secret_ring"},
		{"at": P(9.6, 4.0, Z0), "via": "roll", "event": "secret_lever"},
	]
