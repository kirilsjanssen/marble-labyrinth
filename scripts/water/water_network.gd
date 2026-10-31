extends Node
class_name WaterNetwork
## Small conservative reservoir graph for Android-friendly fixed-timestep water.

signal volumes_changed

var reservoirs: Dictionary = {}
var connections: Array[WaterConnection] = []
var simulated_time := 0.0


func add_reservoir(id: StringName, capacity: float, initial_volume: float, surface_area: float, base_height: float = 0.0) -> void:
	assert(capacity > 0.0 and surface_area > 0.0)
	reservoirs[id] = {
		"capacity": capacity,
		"volume": clampf(initial_volume, 0.0, capacity),
		"initial_volume": clampf(initial_volume, 0.0, capacity),
		"surface_area": surface_area,
		"base_height": base_height,
		"tilt_head": 0.0,
		"temperature_c": 20.0,
	}


func add_connection(connection: WaterConnection) -> void:
	assert(reservoirs.has(connection.reservoir_a) and reservoirs.has(connection.reservoir_b))
	connections.append(connection)


func set_tilt_head(id: StringName, head_offset: float) -> void:
	if reservoirs.has(id):
		reservoirs[id].tilt_head = head_offset


func volume(id: StringName) -> float:
	return float(reservoirs[id].volume)


func capacity(id: StringName) -> float:
	return float(reservoirs[id].capacity)


func fill_ratio(id: StringName) -> float:
	return volume(id) / capacity(id)


func liquid_height(id: StringName) -> float:
	var data: Dictionary = reservoirs[id]
	return float(data.volume) / float(data.surface_area)


func hydraulic_head(id: StringName) -> float:
	var data: Dictionary = reservoirs[id]
	return float(data.base_height) + liquid_height(id) + float(data.tilt_head)


func total_volume() -> float:
	var total := 0.0
	for id in reservoirs:
		total += volume(id)
	return total


func step(delta: float) -> void:
	if delta <= 0.0 or connections.is_empty():
		return
	var proposals: Array[Dictionary] = []
	var outgoing: Dictionary = {}
	var incoming: Dictionary = {}
	for id in reservoirs:
		outgoing[id] = 0.0
		incoming[id] = 0.0

	# Compute every flux from one immutable volume snapshot.
	for connection in connections:
		var head_delta := hydraulic_head(connection.reservoir_a) - hydraulic_head(connection.reservoir_b)
		var flux := clampf(connection.conductance * head_delta * connection.openness(), -connection.max_flow, connection.max_flow)
		if connection.pump:
			flux += connection.pump.requested_flow(head_delta)
		flux = clampf(flux, -connection.max_flow, connection.max_flow)
		var amount := flux * delta
		var source: StringName = connection.reservoir_a if amount >= 0.0 else connection.reservoir_b
		var destination: StringName = connection.reservoir_b if amount >= 0.0 else connection.reservoir_a
		var requested := absf(amount)
		proposals.append({"connection": connection, "source": source, "destination": destination, "amount": requested, "sign": signf(flux)})
		outgoing[source] = float(outgoing[source]) + requested
		incoming[destination] = float(incoming[destination]) + requested

	var source_scale: Dictionary = {}
	var destination_scale: Dictionary = {}
	for id in reservoirs:
		var available := volume(id)
		var free_space := capacity(id) - available
		var requested_out := float(outgoing[id])
		var requested_in := float(incoming[id])
		source_scale[id] = minf(1.0, available / requested_out) if requested_out > 0.0 else 1.0
		destination_scale[id] = minf(1.0, free_space / requested_in) if requested_in > 0.0 else 1.0

	for proposal in proposals:
		var source: StringName = proposal.source
		var destination: StringName = proposal.destination
		var transferred: float = float(proposal.amount) * minf(float(source_scale[source]), float(destination_scale[destination]))
		reservoirs[source].volume = volume(source) - transferred
		reservoirs[destination].volume = volume(destination) + transferred
		var connection: WaterConnection = proposal.connection
		connection.last_flux = (transferred / delta) * float(proposal.sign)

	simulated_time += delta
	volumes_changed.emit()


func reset() -> void:
	for id in reservoirs:
		reservoirs[id].volume = float(reservoirs[id].initial_volume)
		reservoirs[id].tilt_head = 0.0
	for connection in connections:
		connection.last_flux = 0.0
	simulated_time = 0.0
	volumes_changed.emit()
