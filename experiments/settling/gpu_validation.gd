extends SceneTree

const Physics = preload("res://src/physics_engine.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		quit(2)
		return
	var shader := Physics.compile_shader(rd, "res://experiments/settling/settling.glsl")
	if not shader.is_valid():
		rd.free()
		quit(2)
		return
	var pipeline := rd.compute_pipeline_create(shader)
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string("res://reports/settling-fixtures.json"))
	var failures := 0
	var max_position_error := 0.0
	var max_velocity_error := 0.0
	for fixture: Dictionary in cases:
		var values := PackedFloat32Array(fixture.initial)
		var data := values.to_byte_array()
		var state := rd.storage_buffer_create(data.size(), data)
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = 0
		uniform.add_id(state)
		var uniform_set := rd.uniform_set_create([uniform], shader, 0)
		var params := PackedByteArray()
		params.resize(32)
		params.encode_float(0, fixture.gravity[0])
		params.encode_float(4, fixture.gravity[1])
		params.encode_float(8, fixture.flow[0])
		params.encode_float(12, fixture.flow[1])
		params.encode_float(16, 1000.0)
		params.encode_float(20, fixture.viscosity)
		params.encode_float(24, fixture.dt)
		params.encode_u32(28, values.size()/12)
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, pipeline)
		rd.compute_list_bind_uniform_set(list, uniform_set, 0)
		rd.compute_list_set_push_constant(list, params, 32)
		for step in range(int(fixture.steps)):
			rd.compute_list_dispatch(list, 1, 1, 1)
			rd.compute_list_add_barrier(list)
		rd.compute_list_end()
		rd.submit()
		rd.sync()
		var actual := rd.buffer_get_data(state)
		for index in range(values.size()):
			var observed := actual.decode_float(index*4)
			var expected: float = fixture.expected[index]
			var field := index % 12
			var error := absf(observed-expected)
			if field >= 8:
				if not is_finite(observed):
					failures += 1
			elif field >= 4:
				if actual.slice(index*4, index*4+4) != data.slice(index*4, index*4+4):
					failures += 1
			else:
				var tolerance := 1e-7 if field < 2 else 1e-9+absf(expected)*1e-4
				if not is_finite(observed) or error > tolerance:
					failures += 1
					push_error("E1 mismatch angle=%s field=%d error=%s" % [fixture.angle, field, error])
				if field < 2:
					max_position_error = maxf(max_position_error, error)
				else:
					max_velocity_error = maxf(max_velocity_error, error)
		rd.free_rid(uniform_set)
		rd.free_rid(state)
	var result := {"failures": failures, "scenarios": cases.size(), "grains_per_scenario": 5, "max_position_error_m": max_position_error, "max_velocity_error_m_s": max_velocity_error, "device": rd.get_device_name(), "scope": "E1 dilute rigid-sphere solver only; prescribed uniform liquid, no boundaries or contacts"}
	var report := FileAccess.open("res://reports/settling-gpu-validation.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(result, "  "))
	report.close()
	print("E1_GPU_RESULT ", JSON.stringify(result))
	rd.free_rid(pipeline)
	rd.free_rid(shader)
	rd.free()
	quit(0 if failures == 0 else 1)
