extends SceneTree
const Fluid=preload("res://src/phase_fluid.gd")
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	if not value:failures.append(message);push_error(message)
func make(rd:RenderingDevice,n:int,fields:Dictionary,gated:bool)->RefCounted:
	var solver:=Fluid.new();solver.grain_collective_gate_enabled=gated;solver.grain_wetting_cosine=.5
	if not solver.initialize(rd,n,fields.gas,fields.walls,PackedVector2Array(),true,20261024):return null
	if not solver.initialize_collective_exchange():return null
	return solver
func record(rd:RenderingDevice,solver:RefCounted,gravity:Vector2)->void:
	var list:=rd.compute_list_begin();solver.record_collective_exchange(list,0,gravity,.01);rd.compute_list_end()
func same(rd:RenderingDevice,a:RefCounted,b:RefCounted)->bool:
	# Only parity zero evolves in this isolated kernel test; tick is its RNG key.
	for pair in [[a.phase[0],b.phase[0]],[a.materials,b.materials],[a.distributions[0],b.distributions[0]],[a.mass_residual,b.mass_residual],[a.grain_energy_stamp,b.grain_energy_stamp]]:
		if rd.buffer_get_data(pair[0])!=rd.buffer_get_data(pair[1]):return false
	return true
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://reports/grain-collective-fixture.json"))
	for case:Dictionary in fixtures:
		var solver:=make(rd,int(case.side),{"gas":PackedFloat32Array(case.phase),"walls":PackedInt32Array(case.materials)},true)
		if solver==null:quit(1);return
		record(rd,solver,Vector2(case.gravity[0],case.gravity[1]));rd.submit();rd.sync()
		var args:=rd.buffer_get_data(solver.grain_collective_dispatch).to_int32_array()
		check(args[3]==int(case.expected_initial_activity),"CPU/GPU activity count")
		check((args[0]==0 and args[1]==0 and args[2]==0)==(args[3]==0),"Indirect dimensions")
		solver.release()
	# A wall-supported chain sleeps, wakes under reversal, then sleeps in zero gravity.
	var fields:=Fluid.contact_fields(128,0,false)
	for y in range(122,126):fields.walls[y*128+64]=2
	var baseline:=make(rd,128,fields,false);var gated:=make(rd,128,fields,true)
	if baseline==null or gated==null:quit(1);return
	var activity:Array=[]
	for tick in range(48):
		var gravity:=Vector2(0,.00002) if tick<12 else (Vector2(0,-.00002) if tick<36 else Vector2.ZERO)
		baseline.tick=tick;gated.tick=tick
		record(rd,baseline,gravity);record(rd,gated,gravity);rd.submit();rd.sync()
		check(same(rd,baseline,gated),"Sleep/wake changed state at tick %d"%tick)
		var args:=rd.buffer_get_data(gated.grain_collective_dispatch).to_int32_array();activity.append(args[3])
		if tick<12 or tick>=36:check(args==PackedInt32Array([0,0,0,0]),"Idle dispatch not cleared")
	check(activity.slice(12,36).max()>0,"Gravity reversal failed to wake")
	baseline.release();gated.release()
	var benchmarks:Array=[]
	for scenario in ["settled","active"]:
		var n:=256;fields=Fluid.contact_fields(n,0,false)
		for i in range(n*n):
			if fields.walls[i]!=0:continue
			if scenario=="settled" and i/n>=128:fields.walls[i]=2+i%3
			if scenario=="active" and i%n>=32 and i%n<224 and i%n%8==0 and i/n>=88 and i/n<96:fields.walls[i]=2+i%3
		baseline=make(rd,n,fields,false);gated=make(rd,n,fields,true)
		if baseline==null or gated==null:quit(1);return
		var samples:Dictionary={"baseline":[],"gated":[]};var active_samples:Array=[]
		for tick in range(70):
			baseline.tick=tick;gated.tick=tick
			var order:Array=["baseline","gated"] if tick%2==0 else ["gated","baseline"]
			for name:String in order:
				rd.capture_timestamp(name+"_begin");record(rd,baseline if name=="baseline" else gated,Vector2(0,.00002));rd.capture_timestamp(name+"_end")
			rd.submit();rd.sync()
			var timings:Dictionary={}
			for index in range(rd.get_captured_timestamps_count()):timings[rd.get_captured_timestamp_name(index)]=rd.get_captured_timestamp_gpu_time(index)
			if tick>=10:
				for name:String in ["baseline","gated"]:
					if not timings.has(name+"_begin") or not timings.has(name+"_end"):check(false,"Missing GPU timestamps");continue
					var elapsed:float=(timings[name+"_end"]-timings[name+"_begin"])/1000000.
					check(elapsed>0.,"Invalid GPU timestamp interval");samples[name].append(elapsed)
				active_samples.append(rd.buffer_get_data(gated.grain_collective_dispatch).decode_u32(12))
			await process_frame
		check(same(rd,baseline,gated),scenario+" benchmark state changed")
		var result:Dictionary={"scenario":scenario,"side":n,"eligible_sources_min":active_samples.min(),"eligible_sources_max":active_samples.max()}
		if scenario=="settled":check(active_samples.max()==0,"Settled scenario was active")
		else:check(active_samples.min()>0,"Active scenario was not active")
		for name:String in ["baseline","gated"]:
			samples[name].sort();var values:Array=samples[name]
			if values.size()!=60:check(false,"Incomplete benchmark");continue
			result[name]={"p50_ms":values[30],"p95_ms":values[56],"samples":60}
		benchmarks.append(result);baseline.release();gated.release()
	var report:Dictionary={"failures":failures,"activity_counts":activity,"fixtures":fixtures.size(),"benchmarks":benchmarks,"device":rd.get_device_name(),"scope":"Isolated collective stage, alternating baseline/gated order, 10 warmups and 60 paired samples; excludes fluid, single-grain, rendering and utilization. No CPU readback in production scheduling."}
	var file:=FileAccess.open("res://reports/collective-activity-gpu.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("COLLECTIVE_ACTIVITY ",report);rd.free();quit(0 if failures.is_empty() else 1)
