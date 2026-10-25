extends SceneTree
const Coupled=preload("res://experiments/deposition/coupled_contact_gpu.gd")
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(2);return
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/coupled-cycle-fixtures.json"))
	var model:=Coupled.new()
	if not model.initialize(rd,fixture.base,fixture.initial,fixture.planes):quit(2);return
	var failures:=0
	var rows:Array=[]
	var traces:={"particles":PackedByteArray(),"forces":PackedByteArray(),"matrix":PackedByteArray(),"net":PackedByteArray(),"flux":PackedByteArray()}
	var recovery_tested:=false
	for index in range(fixture.steps.size()):
		var step:Dictionary=fixture.steps[index]
		var gravity:=Vector2(step.gravity[0],step.gravity[1])
		var before:=rd.buffer_get_data(model.output())
		var before_flux:=rd.buffer_get_data(model.flux())
		if index==60:
			var previous_time:=model.simulated_time
			model.record_step(gravity,fixture.dt,96,1)
			rd.submit();rd.sync()
			var rejected:=not model.complete(rd.buffer_get_data(model.status_buffer()))
			recovery_tested=rejected and rd.buffer_get_data(model.output())==before and rd.buffer_get_data(model.flux())==before_flux and model.simulated_time==previous_time
			if not recovery_tested:failures+=1;break
		rd.capture_timestamp("begin")
		if not model.record_step(gravity,fixture.dt):failures+=1;break
		if model.record_step(gravity,fixture.dt):failures+=1;break
		rd.capture_timestamp("end");rd.submit();rd.sync()
		var first:int=-1;var last:int=-1
		for i in range(rd.get_captured_timestamps_count()):
			if rd.get_captured_timestamp_name(i)=="begin":first=rd.get_captured_timestamp_gpu_time(i)
			if rd.get_captured_timestamp_name(i)=="end":last=rd.get_captured_timestamp_gpu_time(i)
		if first<0 or last<first:failures+=1
		var accepted:=model.complete(rd.buffer_get_data(model.status_buffer()))
		var state:=rd.buffer_get_data(model.output())
		var error:=0.0
		for i in range(model.count):
			error=maxf(error,Vector2(state.decode_float(i*32)-step.expected[i].x,state.decode_float(i*32+4)-step.expected[i].y).length())
			if state.slice(i*32+8,i*32+32)!=before.slice(i*32+8,i*32+32):failures+=1
		rows.append({"step":index+1,"accepted":accepted,"position_error":error,"gpu_ms":(last-first)/1000000.0,"contact_status":Array(rd.buffer_get_data(model.buffers[3]).to_int32_array()),"pressure_status":Array(rd.buffer_get_data(model.online.solvers[-1].control).to_int32_array())})
		if not accepted or error>2e-6:
			failures+=1
			var main=model.online.solvers[-1]
			FileAccess.open("res://reports/coupled-rejected-faces.bin",FileAccess.WRITE).store_buffer(rd.buffer_get_data(model.online.buffers[4]))
			FileAccess.open("res://reports/coupled-rejected-pressure.bin",FileAccess.WRITE).store_buffer(rd.buffer_get_data(main.levels[0].p[main.levels[0].parity]))
			if not accepted and (state!=before or rd.buffer_get_data(model.flux())!=before_flux):failures+=1
			break
		traces.particles.append_array(state)
		traces.forces.append_array(rd.buffer_get_data(model.buffers[2]))
		traces.matrix.append_array(rd.buffer_get_data(model.online.buffers[8]))
		traces.net.append_array(rd.buffer_get_data(model.feedback.buffers[3]))
		traces.flux.append_array(rd.buffer_get_data(model.flux()))
	for key in traces:FileAccess.open("res://reports/coupled-cycle-"+key+".bin",FileAccess.WRITE).store_buffer(traces[key])
	var report:={"failures":failures,"accepted":model.tick,"time":model.simulated_time,"recovery_tested":recovery_tested,"steps":rows,"scope":"80-step persistent two-grain GPU pressure/contact/feedback cycle; no gas or dense volume exclusion"}
	FileAccess.open("res://reports/coupled-cycle-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("COUPLED_CYCLE accepted=",model.tick," failures=",failures," recovery=",recovery_tested)
	model.release();rd.free();quit(0 if failures==0 else 1)
