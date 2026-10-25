extends SceneTree

const MultigridGPU = preload("res://experiments/liquid/multigrid_gpu.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		quit(2)
		return
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://reports/multigrid-fixtures.json"))
	var fixture: Dictionary = {}
	for candidate: Dictionary in fixtures:
		if candidate.name == "settling_32":
			fixture = candidate
	if fixture.is_empty():
		quit(2)
		return
	var fused := OS.get_cmdline_user_args().has("--fused-pressure")
	var solver := MultigridGPU.new()
	solver.fuse_coarse = fused
	if not solver.initialize(rd, fixture.levels):
		quit(2)
		return
	var failures := 0
	var cases: Array = []
	var scenarios := [{"name":"cold", "scale":1.0, "budget":96}, {"name":"same_rhs", "scale":1.0, "budget":96}, {"name":"changed_rhs", "scale":1.01, "budget":96}, {"name":"budget_exhausted", "scale":-1.0, "budget":1}, {"name":"nonfinite_rhs", "scale":1.0, "budget":2}]
	var previous_state := PackedByteArray()
	for scenario: Dictionary in scenarios:
		var equations := PackedFloat32Array(fixture.levels[0].equations).to_byte_array()
		for i in range(int(fixture.size)*int(fixture.size)):
			equations.encode_float(i*32+16, equations.decode_float(i*32+16)*scenario.scale)
		if scenario.name == "nonfinite_rhs":
			equations.encode_float(16, NAN)
		rd.buffer_update(solver.levels[0].equations, 0, equations.size(), equations)
		solver.reset_statistics()
		rd.capture_timestamp("adaptive_begin")
		var list := rd.compute_list_begin()
		var output: RID = solver.record_adaptive(list, scenario.budget, 2e-6, false, fused)
		rd.compute_list_end()
		rd.capture_timestamp("adaptive_end")
		rd.submit()
		rd.sync()
		# Capture query results before buffer_get_data performs further transfers.
		var begin := -1
		var end := -1
		for i in range(rd.get_captured_timestamps_count()):
			if rd.get_captured_timestamp_name(i) == "adaptive_begin":
				begin = rd.get_captured_timestamp_gpu_time(i)
			if rd.get_captured_timestamp_name(i) == "adaptive_end":
				end = rd.get_captured_timestamp_gpu_time(i)
		var metadata := rd.buffer_get_data(solver.control, 0, 16)
		var state := rd.buffer_get_data(output)
		var converged := metadata.decode_u32(4) == 1
		var cycles := metadata.decode_u32(8)
		var invalid := metadata.decode_u32(12) == 1
		var equation_residual := 0.0
		var pressure_error := 0.0
		var n := int(fixture.size)
		if scenario.name != "nonfinite_rhs":
			for i in range(n*n):
				var value := state.decode_float(i*4)
				pressure_error = maxf(pressure_error, absf(value-float(fixture.pressure[i])*float(scenario.scale)))
				var residual := float(equations.decode_float(i*32+16))
				for direction in range(4):
					var weight := float(equations.decode_float(i*32+direction*4))
					if weight > 0:
						var neighbor: int = i+[-1,1,-n,n][direction]
						residual -= weight*(value-float(state.decode_float(neighbor*4)))
				equation_residual = maxf(equation_residual, absf(residual))
		if scenario.name == "nonfinite_rhs":
			if not invalid or converged or cycles != 0 or state != previous_state:
				failures += 1
		elif scenario.name == "budget_exhausted":
			if converged or invalid or cycles != 1 or equation_residual <= 2e-6:
				failures += 1
		else:
			if not converged or invalid or pressure_error > 2e-6 or equation_residual > 1e-5:
				failures += 1
			if scenario.name == "same_rhs" and (cycles != 0 or state != previous_state):
				failures += 1
			if scenario.name == "changed_rhs" and cycles == 0:
				failures += 1
		cases.append({"name":scenario.name, "converged":converged, "invalid":invalid, "executed_cycles":cycles, "gpu_residual":metadata.decode_float(0) if not invalid else "nonfinite", "independent_residual":equation_residual if not invalid else "nonfinite", "pressure_error":pressure_error if not invalid else "not_applicable", "single_sample_gpu_ms":float(end-begin)/1e6 if begin>=0 and end>=begin else -1})
		previous_state = state
	var result := {"failures":failures, "device":rd.get_device_name(), "fused":fused, "cases":cases, "scope":"GPU residual decision, indirect gating and persistent pressure warm start; candidate pressure must not be committed to physics on budget exhaustion. Timing is one un-warmed sample."}
	var report := FileAccess.open("res://reports/adaptive-pressure-fused.json" if fused else "res://reports/adaptive-pressure-validation.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(result,"  "))
	report.close()
	print("ADAPTIVE_PRESSURE_RESULT ",JSON.stringify(result))
	solver.release()
	rd.free()
	quit(0 if failures == 0 else 1)
