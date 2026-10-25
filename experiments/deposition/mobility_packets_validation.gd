extends SceneTree
const Online=preload("res://experiments/liquid/online_grains.gd")
const Packets=preload("res://experiments/deposition/mobility_packets_gpu.gd")
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(2);return
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/calibrated-contact-fixtures.json"))
	var test:Dictionary=fixture.cases[3]
	var baseline:=Online.new()
	if not baseline.initialize(rd,fixture.base,test.grains):quit(2);return
	baseline.record_mobility(96);rd.submit();rd.sync()
	var expected:=rd.buffer_get_data(baseline.buffers[8])
	var failures:=0
	if rd.buffer_get_data(baseline.buffers[9]).decode_u32(0)!=1:failures+=1
	var cpu_error:=0.0
	for i in range(test.matrix.size()):
		for j in range(test.matrix.size()):
			var value:=expected.decode_float((i*test.matrix.size()+j)*4)
			if not is_finite(value):failures+=1
			cpu_error=maxf(cpu_error,absf(value-test.matrix[i][j]))
	if cpu_error>0.001:failures+=1
	baseline.release()
	var rows:Array=[]
	for scenario:Dictionary in [{"name":"eight_cycles","batch":8,"budget":96},{"name":"one_cycle","batch":1,"budget":96},{"name":"exhausted","batch":1,"budget":1},{"name":"cancelled","batch":8,"budget":96}]:
		var online:=Online.new()
		if not online.initialize(rd,fixture.base,test.grains):quit(2);return
		var initial:=rd.buffer_get_data(online.output())
		var job:=Packets.new();job.initialize(online)
		if not job.start(scenario.budget,scenario.batch):failures+=1
		var timings:Array[float]=[]
		var readback_bytes:=0
		for packet in range(2*online.count*(scenario.budget+1)+1):
			if job.state not in ["solve","capture"]:break
			rd.capture_timestamp("begin")
			if not job.record_next():failures+=1;break
			if job.record_next() or job.start() or job.cancel():failures+=1
			rd.capture_timestamp("end");rd.submit();rd.sync()
			var first:int=-1;var last:int=-1
			for i in range(rd.get_captured_timestamps_count()):
				if rd.get_captured_timestamp_name(i)=="begin":first=rd.get_captured_timestamp_gpu_time(i)
				if rd.get_captured_timestamp_name(i)=="end":last=rd.get_captured_timestamp_gpu_time(i)
			if first<0 or last<first:failures+=1
			timings.append((last-first)/1000000.0)
			var status:=rd.buffer_get_data(job.status_rid,0,job.status_size);readback_bytes+=status.size()
			job.consume(status)
			if scenario.name=="cancelled":
				if not job.cancel():failures+=1
				break
		var wanted:="failed" if scenario.name=="exhausted" else ("cancelled" if scenario.name=="cancelled" else "done")
		if job.state!=wanted or rd.buffer_get_data(online.output())!=initial:failures+=1
		var certificate:=rd.buffer_get_data(online.buffers[9]).decode_u32(0)
		var error:=0.0
		if wanted=="done":
			var matrix:=rd.buffer_get_data(online.buffers[8])
			for i in range(expected.size()/4):error=maxf(error,absf(matrix.decode_float(i*4)-expected.decode_float(i*4)))
			if error>0.001 or certificate!=1:failures+=1
		elif certificate!=0:failures+=1
		rows.append({"name":scenario.name,"state":job.state,"packets":job.packets,"matrix_error":error,"status_bytes":readback_bytes,"gpu_packet_max_ms":timings.max(),"gpu_total_ms":timings.reduce(func(a:float,b:float):return a+b,0.0)})
		online.release()
	var report:={"cpu_matrix_error":cpu_error,"failures":failures,"cases":rows,"scope":"bounded GPU calibration packets; synchronous harness, not yet main-device async joint simulation"}
	FileAccess.open("res://reports/mobility-packets-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MOBILITY_PACKETS ",JSON.stringify(report));rd.free();quit(0 if failures==0 else 1)
