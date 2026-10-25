extends SceneTree

const Physics = preload("res://src/physics_engine.gd")
const MultigridGPU = preload("res://experiments/liquid/multigrid_gpu.gd")

func _initialize() -> void:
	_run.call_deferred()

func make_set(rd: RenderingDevice, shader: RID, buffers: Array) -> RID:
	var uniforms: Array[RDUniform] = []
	for binding in range(buffers.size()):
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = binding
		uniform.add_id(buffers[binding])
		uniforms.append(uniform)
	return rd.uniform_set_create(uniforms, shader, 0)

func _run() -> void:
	var use_multigrid := "--multigrid" in OS.get_cmdline_user_args()
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		quit(2)
		return
	var pressure_shader := Physics.compile_shader(rd, "res://experiments/liquid/pressure.glsl")
	var flux_shader := Physics.compile_shader(rd, "res://experiments/liquid/flux.glsl")
	if not pressure_shader.is_valid() or not flux_shader.is_valid():
		rd.free()
		quit(2)
		return
	var pressure_pipeline := rd.compute_pipeline_create(pressure_shader)
	var flux_pipeline := rd.compute_pipeline_create(flux_shader)
	var fixture_path := "res://reports/multigrid-fixtures.json" if use_multigrid else "res://reports/liquid-fixtures.json"
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	var failures := 0
	var results: Array = []
	for fixture: Dictionary in fixtures:
		var n := int(fixture.size)
		var zero := PackedByteArray()
		zero.resize(n*n*4)
		zero.fill(0)
		var pressure := [rd.storage_buffer_create(zero.size(), zero), rd.storage_buffer_create(zero.size(), zero)]
		var equations := PackedFloat32Array(fixture.equations).to_byte_array()
		var equations_buffer := rd.storage_buffer_create(equations.size(), equations)
		var sets := [make_set(rd, pressure_shader, [pressure[0],pressure[1],equations_buffer]), make_set(rd, pressure_shader, [pressure[1],pressure[0],equations_buffer])]
		var face_data := PackedByteArray()
		face_data.resize(fixture.faces.size()*16)
		for index in range(fixture.faces.size()):
			var face: Array = fixture.faces[index]
			face_data.encode_u32(index*16, int(face[0]))
			face_data.encode_u32(index*16+4, int(face[1]))
			face_data.encode_float(index*16+8, face[2])
			face_data.encode_float(index*16+12, face[3])
		var faces := rd.storage_buffer_create(face_data.size(), face_data)
		var flux := rd.storage_buffer_create(fixture.faces.size()*8)
		var multigrid := MultigridGPU.new()
		var output: RID = pressure[int(fixture.steps)%2]
		if use_multigrid:
			if not multigrid.initialize(rd, fixture.levels):
				quit(2)
				return
			output = multigrid.output_after(int(fixture.steps))
		var flux_set := make_set(rd, flux_shader, [output,faces,flux])
		var params := PackedByteArray()
		params.resize(16)
		params.encode_u32(0, n)
		params.encode_float(4, 0.8)
		rd.capture_timestamp("pressure_flux_begin")
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, pressure_pipeline)
		rd.compute_list_set_push_constant(list, params, 16)
		for step in range(int(fixture.steps)):
			if use_multigrid:
				multigrid.cycle(list)
			else:
				rd.compute_list_bind_uniform_set(list, sets[step%2], 0)
				rd.compute_list_dispatch(list, ceili(float(n*n)/64), 1, 1)
				rd.compute_list_add_barrier(list)
		params.encode_u32(0, fixture.faces.size())
		params.encode_float(4, 1.0/n)
		rd.compute_list_bind_compute_pipeline(list, flux_pipeline)
		rd.compute_list_bind_uniform_set(list, flux_set, 0)
		rd.compute_list_set_push_constant(list, params, 16)
		rd.compute_list_dispatch(list, ceili(float(fixture.faces.size())/64), 1, 1)
		rd.compute_list_end()
		rd.capture_timestamp("pressure_flux_end")
		rd.submit()
		rd.sync()
		var gpu_begin := -1
		var gpu_end := -1
		for index in range(rd.get_captured_timestamps_count()):
			if rd.get_captured_timestamp_name(index) == "pressure_flux_begin":
				gpu_begin = rd.get_captured_timestamp_gpu_time(index)
			if rd.get_captured_timestamp_name(index) == "pressure_flux_end":
				gpu_end = rd.get_captured_timestamp_gpu_time(index)
		var gpu_ms := float(gpu_end-gpu_begin)/1e6 if gpu_begin >= 0 and gpu_end >= gpu_begin else -1.0
		var actual_p := rd.buffer_get_data(output)
		var actual_flux := rd.buffer_get_data(flux)
		var maximum_error := 0.0
		var divergence := PackedFloat64Array()
		divergence.resize(n*n)
		for index in range(n*n):
			var value := actual_p.decode_float(index*4)
			if not is_finite(value):
				failures += 1
			maximum_error = maxf(maximum_error, absf(value-float(fixture.pressure[index])))
		for index in range(fixture.faces.size()):
			var liquid := actual_flux.decode_float(index*8)
			var mixture := actual_flux.decode_float(index*8+4)
			if not is_finite(liquid) or not is_finite(mixture):
				failures += 1
			maximum_error = maxf(maximum_error, absf(liquid-float(fixture.liquid[index])))
			maximum_error = maxf(maximum_error, absf(mixture-float(fixture.mixture[index])))
			divergence[int(fixture.faces[index][0])] += mixture*n
			divergence[int(fixture.faces[index][1])] -= mixture*n
		var residual := 0.0
		for value in divergence:
			residual = maxf(residual, absf(value))
		if maximum_error > 2e-6 or residual > 1e-5:
			failures += 1
		results.append({"name": fixture.name, "size": n, "iterations": fixture.steps, "pressure_dispatches": multigrid.dispatches if use_multigrid else int(fixture.steps), "single_sample_gpu_ms": gpu_ms, "max_state_error": maximum_error, "max_divergence": residual, "pressure_representation": "base plus residual" if fixture.get("base_pressure") != null else "full"})
		for rid: RID in sets+[flux_set,flux,faces,equations_buffer]+pressure:
			rd.free_rid(rid)
		if use_multigrid:
			multigrid.release()
	var result := {"failures": failures, "device": rd.get_device_name(), "cases": results, "scope": "Instantaneous prescribed phase flux projection; no advection or feedback. Timing is one un-warmed GPU sample including pressure and flux, not a steady-state benchmark or utilization."}
	var report_path := "res://reports/multigrid-gpu-validation.json" if use_multigrid else "res://reports/liquid-gpu-validation.json"
	var report := FileAccess.open(report_path, FileAccess.WRITE)
	report.store_string(JSON.stringify(result, "  "))
	report.close()
	print("LIQUID_GPU_RESULT ", JSON.stringify(result))
	for rid in [pressure_pipeline,flux_pipeline,pressure_shader,flux_shader]:
		rd.free_rid(rid)
	rd.free()
	quit(0 if failures == 0 else 1)
