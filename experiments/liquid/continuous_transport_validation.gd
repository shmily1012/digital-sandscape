extends SceneTree

const Solver = preload("res://experiments/liquid/multigrid_gpu.gd")
const Transport = preload("res://experiments/liquid/geometric_gpu.gd")
const Buoyancy = preload("res://experiments/liquid/buoyancy_gpu.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		quit(2)
		return
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://reports/pressure-transport-fixtures.json"))
	var capillary := "--capillary" in OS.get_cmdline_user_args()
	var coupled := "--buoyancy" in OS.get_cmdline_user_args() or capillary
	var sequence_path := "res://reports/buoyancy-sequence.json" if coupled else "res://reports/pressure-transport-sequence.json"
	if capillary:
		sequence_path = "res://reports/capillary-sequence.json"
	var sequence: Array = JSON.parse_string(FileAccess.get_file_as_string(sequence_path))
	var buoyancy := Buoyancy.new()
	if coupled and not buoyancy.initialize(rd):
		quit(2)
		return
	var base: Dictionary = fixtures[0]
	if capillary:
		base.geometry.initial = sequence[0].initial
	var solver := Solver.new()
	var transport := Transport.new()
	if not solver.initialize(rd,base.levels) or not transport.initialize(rd,base.geometry):
		quit(2)
		return
	var forcing := rd.storage_buffer_create(base.faces.size()*16)
	var initial := PackedFloat32Array(base.geometry.initial)
	var failures := 0
	var elapsed := 0.0
	var max_error := 0.0
	var max_area_error := 0.0
	var rows: Array = []
	var captured_rejection := false
	var previous_centroid := 0.0
	var mass := 0.0
	for i in range(initial.size()):
		previous_centroid += initial[i]*(float(i/32)+0.5)/32.0
		mass += initial[i]
	previous_centroid /= mass
	for step: Dictionary in sequence:
		var fixture: Dictionary = {}
		for candidate: Dictionary in fixtures:
			if candidate.name == step.case:
				fixture = candidate
		var data := PackedByteArray()
		data.resize(fixture.faces.size()*16)
		for i in range(fixture.faces.size()):
			var face: Array = fixture.faces[i]
			data.encode_u32(i*16,face[0])
			data.encode_u32(i*16+4,face[1])
			data.encode_float(i*16+8,face[2])
			data.encode_float(i*16+12,face[3])
		if step.case == "nonfinite_velocity":
			data.encode_float(12,NAN)
		rd.buffer_update(forcing,0,data.size(),data)
		var equations := PackedFloat32Array(fixture.levels[0].equations).to_byte_array()
		rd.buffer_update(solver.levels[0].equations,0,equations.size(),equations)
		solver.reset_statistics()
		var before := rd.buffer_get_data(transport.output())
		var compensation := rd.buffer_get_data(transport.buffers[9])
		var list := rd.compute_list_begin()
		if coupled:
			buoyancy.record(list,transport.output(),forcing,transport.buffers[3],solver.levels[0].equations,32,base.faces.size(),Vector2(step.gravity[0],step.gravity[1]),0.02,0.001 if capillary else 0.0,5.0 if capillary else 0.0)
		var pressure: RID = solver.record_adaptive(list,96,2e-6)
		# Experimental Darcy capillary limit: 0.02*h^3/(M*sigma).
		var requested_dt := minf(0.0005,0.02/pow(32.0,3)/0.001) if capillary else 0.02
		if not transport.record_dynamic_step(list,pressure,forcing,solver.control,requested_dt):
			failures += 1
		var parity_before: int = transport.parity
		if transport.record_steps(list,1,0.02) or transport.parity != parity_before:
			failures += 1
		rd.compute_list_end()
		rd.submit()
		rd.sync()
		var status := rd.buffer_get_data(transport.buffers[10])
		var accepted := status.decode_u32(4)==1
		if capillary and not accepted and not captured_rejection:
			captured_rejection = true
			var diagnostic := FileAccess.open("res://reports/capillary-rejected-state.bin",FileAccess.WRITE)
			diagnostic.store_buffer(before)
			diagnostic.close()
			var diagnostic_curvature := FileAccess.open("res://reports/capillary-rejected-curvature.bin",FileAccess.WRITE)
			diagnostic_curvature.store_buffer(rd.buffer_get_data(buoyancy.curvature))
			diagnostic_curvature.close()
		var actual := rd.buffer_get_data(transport.output())
		if accepted != bool(fixture.accepted):
			failures += 1
		if accepted:
			elapsed += status.decode_float(0)/32.0
		elif actual != before or compensation != rd.buffer_get_data(transport.buffers[9]):
			failures += 1
		var error := 0.0
		var area := 0.0
		var centroid := 0.0
		for i in range(1024):
			var value := actual.decode_float(i*4)
			if not is_finite(value) or value < -2e-6 or value > 1+2e-6 or (not base.geometry.active[i] and value != 0):
				failures += 1
			error = maxf(error,absf(value-float(step.expected[i])))
			area += value-initial[i]
			centroid += value*(float(i/32)+0.5)/32.0
		centroid /= mass+area
		if coupled and (centroid-previous_centroid)*float(step.gravity[1]) >= -1e-8:
			failures += 1
		previous_centroid = centroid
		max_error = maxf(max_error,error)
		max_area_error = maxf(max_area_error,absf(area/1024.0))
		if error > 3e-4 or absf(area/1024.0)>1e-6 or absf(elapsed-float(step.elapsed))>1e-6:
			failures += 1
		var control := rd.buffer_get_data(solver.control,0,16)
		rows.append({"case":step.case,"accepted":accepted,"elapsed":elapsed,"error":error,"centroid_y":centroid,"cycles":control.decode_u32(8)})
	var result := {"failures":failures,"steps":rows,"max_fraction_error":max_error,"max_area_error":max_area_error,"device":rd.get_device_name(),"scope":"Persistent pressure and interface buffers; prescribed forcing reversal and injected NaN rejection. Test-only per-step readback. No two-way interface-pressure feedback."}
	if coupled:
		result.scope = "Current GPU gas fraction drives buoyancy, pressure and interface transport each step. No capillary force or grains. Test-only readbacks."
	var report_path := "res://reports/buoyancy-validation.json" if coupled else "res://reports/continuous-transport-validation.json"
	if capillary:
		report_path = "res://reports/capillary-feedback-validation.json"
		result.scope = "Current GPU fractions drive height curvature, residual capillary force, buoyancy, pressure and transport. Short 32-square experiment, no grains or wall contact model."
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("CONTINUOUS_TRANSPORT_RESULT failures=",failures," steps=",rows.size()," error=",max_error," area_error=",max_area_error)
	if coupled:
		buoyancy.release()
	transport.release()
	rd.free_rid(forcing)
	solver.release()
	rd.free()
	quit(0 if failures==0 else 1)
