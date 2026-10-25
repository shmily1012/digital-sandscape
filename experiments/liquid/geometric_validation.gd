extends SceneTree

const Transport = preload("res://experiments/liquid/geometric_gpu.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		quit(2)
		return
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://reports/geometric-fixtures.json"))
	var failures := 0
	var cases: Array = []
	for fixture: Dictionary in fixtures:
		var transport := Transport.new()
		if not transport.initialize(rd, fixture):
			quit(2)
			return
		rd.capture_timestamp("transport_begin")
		var list := rd.compute_list_begin()
		if not transport.record_steps(list, int(fixture.steps), float(fixture.dt)):
			failures += 1
		rd.compute_list_end()
		rd.capture_timestamp("transport_end")
		rd.submit()
		rd.sync()
		var begin := -1
		var end := -1
		for index in range(rd.get_captured_timestamps_count()):
			if rd.get_captured_timestamp_name(index) == "transport_begin":
				begin = rd.get_captured_timestamp_gpu_time(index)
			if rd.get_captured_timestamp_name(index) == "transport_end":
				end = rd.get_captured_timestamp_gpu_time(index)
		var actual := rd.buffer_get_data(transport.output())
		var initial := PackedFloat32Array(fixture.initial).to_byte_array()
		var max_error := 0.0
		var minimum := INF
		var maximum := -INF
		var area_difference := 0.0
		for i in range(int(fixture.size)*int(fixture.size)):
			var value := actual.decode_float(i*4)
			if not is_finite(value):
				failures += 1
			if not fixture.active[i] and value != 0.0:
				failures += 1
			max_error = maxf(max_error, absf(value-float(fixture.expected[i])))
			area_difference += value-initial.decode_float(i*4)
			minimum = minf(minimum,value)
			maximum = maxf(maximum,value)
		area_difference /= float(fixture.size)*float(fixture.size)
		if max_error > 3e-4 or absf(area_difference) > 1e-6 or minimum < -2e-6 or maximum > 1+2e-6:
			failures += 1
		if fixture.name == "zero" and actual != initial:
			failures += 1
		# Invalid work must not advance ping-pong state or mutate buffers.
		var previous_parity := transport.parity
		list = rd.compute_list_begin()
		if transport.record_steps(list, 257, fixture.dt):
			failures += 1
		if transport.record_steps(list, 1, INF):
			failures += 1
		if is_finite(transport.max_dt) and transport.record_steps(list, 1, transport.max_dt*1.01):
			failures += 1
		rd.compute_list_end()
		rd.submit()
		rd.sync()
		if previous_parity != transport.parity or actual != rd.buffer_get_data(transport.output()):
			failures += 1
		cases.append({"name":fixture.name,"steps":fixture.steps,"max_fraction_error":max_error,"gas_area_error":area_difference,"minimum":minimum,"maximum":maximum,"single_sample_gpu_ms":float(end-begin)/1e6 if begin>=0 and end>=begin else -1})
		transport.release()
	var result := {"failures":failures,"device":rd.get_device_name(),"cases":cases,"scope":"Prescribed divergence-free face velocities, two-phase GPU transport only; no pressure or capillary generation. Timing is one un-warmed batch sample."}
	var report := FileAccess.open("res://reports/geometric-gpu-validation.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(result,"  "))
	report.close()
	print("GEOMETRIC_GPU_RESULT ",JSON.stringify(result))
	rd.free()
	quit(0 if failures == 0 else 1)
