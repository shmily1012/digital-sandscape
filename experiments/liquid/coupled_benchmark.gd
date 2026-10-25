extends SceneTree
const Solver = preload("res://experiments/liquid/multigrid_gpu.gd")
const Transport = preload("res://experiments/liquid/geometric_gpu.gd")
const Force = preload("res://experiments/liquid/buoyancy_gpu.gd")
const Art = preload("res://experiments/liquid/live_art.gd")

func _initialize() -> void:
	_run.call_deferred()

func _submit_ms(rd: RenderingDevice) -> float:
	rd.capture_timestamp("end")
	rd.submit()
	rd.sync()
	var begin := -1
	var end := -1
	for i in range(rd.get_captured_timestamps_count()):
		if rd.get_captured_timestamp_name(i)=="begin": begin=rd.get_captured_timestamp_gpu_time(i)
		if rd.get_captured_timestamp_name(i)=="end": end=rd.get_captured_timestamp_gpu_time(i)
	return float(end-begin)/1e6 if begin>=0 and end>=begin else -1.0

func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd==null:
		quit(2)
		return
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://reports/pressure-transport-fixtures.json"))
	var sequence: Array = JSON.parse_string(FileAccess.get_file_as_string("res://reports/capillary-sequence.json"))
	var fixture: Dictionary = fixtures[0]
	fixture.geometry.initial = sequence[0].initial
	var results: Array = []
	var failures := 0
	for strategy in ["prequeue96","batches8","fused8"]:
		var batch := 96 if strategy=="prequeue96" else 8
		var solver := Solver.new()
		var transport := Transport.new()
		var force := Force.new()
		var art := Art.new()
		if not solver.initialize(rd,fixture.levels) or not transport.initialize(rd,fixture.geometry) or not force.initialize(rd) or not art.initialize(rd):
			quit(2)
			return
		var bytes := PackedByteArray()
		bytes.resize(fixture.faces.size()*16)
		for i in range(fixture.faces.size()):
			bytes.encode_u32(i*16,fixture.faces[i][0])
			bytes.encode_u32(i*16+4,fixture.faces[i][1])
			bytes.encode_float(i*16+8,fixture.faces[i][2])
		var forcing := rd.storage_buffer_create(bytes.size(),bytes)
		var samples: Array = []
		var totals := [0.0,0.0,0.0]
		var packets := 0
		var count := mini(70,sequence.size())
		for step in range(count):
			solver.reset_statistics()
			var gravity := Vector2(sequence[step].gravity[0],sequence[step].gravity[1])
			rd.capture_timestamp("begin")
			var list := rd.compute_list_begin()
			force.record(list,transport.output(),forcing,transport.buffers[3],solver.levels[0].equations,32,fixture.faces.size(),gravity,0.02,0.001,5.0)
			rd.compute_list_end()
			var force_ms := _submit_ms(rd)
			var pressure_ms := 0.0
			var pressure: RID
			var converged := false
			for packet in range(96/batch):
				rd.capture_timestamp("begin")
				list = rd.compute_list_begin()
				pressure = solver.record_adaptive(list,batch,2e-6)
				if strategy=="fused8":
					transport.record_dynamic_step(list,pressure,forcing,solver.control,0.0005)
					art.record(list,transport.output())
				rd.compute_list_end()
				pressure_ms += _submit_ms(rd)
				packets += 1
				var status := rd.buffer_get_data(solver.control,0,16)
				if status.decode_u32(4)==1:
					converged = true
					break
			if not converged: failures += 1
			var transport_ms := 0.0
			if strategy!="fused8":
				rd.capture_timestamp("begin")
				list = rd.compute_list_begin()
				transport.record_dynamic_step(list,pressure,forcing,solver.control,0.0005)
				art.record(list,transport.output())
				rd.compute_list_end()
				transport_ms = _submit_ms(rd)
			var status := rd.buffer_get_data(transport.buffers[10])
			if status.decode_u32(4)!=1 or force_ms<0 or pressure_ms<0 or transport_ms<0: failures += 1
			if step>=10:
				samples.append(force_ms+pressure_ms+transport_ms)
				totals[0]+=force_ms
				totals[1]+=pressure_ms
				totals[2]+=transport_ms
		var state := rd.buffer_get_data(transport.output())
		var error := 0.0
		for i in range(1024): error=maxf(error,absf(state.decode_float(i*4)-float(sequence[count-1].expected[i])))
		if error>3e-4: failures += 1
		samples.sort()
		results.append({"strategy":strategy,"batch_cycles":batch,"steps":count,"samples":samples.size(),"p50_gpu_ms":samples[samples.size()/2],"p95_gpu_ms":samples[ceili(samples.size()*0.95)-1],"mean_force_ms":totals[0]/samples.size(),"mean_pressure_stage_ms":totals[1]/samples.size(),"mean_separate_transport_color_ms":totals[2]/samples.size(),"pressure_packets":packets,"max_fraction_error":error})
		art.release()
		force.release()
		transport.release()
		rd.free_rid(forcing)
		solver.release()
	var result := {"failures":failures,"device":rd.get_device_name(),"results":results,"scope":"32-square local RD GPU timestamps, 10 warmup + up to 60 samples. Sum of separately submitted stages excludes CPU waits, Canvas and main-device scheduling; not utilization."}
	var file := FileAccess.open("res://reports/coupled-benchmark.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("COUPLED_BENCHMARK ",JSON.stringify(result))
	rd.free()
	quit(0 if failures==0 else 1)
