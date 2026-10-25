extends SceneTree

const Physics = preload("res://src/physics_engine.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		quit(2)
		return
	var shader := Physics.compile_shader(rd, "res://experiments/bubbles/step.glsl")
	if not shader.is_valid():
		rd.free()
		quit(2)
		return
	var pipeline := rd.compute_pipeline_create(shader)
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string("res://reports/bubble-gpu-fixtures.json"))
	var failures := 0
	var maximum_error := 0.0
	for fixture: Dictionary in cases:
		var values := PackedFloat32Array(fixture.initial)
		var data := values.to_byte_array()
		var buffers := [rd.storage_buffer_create(data.size(), data), rd.storage_buffer_create(data.size(), data)]
		var sets: Array[RID] = []
		for parity in range(2):
			var uniforms: Array[RDUniform] = []
			for binding in range(2):
				var uniform := RDUniform.new()
				uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
				uniform.binding = binding
				uniform.add_id(buffers[(parity+binding)%2])
				uniforms.append(uniform)
			sets.append(rd.uniform_set_create(uniforms, shader, 0))
		var params := PackedByteArray()
		params.resize(48)
		var scalars := [fixture.gravity[0], fixture.gravity[1], fixture.extent[0], fixture.extent[1], fixture.tension, fixture.stiffness, fixture.grain_drag, fixture.bubble_drag, fixture.shape_mobility, fixture.dt]
		for index in range(scalars.size()):
			params.encode_float(index*4, scalars[index])
		params.encode_u32(40, values.size()/8)
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, pipeline)
		rd.compute_list_set_push_constant(list, params, 48)
		for step in range(int(fixture.steps)):
			rd.compute_list_bind_uniform_set(list, sets[step%2], 0)
			rd.compute_list_dispatch(list, ceili(float(values.size()/8)/64.0), 1, 1)
			rd.compute_list_add_barrier(list)
		rd.compute_list_end()
		rd.submit()
		rd.sync()
		var actual := rd.buffer_get_data(buffers[int(fixture.steps)%2])
		for index in range(values.size()):
			var observed := actual.decode_float(index*4)
			var field := index%8
			if field == 2 or field >= 4:
				if actual.slice(index*4, index*4+4) != data.slice(index*4, index*4+4):
					failures += 1
			else:
				var error := absf(observed-float(fixture.expected[index]))
				maximum_error = maxf(maximum_error, error)
				if not is_finite(observed) or error > 2e-5:
					failures += 1
					push_error("E2 mismatch %s field=%d error=%s" % [fixture.name, field, error])
		for rid in sets:
			rd.free_rid(rid)
		for rid: RID in buffers:
			rd.free_rid(rid)
	var result := {"failures": failures, "scenarios": cases.size(), "steps_per_scenario": 1000, "max_state_error": maximum_error, "tolerance": 2e-5, "device": rd.get_device_name(), "scope": "Dimensionless elliptical inclusion candidate; no resolved liquid or calibrated interface"}
	var report := FileAccess.open("res://reports/bubble-gpu-validation.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(result, "  "))
	report.close()
	print("E2_GPU_RESULT ", JSON.stringify(result))
	rd.free_rid(pipeline)
	rd.free_rid(shader)
	rd.free()
	quit(0 if failures == 0 else 1)
