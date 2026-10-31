extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var network := WaterNetwork.new()
	root.add_child(network)
	network.add_reservoir(&"A", 10.0, 8.0, 4.0, 0.0)
	network.add_reservoir(&"B", 10.0, 2.0, 4.0, 0.0)
	var valve := WaterValve.new()
	valve.openness = 0.0
	var connection := WaterConnection.new()
	connection.reservoir_a = &"A"
	connection.reservoir_b = &"B"
	connection.conductance = 1.4
	connection.max_flow = 2.0
	connection.valve = valve
	network.add_connection(connection)
	var initial_total := network.total_volume()
	for _tick in range(120):
		network.step(1.0 / 60.0)
	if not _require(is_equal_approx(network.volume(&"A"), 8.0), "closed valve must stop transfer"):
		return

	valve.openness = 1.0
	for _tick in range(360):
		network.step(1.0 / 60.0)
	if not _require(network.volume(&"A") < 7.0 and network.volume(&"B") > 3.0, "open valve must move water down the head gradient"):
		return
	var before_reverse := network.volume(&"A")
	network.set_tilt_head(&"A", -2.0)
	network.set_tilt_head(&"B", 2.0)
	for _tick in range(240):
		network.step(1.0 / 60.0)
	if not _require(network.volume(&"A") > before_reverse + 0.2, "reversed tilt must reverse flow"):
		return

	for _tick in range(2000):
		network.step(1.0 / 60.0)
	if not _require(absf(network.total_volume() - initial_total) < 0.00001, "water volume must be conserved for 2000+ ticks"):
		return
	for id in network.reservoirs:
		if not _require(network.volume(id) >= 0.0 and network.volume(id) <= network.capacity(id), "reservoir bounds must hold"):
			return

	var pumped := WaterNetwork.new()
	root.add_child(pumped)
	pumped.add_reservoir(&"LOW", 10.0, 7.0, 4.0, 0.0)
	pumped.add_reservoir(&"HIGH", 10.0, 1.0, 4.0, 3.0)
	var pump := WaterPump.new()
	pump.enabled = false
	pump.direction = 1.0
	pump.flow_rate = 1.25
	pump.max_head = 5.0
	var pipe := WaterConnection.new()
	pipe.reservoir_a = &"LOW"
	pipe.reservoir_b = &"HIGH"
	pipe.conductance = 0.0
	pipe.max_flow = 1.25
	pipe.pump = pump
	pumped.add_connection(pipe)
	for _tick in range(120):
		pumped.step(1.0 / 60.0)
	if not _require(is_equal_approx(pumped.volume(&"HIGH"), 1.0), "disabled pump must not lift water"):
		return
	pump.enabled = true
	for _tick in range(120):
		pumped.step(1.0 / 60.0)
	if not _require(pumped.volume(&"HIGH") > 3.4, "enabled pump must lift a bounded amount of water"):
		return
	if not _require(absf(pumped.total_volume() - 8.0) < 0.00001, "pump must conserve water"):
		return

	var overflow := WaterNetwork.new()
	root.add_child(overflow)
	overflow.add_reservoir(&"BOWL", 5.0, 5.0, 1.0, 2.0)
	overflow.add_reservoir(&"CATCH", 8.0, 0.0, 2.0, 0.0)
	var drain := WaterConnection.new()
	drain.reservoir_a = &"BOWL"
	drain.reservoir_b = &"CATCH"
	drain.conductance = 0.8
	drain.max_flow = 1.0
	overflow.add_connection(drain)
	for _tick in range(180):
		overflow.step(1.0 / 60.0)
	if not _require(overflow.volume(&"CATCH") > 1.0 and absf(overflow.total_volume() - 5.0) < 0.00001, "overflow must reach an explicit catch reservoir without mass loss"):
		return

	print("WATER NETWORK PASS: valve, downhill/reverse flow, pump, overflow, bounds and conservation")
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("WATER NETWORK FAIL: " + message)
	quit(1)
	return false
