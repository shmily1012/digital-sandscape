extends SceneTree

const Physics = preload("res://src/phase_fluid.gd")
const Art = preload("res://src/phase_art.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		quit(2)
		return
	var results := []
	var energy_mode:bool="--benchmark-energy" in OS.get_cmdline_user_args()
	for side in [256, 512]:
		var physics := Physics.new()
		var art := Art.new()
		var fields:=Physics.initial_fields(side,20261024,true)
		if energy_mode:
			fields=Physics.contact_fields(side,side/4)
			physics.grain_energy_enabled=true;physics.voxel_interface_enabled=true;physics.grain_wetting_cosine=.5
			physics.grain_collective_enabled="--collective-exchange" in OS.get_cmdline_user_args()
		if not physics.initialize(rd,side,fields.gas,fields.walls,PackedVector2Array(),true,20261024) or not art.initialize(rd,physics.phase,side,physics.materials):
			art.release()
			physics.release()
			rd.free()
			quit(2)
			return
		var samples: Array[float] = []
		var physics_samples:Array[float]=[]
		for sample in range(70):
			rd.capture_timestamp("compute_begin")
			physics.advance(1,Vector2(0,0.00002),0.01)
			rd.capture_timestamp("physics_end")
			art.refresh(physics.tick%2)
			rd.capture_timestamp("compute_end")
			rd.submit()
			rd.sync()
			var begin := -1
			var end := -1
			var physics_end:=-1
			for index in range(rd.get_captured_timestamps_count()):
				if rd.get_captured_timestamp_name(index) == "compute_begin":
					begin = rd.get_captured_timestamp_gpu_time(index)
				if rd.get_captured_timestamp_name(index) == "compute_end":
					end = rd.get_captured_timestamp_gpu_time(index)
				if rd.get_captured_timestamp_name(index)=="physics_end":physics_end=rd.get_captured_timestamp_gpu_time(index)
			if sample >= 10 and begin >= 0 and end > begin:
				samples.append((end - begin) / 1000000.0)
				physics_samples.append((physics_end-begin)/1000000.)
			await process_frame
		if samples.is_empty():
			push_error("No valid GPU timestamps; benchmark unavailable")
			art.release()
			physics.release()
			rd.free()
			quit(2)
			return
		samples.sort()
		physics_samples.sort()
		results.append({"side": side, "samples": samples.size(), "gpu_ms_p50": samples[samples.size()/2], "gpu_ms_p95": samples[ceili(samples.size()*0.95)-1], "gpu_ms_max": samples[-1], "dedicated_buffers_and_image_bytes": side*side*136, "load_factor":physics.load_factor,"boundary_motion_enabled":physics.boundary_motion_enabled})
		results[-1].physics_gpu_ms_p95=physics_samples[ceili(physics_samples.size()*.95)-1]
		results[-1].energy_exchange=energy_mode
		results[-1].collective_exchange=physics.grain_collective_enabled
		if energy_mode:
			results[-1].dedicated_buffers_and_image_bytes+=side*side*12
		if physics.grain_collective_enabled:results[-1].dedicated_buffers_and_image_bytes+=16
		art.release()
		physics.release()
	var report := {"engine": Engine.get_version_info().string, "device": rd.get_device_name(), "scope": "Local RD, one LBM/phase/voxel-grain tick plus colorize; 10 warmup frames, 60 samples. Excludes Canvas rendering and driver/runtime memory. Not utilization or a long-duration benchmark.", "results": results}
	var file := FileAccess.open("res://reports/grain-collective-benchmark.json" if "--collective-exchange" in OS.get_cmdline_user_args() else ("res://reports/grain-energy-benchmark.json" if energy_mode else "res://reports/phase-sand-benchmark.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("PHASE_SAND_BENCHMARK ", JSON.stringify(report))
	rd.free()
	quit(0)
