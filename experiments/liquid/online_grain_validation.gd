extends SceneTree
const Grains = preload("res://experiments/liquid/online_grains.gd")
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd==null:
		quit(2)
		return
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/online-grain-fixtures.json"))
	var too_many: Array = []
	for i in range(9): too_many.append(fixture.initial[0])
	var guard := Grains.new()
	if guard.initialize(rd,fixture.base,too_many):
		quit(2)
		return
	var model := Grains.new()
	if not model.initialize(rd,fixture.base,fixture.initial):
		quit(2)
		return
	var failures := 0
	var batched := "--batched" in OS.get_cmdline_user_args()
	var initial := rd.buffer_get_data(model.output())
	model.advance(Vector2.DOWN,0.02,1)
	rd.submit()
	rd.sync()
	var budget_retained := rd.buffer_get_data(model.output())==initial
	if not budget_retained or rd.buffer_get_data(model.status()).decode_u32(4)!=1: failures += 1
	var rows: Array = []
	for step: Dictionary in fixture.sequence:
		var retained_state := rd.buffer_get_data(model.output())
		var total_ms := 0.0
		var accepted := false
		var attempts := 0
		for attempt in range(12 if batched else 1):
			attempts += 1
			rd.capture_timestamp("begin")
			if not model.advance(Vector2(step.gravity[0],step.gravity[1]),step.dt,8 if batched else 96): failures += 1
			rd.capture_timestamp("end")
			rd.submit()
			rd.sync()
			var begin := -1
			var end := -1
			for i in range(rd.get_captured_timestamps_count()):
				if rd.get_captured_timestamp_name(i)=="begin": begin=rd.get_captured_timestamp_gpu_time(i)
				if rd.get_captured_timestamp_name(i)=="end": end=rd.get_captured_timestamp_gpu_time(i)
			if begin<0 or end<begin: failures += 1
			else: total_ms += float(end-begin)/1e6
			var summary := rd.buffer_get_data(model.status())
			accepted = summary.decode_u32(0)==1
			if accepted: break
			if rd.buffer_get_data(model.output())!=retained_state: failures += 1
			if summary.decode_u32(4)!=1: break
		if not accepted: failures += 1
		var actual := rd.buffer_get_data(model.output())
		var k := rd.buffer_get_data(model.buffers[7])
		var valid := rd.buffer_get_data(model.buffers[9]).decode_u32(0)==1
		var error := 0.0
		var calibration_error := 0.0
		for i in range(fixture.initial.size()):
			var x := actual.decode_float(i*32)
			var y := actual.decode_float(i*32+4)
			if not is_finite(x) or not is_finite(y): failures += 1
			error=maxf(error,maxf(absf(x-float(step.expected[i].x)),absf(y-float(step.expected[i].y))))
			if actual.slice(i*32+8,i*32+32)!=initial.slice(i*32+8,i*32+32): failures += 1
			for j in range(4):
				var value := k.decode_float(i*16+j*4)
				if not is_finite(value): failures += 1
				calibration_error=maxf(calibration_error,absf(value-float(step.self_response[i][j])))
		if not valid or error>2e-6 or calibration_error>0.01: failures += 1
		rows.append({"position_error":error,"self_response_error":calibration_error,"positive_mobility":valid,"single_step_gpu_ms":total_ms,"attempts":attempts})
	model.release()
	var dense := [fixture.initial[0].duplicate(),fixture.initial[0].duplicate()]
	dense[0].x=0.5
	dense[0].y=0.5
	dense[1].x=0.5
	dense[1].y=0.5
	model = Grains.new()
	model.initialize(rd,fixture.base,dense)
	var dense_before := rd.buffer_get_data(model.output())
	model.advance(Vector2.DOWN,0.02)
	rd.submit()
	rd.sync()
	var dense_retained := rd.buffer_get_data(model.output())==dense_before and rd.buffer_get_data(model.buffers[9]).decode_u32(0)==0 and rd.buffer_get_data(model.status()).decode_u32(4)==3
	if not dense_retained: failures += 1
	model.release()
	var report := {"failures":failures,"budget_retained":budget_retained,"negative_mobility_rejected":dense_retained,"steps":rows,"scope":"GPU recalibrates each current particle position with 2N pressure solves, then certifies corrected mobility and advances. Maximum 8 particles, no intermediate CPU state readback; expensive reference only."}
	report["batched"] = batched
	var file := FileAccess.open("res://reports/batched-grain-validation.json" if batched else "res://reports/online-grain-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("ONLINE_GRAINS_RESULT ",JSON.stringify(report))
	rd.free()
	quit(0 if failures==0 else 1)
