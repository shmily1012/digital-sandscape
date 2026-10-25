extends SceneTree
const Physics=preload("res://src/physics_engine.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(2);return
	var shader:=Physics.compile_shader(rd,"res://experiments/deposition/tangential_history.glsl")
	if not shader.is_valid():quit(2);return
	var pipeline:=rd.compute_pipeline_create(shader)
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/tangential-history-fixtures.json"))
	var n:int=fixture.count
	var initial:=PackedByteArray();initial.resize(n*16)
	for i in range(n):
		initial.encode_s32(i*16,1000+i);initial.encode_s32(i*16+4,2000+i);initial.encode_float(i*16+12,100.)
	var refs:Array[RID]=[rd.storage_buffer_create(initial.size(),initial),rd.storage_buffer_create(n*32),rd.storage_buffer_create(n*16),rd.storage_buffer_create(n*32),rd.storage_buffer_create(n*32),rd.storage_buffer_create(n*4),rd.storage_buffer_create(4)]
	var uniforms:Array[RDUniform]=[]
	for i in range(refs.size()):
		var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(refs[i]);uniforms.append(u)
	var set:=rd.uniform_set_create(uniforms,shader,0)
	var failures:=0;var rows:Array=[]
	for step:Dictionary in fixture.steps:
		var data:=PackedByteArray();data.resize(n*32)
		for i in range(n):
			var v:Array=step.inputs[i]
			data.encode_s32(i*32,int(v[0]));data.encode_s32(i*32+4,int(v[1]))
			for j in range(2,8):data.encode_float(i*32+j*4,float(v[j]))
		# Fault in the last workgroup verifies whole-batch publication gating.
		var at:=(n-1)*32
		match str(step.fault):
			"negative_normal":data.encode_float(at+12,-1.)
			"changed_id":data.encode_s32(at,9000)
			"changed_stiffness":data.encode_float(at+16,200.)
			"nan":data.encode_u32(at+8,0x7fc00000)
		var before:=rd.buffer_get_data(refs[0]);var before_metrics:=rd.buffer_get_data(refs[4])
		rd.buffer_update(refs[1],0,data.size(),data)
		rd.capture_timestamp("spring_begin")
		var list:=rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set,0)
		for phase in range(3):
			var pc:=PackedByteArray();pc.resize(16);pc.encode_u32(0,n);pc.encode_u32(4,phase)
			rd.compute_list_set_push_constant(list,pc,16)
			rd.compute_list_dispatch(list,1 if phase==1 else ceili(float(n)/64.),1,1)
			rd.compute_list_add_barrier(list)
		rd.compute_list_end()
		rd.capture_timestamp("spring_end");rd.submit();rd.sync()
		var start:int=-1;var finish:int=-1
		for stamp in range(rd.get_captured_timestamps_count()):
			if rd.get_captured_timestamp_name(stamp)=="spring_begin":start=rd.get_captured_timestamp_gpu_time(stamp)
			if rd.get_captured_timestamp_name(stamp)=="spring_end":finish=rd.get_captured_timestamp_gpu_time(stamp)
		if start<0 or finish<=start:failures+=1
		var state:=rd.buffer_get_data(refs[0]);var metrics:=rd.buffer_get_data(refs[4])
		var accepted:bool=rd.buffer_get_data(refs[6]).decode_u32(0)==1
		var error:=0.;var metric_error:=0.
		if accepted!=bool(step.accepted):failures+=1
		if not accepted and (state!=before or metrics!=before_metrics):failures+=1
		for i in range(n):
			if state.decode_s32(i*16)!=1000+i or state.decode_s32(i*16+4)!=2000+i:failures+=1
			var xi:=state.decode_float(i*16+8)
			if not is_finite(xi):failures+=1
			error=maxf(error,absf(xi-float(step.expected_xi[i])))
			for j in range(8):
				var value:=metrics.decode_float(i*32+j*4)
				if not is_finite(value):failures+=1
				metric_error=maxf(metric_error,absf(value-float(step.expected_metrics[i][j])))
		if error>2e-6 or metric_error>2e-6:failures+=1
		rows.append({"tick":step.tick,"gpu_ms":float(finish-start)/1e6,"accepted":accepted,"xi_error":error,"metric_error":metric_error})
	var report:={"failures":failures,"contacts":n,"transactions":rows,"scope":"Persistent GPU local spring law, prescribed slip/normal force; not the coupled contact solver"}
	var file:=FileAccess.open("res://reports/tangential-history-gpu.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("TANGENTIAL_HISTORY_RESULT ",JSON.stringify(report))
	rd.free_rid(set)
	for rid in refs:rd.free_rid(rid)
	rd.free_rid(pipeline);rd.free_rid(shader);rd.free();quit(0 if failures==0 else 1)
