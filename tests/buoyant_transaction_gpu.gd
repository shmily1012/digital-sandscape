extends SceneTree
const Fluid=preload("res://src/phase_fluid.gd")
const Transaction=preload("res://src/buoyant_loop_transaction.gd")
var failures:Array=[]
func _initialize()->void:call_deferred("run")
func check(condition:bool,label:String)->void:
	if not condition:failures.append(label);push_error(label)
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/buoyant-transaction-fixture.json"))
	var initial:=FileAccess.get_file_as_bytes("res://reports/buoyant-transaction-input.bin")
	var expected:=FileAccess.get_file_as_bytes("res://reports/buoyant-transaction-expected.bin")
	var results:Array=[]
	for item:Dictionary in fixture.cases:
		initial=FileAccess.get_file_as_bytes("res://reports/"+str(item.get("input_file","buoyant-transaction-input.bin")))
		expected=FileAccess.get_file_as_bytes("res://reports/"+str(item.get("expected_file","buoyant-transaction-expected.bin")))
		var gravity:=Vector2(0,.00002)
		if item.has("gravity"):gravity=Vector2(item.gravity[0],item.gravity[1])
		var solver:=Fluid.new()
		var metadata:Dictionary={"side":256,"bytes":initial,"tick":90000,"seed":int(item.get("seed",10)),"with_sand":true,"collective_exchange":false,"weight_scale":1.,"mobility_scale":1.,"wetting_cosine":.5}
		if not solver.restore_energy(rd,metadata):quit(1);return
		var transaction:=Transaction.new()
		if not transaction.initialize(rd,solver,PackedInt32Array(item.path),bool(item.get("automatic",false))):quit(1);return
		var list:=rd.compute_list_begin();transaction.record(list,solver,gravity);rd.compute_list_end();rd.submit();rd.sync()
		var result:=rd.buffer_get_data(transaction.result)
		check((result.decode_u32(4)==1)==bool(item.accepted),item.name+" acceptance")
		check(solver.energy_snapshot_bytes()==(expected if item.accepted else initial),item.name+" full packet state")
		if item.accepted:
			check(absf(result.decode_float(0)-float(item.work))<2e-7,"GPU/CPU work")
			if not item.get("automatic",false):
				list=rd.compute_list_begin();transaction.record(list,solver,gravity);rd.compute_list_end();rd.submit();rd.sync()
				check(rd.buffer_get_data(transaction.result).decode_u32(8)==16,"No second grain movement in same tick")
				check(solver.energy_snapshot_bytes()==expected,"Duplicate dispatch preserves state")
		else:check(result.decode_u32(8)==int(item.reason),item.name+" rejection reason")
		results.append({"name":item.name,"accepted":result.decode_u32(4),"work":result.decode_float(0),"reason":result.decode_u32(8)})
		if item.name=="automatic":
			var times:Array[float]=[]
			for sample in range(35):
				rd.buffer_update(solver.phase[0],0,256*256*4,initial.slice(0,256*256*4))
				rd.buffer_update(solver.distributions[0],0,256*256*36,initial.slice(256*256*4,256*256*40))
				rd.buffer_update(solver.materials,0,256*256*4,initial.slice(256*256*40,256*256*44))
				rd.buffer_update(solver.mass_residual,0,256*256*4,initial.slice(256*256*52,256*256*56))
				rd.buffer_update(solver.grain_energy_stamp,0,256*256*4,initial.slice(256*256*56))
				rd.capture_timestamp("begin_search")
				list=rd.compute_list_begin();transaction.record(list,solver,gravity);rd.compute_list_end()
				rd.capture_timestamp("end_search");rd.submit();rd.sync()
				var begin:=-1;var end:=-1
				for j in range(rd.get_captured_timestamps_count()):
					if rd.get_captured_timestamp_name(j)=="begin_search":begin=rd.get_captured_timestamp_gpu_time(j)
					if rd.get_captured_timestamp_name(j)=="end_search":end=rd.get_captured_timestamp_gpu_time(j)
				if sample>=5 and end>begin and begin>=0:times.append((end-begin)/1000000.)
				check(solver.energy_snapshot_bytes()==expected,"Measured search preserves exact oracle")
				await process_frame
			times.sort();check(times.size()==30,"GPU timestamps available")
			if times.size()==30:results[-1].search_gpu_ms_p95=times[28];results[-1].search_gpu_ms_p50=times[15];results[-1].timing_samples=30
		transaction.release();solver.release()
	var out:=FileAccess.open("res://reports/buoyant-transaction-gpu.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"failures":failures,"results":results,"physical_acceptance":false,"scope":"Explicit and automatic GPU proposals, full packet oracle and reversed gravity. Timing covers one known active column, excludes reset uploads and whole-workload utilization."},"  "));out.close()
	print("BUOYANT_TRANSACTION failures=",failures);rd.free();quit(0 if failures.is_empty() else 1)
