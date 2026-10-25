extends SceneTree

const Job = preload("res://experiments/liquid/async_pressure_job.gd")
var job: Node
var last_result: Dictionary = {}
var snapshot := PackedByteArray()
var captured := false
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _wait_ready() -> bool:
	for frame in range(2400):
		await process_frame
		if job.state == "idle":
			return true
	return false

func _capture() -> void:
	captured = false
	job.capture_published_for_test(func(data: PackedByteArray):
		snapshot = data
		captured = true)
	for frame in range(600):
		await process_frame
		if captured:
			return
	failures += 1

func _run() -> void:
	Engine.max_fps = 120
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://reports/multigrid-fixtures.json"))
	var fixture: Dictionary = {}
	for candidate: Dictionary in fixtures:
		if candidate.name == "settling_32":
			fixture = candidate
	job = Job.new()
	root.add_child(job)
	job.completed.connect(func(result: Dictionary): last_result = result)
	job.initialize(fixture.levels)
	if not await _wait_ready():
		push_error("Async pressure initialization timeout")
		quit(2)
		return
	var results: Array = []
	var previous := PackedByteArray()
	var version := 0
	for scenario: Dictionary in [{"name":"cold", "scale":1.0, "budget":96}, {"name":"unchanged", "scale":1.0, "budget":96}, {"name":"changed", "scale":1.01, "budget":96}, {"name":"budget_exhausted", "scale":-1.0, "budget":1}, {"name":"invalid", "scale":1.0, "budget":8}, {"name":"cancelled", "scale":-1.0, "budget":96}]:
		var equations := PackedFloat32Array(fixture.levels[0].equations).to_byte_array()
		var n := int(fixture.size)
		for i in range(n*n):
			equations.encode_float(i*32+16, equations.decode_float(i*32+16)*scenario.scale)
		if scenario.name == "invalid":
			equations.encode_float(16, NAN)
		last_result = {}
		if not job.start(equations, scenario.budget, 8):
			failures += 1
		if job.start(equations, scenario.budget, 8):
			failures += 1
		if scenario.name == "cancelled":
			job.cancel()
		if not await _wait_ready() or last_result.is_empty():
			push_error("Async pressure callback timeout")
			quit(2)
			return
		await _capture()
		var success: bool = scenario.name in ["cold","unchanged","changed"]
		if last_result.success != success or last_result.status_readback_bytes != last_result.packets*16:
			failures += 1
		if success:
			version += 1
			var maximum_error := 0.0
			for i in range(n*n):
				maximum_error = maxf(maximum_error, absf(snapshot.decode_float(i*4)-float(fixture.pressure[i])*float(scenario.scale)))
			if maximum_error > 2e-6:
				failures += 1
			last_result["pressure_error"] = maximum_error
		elif snapshot != previous:
			failures += 1
		if job.published_version != version:
			failures += 1
		if scenario.name == "unchanged" and (last_result.cycles != 0 or last_result.packets != 1 or snapshot != previous):
			failures += 1
		last_result["name"] = scenario.name
		results.append(last_result.duplicate())
		previous = snapshot.duplicate()
	# Close with an asynchronous status request still outstanding.
	var equations := PackedFloat32Array(fixture.levels[0].equations).to_byte_array()
	job.start(equations, 96, 8)
	job.close()
	for frame in range(600):
		await process_frame
		if job.state == "closed":
			break
	if job.state != "closed" or job.pending or job.published_version != version:
		failures += 1
	var report := {"failures":failures,"cases":results,"closed_with_pending_callback":job.state == "closed","scope":"Main RenderingDevice, render-thread ownership, async 16-byte status, one packet in flight, transactional pressure publication. Full readback is test-only. wall_ms is latency, not GPU time."}
	var file := FileAccess.open("res://reports/async-pressure-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("ASYNC_PRESSURE_RESULT ", JSON.stringify(report))
	job.queue_free()
	quit(0 if failures == 0 else 1)
