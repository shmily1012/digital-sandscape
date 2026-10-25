extends SceneTree
const Solver=preload("res://experiments/deposition/contact_solver_gpu.gd")
func _initialize() -> void:_run.call_deferred()
func _gpu_ms(rd:RenderingDevice) -> float:
	var first:int=-1
	var last:int=-1
	for i in range(rd.get_captured_timestamps_count()):
		if rd.get_captured_timestamp_name(i)=="begin":first=rd.get_captured_timestamp_gpu_time(i)
		if rd.get_captured_timestamp_name(i)=="end":last=rd.get_captured_timestamp_gpu_time(i)
	return (last-first)/1000000.0 if first>=0 and last>=first else -1.0
func _run() -> void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(2);return
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/contact-cycle-fixtures.json")).cases[0]
	var solver:=Solver.new()
	if not solver.initialize(rd,fixture.initial,fixture.planes):quit(2);return
	var rows:Array=[]
	var trace:=PackedByteArray()
	var force_trace:=PackedByteArray()
	var failure:=0
	for index in range(240):
		var before:=rd.buffer_get_data(solver.output()) # Validation only.
		var gravity:=Vector2(0,1) if index<160 else Vector2(.6,-.8)
		var start:=Time.get_ticks_usec()
		rd.capture_timestamp("begin")
		if not solver.record_step(gravity,.05):failure+=1;break
		if solver.record_step(gravity,.05):failure+=1;break # Single pending transaction.
		rd.capture_timestamp("end")
		rd.submit();rd.sync()
		var gpu_ms:=_gpu_ms(rd)
		if gpu_ms<0:failure+=1
		var status:=rd.buffer_get_data(solver.status_buffer())
		var accepted:=solver.accept(status)
		var batches:Array=[]
		while not accepted and solver.rounds_used<16:
			rd.capture_timestamp("begin")
			if not solver.record_refinement():failure+=1;break
			rd.capture_timestamp("end")
			rd.submit();rd.sync()
			var batch_ms:=_gpu_ms(rd)
			if batch_ms<0:failure+=1
			gpu_ms+=batch_ms
			status=rd.buffer_get_data(solver.status_buffer())
			accepted=solver.accept(status)
			batches.append({"assembly":Array(rd.buffer_get_data(solver.buffers.assembly).to_int32_array()),"svd":Array(rd.buffer_get_data(solver.buffers.svd).to_int32_array()),"backtrack":Array(rd.buffer_get_data(solver.buffers.backtrack).to_int32_array())})
		var elapsed:=Time.get_ticks_usec()-start
		var after:=rd.buffer_get_data(solver.output())
		rows.append({"batches":batches,"step":index+1,"accepted":accepted,"rounds":solver.rounds_used,"status":Array(status.to_int32_array()),"gpu_ms":gpu_ms,"wall_ms":elapsed/1000.0,"unchanged":before==after})
		if not accepted:
			if before!=after:failure+=1
			FileAccess.open("res://reports/refined-cycle-rejected-input.bin",FileAccess.WRITE).store_buffer(before)
			FileAccess.open("res://reports/refined-cycle-rejected-contacts.bin",FileAccess.WRITE).store_buffer(rd.buffer_get_data(solver.contacts[solver.contact_parity]))
			solver.cancel();failure+=1;break
		trace.append_array(after)
		force_trace.append_array(rd.buffer_get_data(solver.contacts[solver.contact_parity]))
	# Cancellation must discard a completed candidate without publishing time/state.
	var saved:=rd.buffer_get_data(solver.output())
	var saved_tick:=solver.tick
	var saved_time:=solver.simulated_time
	if solver.record_step(Vector2(0,1),-1.0):failure+=1
	if not solver.record_step(Vector2(0,1),.05):failure+=1
	if solver.record_refinement(5):failure+=1
	rd.submit();rd.sync()
	var cancelled_status:=rd.buffer_get_data(solver.status_buffer())
	solver.cancel()
	if solver.accept(cancelled_status) or saved!=rd.buffer_get_data(solver.output()) or solver.tick!=saved_tick or solver.simulated_time!=saved_time:failure+=1
	var report:={"accepted":solver.tick,"time":solver.simulated_time,"failures":failure,"steps":rows,"scope":"16 grains, local drag and friction, no liquid feedback; synchronous validation"}
	FileAccess.open("res://reports/refined-cycle-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	FileAccess.open("res://reports/refined-cycle-trace.bin",FileAccess.WRITE).store_buffer(trace)
	FileAccess.open("res://reports/refined-cycle-forces.bin",FileAccess.WRITE).store_buffer(force_trace)
	print("REFINED_CYCLE accepted=",solver.tick," failures=",failure)
	solver.release();rd.free();quit(0 if failure==0 else 1)
