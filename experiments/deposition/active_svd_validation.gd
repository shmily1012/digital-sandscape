extends SceneTree
const Physics=preload("res://src/physics_engine.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:
		quit(2)
		return
	var shader:=Physics.compile_shader(rd,"res://experiments/deposition/active_svd.glsl")
	if not shader.is_valid():
		quit(2)
		return
	var pipeline:=rd.compute_pipeline_create(shader)
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/active-svd-fixtures.json"))
	var failures:=0
	var rows:Array=[]
	for test:Dictionary in fixture.cases:
		var n:int=test.size
		var buffers:Array[RID]=[]
		for values:Array in [test.matrix,test.rhs]:
			var bytes:=PackedFloat32Array(values).to_byte_array()
			buffers.append(rd.storage_buffer_create(bytes.size(),bytes))
		buffers.append(rd.storage_buffer_create(n*4))
		buffers.append(rd.storage_buffer_create(16))
		buffers.append(rd.storage_buffer_create(n*4))
		buffers.append(rd.storage_buffer_create(16))
		var uniforms:Array[RDUniform]=[]
		for binding in range(6):
			var u:=RDUniform.new()
			u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.binding=binding
			u.add_id(buffers[binding])
			uniforms.append(u)
		var uniform_set:=rd.uniform_set_create(uniforms,shader,0)
		var params:=PackedByteArray();params.resize(16)
		params.encode_u32(0,n);params.encode_u32(4,16);params.encode_float(8,1e-6)
		rd.capture_timestamp("svd_begin")
		var list:=rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list,pipeline)
		rd.compute_list_bind_uniform_set(list,uniform_set,0)
		rd.compute_list_set_push_constant(list,params,16)
		rd.compute_list_dispatch(list,1,1,1)
		rd.compute_list_add_barrier(list)
		rd.compute_list_end()
		rd.capture_timestamp("svd_finish")
		rd.submit()
		rd.sync()
		var start:int=-1;var end:int=-1
		for i in range(rd.get_captured_timestamps_count()):
			if rd.get_captured_timestamp_name(i)=="svd_begin":start=rd.get_captured_timestamp_gpu_time(i)
			if rd.get_captured_timestamp_name(i)=="svd_finish":end=rd.get_captured_timestamp_gpu_time(i)
		if start<0 or end<=start: failures+=1
		var x:=rd.buffer_get_data(buffers[2]).to_float32_array()
		var null_v:=rd.buffer_get_data(buffers[4]).to_float32_array()
		var rank:=rd.buffer_get_data(buffers[3]).decode_u32(0)
		var difference:=0.0;var magnitude:=0.0;var null_error:=0.0;var norm:=0.0
		for i in range(n):
			if not is_finite(x[i]) or not is_finite(null_v[i]): failures+=1
			difference=maxf(difference,absf(x[i]-float(test.expected[i])))
			magnitude=maxf(magnitude,absf(float(test.expected[i])))
			norm+=null_v[i]*null_v[i]
			var product:=0.0
			for j in range(n): product+=float(test.matrix[i*n+j])*null_v[j]
			null_error=maxf(null_error,absf(product))
		var relative_error:=difference/maxf(magnitude,1e-12)
		if rank!=int(test.rank) or relative_error>1e-3 or absf(norm-1)>1e-4 or (rank<n and null_error>1e-3): failures+=1
		rows.append({"name":test.name,"rank":rank,"relative_solution_error":relative_error,"null_residual":null_error,"gpu_ms":float(end-start)/1e6})
		rd.free_rid(uniform_set)
		for rid in buffers:rd.free_rid(rid)
	var report:={"failures":failures,"systems":rows,"scope":"Four captured 30x30 systems and four independent matrices up to 32x32; float32 Jacobi SVD, no integrated contact fallback."}
	var file:=FileAccess.open("res://reports/active-svd-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("ACTIVE_SVD_RESULT ",JSON.stringify(report))
	rd.free_rid(pipeline);rd.free_rid(shader);rd.free()
	quit(0 if failures==0 else 1)
