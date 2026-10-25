extends SceneTree

const Physics = preload("res://src/physics_engine.gd")
const Art = preload("res://src/art_renderer.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		quit(2)
		return
	var results := []
	for side in [256, 512]:
		var physics := Physics.new()
		var art := Art.new()
		if not physics.initialize(rd, side, 20261024, true) or not art.initialize(rd, physics.state, side):
			art.release()
			physics.release()
			rd.free()
			quit(2)
			return
		var samples: Array[float] = []
		for sample in range(70):
			rd.capture_timestamp("compute_begin")
			physics.advance(Vector2i(0, 32767), 1)
			art.refresh()
			rd.capture_timestamp("compute_end")
			rd.submit()
			rd.sync()
			var begin := -1
			var end := -1
			for index in range(rd.get_captured_timestamps_count()):
				if rd.get_captured_timestamp_name(index) == "compute_begin":
					begin = rd.get_captured_timestamp_gpu_time(index)
				if rd.get_captured_timestamp_name(index) == "compute_end":
					end = rd.get_captured_timestamp_gpu_time(index)
			if sample >= 10 and begin >= 0 and end > begin:
				samples.append((end - begin) / 1000000.0)
			await process_frame
		if samples.is_empty():
			push_error("No valid GPU timestamps; benchmark unavailable")
			art.release()
			physics.release()
			rd.free()
			quit(2)
			return
		samples.sort()
		results.append({"side": side, "samples": samples.size(), "gpu_ms_p50": samples[samples.size()/2], "gpu_ms_p95": samples[ceili(samples.size()*0.95)-1], "gpu_ms_max": samples[-1], "dedicated_texture_bytes": side*side*24})
		art.release()
		physics.release()
	var report := {"engine": Engine.get_version_info().string, "device": rd.get_device_name(), "scope": "Local RD, one liquid/gas approximation physics tick plus colorize; 10 warmup frames, 60 samples. Excludes Canvas rendering and driver/runtime memory. Not utilization or a long-duration benchmark.", "results": results}
	var file := FileAccess.open("res://reports/gpu-benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("GPU_BENCHMARK ", JSON.stringify(report))
	rd.free()
	quit(0)
