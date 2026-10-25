extends SceneTree

const Solver = preload("res://experiments/liquid/multigrid_gpu.gd")
const Transport = preload("res://experiments/liquid/geometric_gpu.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		quit(2)
		return
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://reports/pressure-transport-fixtures.json"))
	var failures := 0
	var cases: Array = []
	for fixture: Dictionary in fixtures:
		var solver := Solver.new()
		var transport := Transport.new()
		if not solver.initialize(rd,fixture.levels) or not transport.initialize(rd,fixture.geometry):
			quit(2)
			return
		var forcing_data := PackedByteArray()
		forcing_data.resize(fixture.faces.size()*16)
		for i in range(fixture.faces.size()):
			var face: Array = fixture.faces[i]
			forcing_data.encode_u32(i*16,face[0])
			forcing_data.encode_u32(i*16+4,face[1])
			forcing_data.encode_float(i*16+8,face[2])
			forcing_data.encode_float(i*16+12,face[3])
		if fixture.name == "nonfinite_velocity":
			forcing_data.encode_float(12,NAN)
		var forcing := rd.storage_buffer_create(forcing_data.size(),forcing_data)
		var initial := PackedFloat32Array(fixture.geometry.initial).to_byte_array()
		var initial_compensation := rd.buffer_get_data(transport.buffers[9])
		var list := rd.compute_list_begin()
		var pressure: RID = solver.record_adaptive(list,int(fixture.budget),2e-6)
		if not transport.record_dynamic_step(list,pressure,forcing,solver.control,fixture.requested_dt):
			failures += 1
		rd.compute_list_end()
		rd.submit()
		rd.sync()
		var status := rd.buffer_get_data(transport.buffers[10])
		var actual := rd.buffer_get_data(transport.output())
		var accepted := status.decode_u32(4)==1
		var dt := status.decode_float(0)/32.0
		var error := 0.0
		var area_error := 0.0
		var minimum := INF
		var maximum := -INF
		for i in range(1024):
			var value := actual.decode_float(i*4)
			if not is_finite(value) or (not fixture.geometry.active[i] and value != 0):
				failures += 1
			error = maxf(error,absf(value-float(fixture.expected[i])))
			area_error += value-initial.decode_float(i*4)
			minimum = minf(minimum,value)
			maximum = maxf(maximum,value)
		area_error /= 1024.0
		if accepted != bool(fixture.accepted) or absf(dt-float(fixture.expected_dt))>1e-5 or error>3e-4 or absf(area_error)>1e-6 or minimum < -2e-6 or maximum>1+2e-6:
			failures += 1
		if not accepted and (actual != initial or rd.buffer_get_data(transport.buffers[9]) != initial_compensation):
			failures += 1
		var pressure_status := rd.buffer_get_data(solver.control,0,16)
		var divergence := status.decode_float(8)
		cases.append({"name":fixture.name,"accepted":accepted,"dt":dt,"cpu_dt":fixture.expected_dt,"max_fraction_error":error,"gas_area_error":area_error,"minimum":minimum,"maximum":maximum,"face_divergence":divergence if is_finite(divergence) else "nonfinite","pressure_cycles":pressure_status.decode_u32(8),"pressure_converged":pressure_status.decode_u32(4)==1})
		transport.release()
		rd.free_rid(forcing)
		solver.release()
	var result := {"failures":failures,"device":rd.get_device_name(),"cases":cases,"scope":"Single GPU command chain: externally supplied pressure RHS, multigrid, face velocity, dynamic CFL/divergence gate and two-phase transport. No intermediate CPU readback, no capillary/grain forcing generation."}
	var report := FileAccess.open("res://reports/pressure-transport-validation.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(result,"  "))
	report.close()
	print("PRESSURE_TRANSPORT_RESULT ",JSON.stringify(result))
	rd.free()
	quit(0 if failures==0 else 1)
