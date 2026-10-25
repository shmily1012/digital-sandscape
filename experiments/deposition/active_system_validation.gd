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
	var assembly:=Physics.compile_shader(rd,"res://experiments/deposition/active_system.glsl")
	if not assembly.is_valid():
		quit(2)
		return
	var assembly_pipeline:=rd.compute_pipeline_create(assembly)
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/active-system-fixture.json"))
	var fixture:Dictionary={"cases":[source.duplicate(true),source.duplicate(true)]}
	fixture.cases[0]["name"]="captured_network"
	fixture.cases[1]["name"]="active_capacity_rejected"
	var failures:=0
	var rows:Array=[]
	for test:Dictionary in fixture.cases:
		var n:int=32
		var buffers:Array[RID]=[]
		for length in [1024,32]:
			var zeros:=PackedFloat32Array();zeros.resize(length)
			var bytes:=zeros.to_byte_array()
			buffers.append(rd.storage_buffer_create(bytes.size(),bytes))
		buffers.append(rd.storage_buffer_create(n*4))
		buffers.append(rd.storage_buffer_create(16))
		buffers.append(rd.storage_buffer_create(n*4))
		var particles:=PackedFloat32Array()
		for g:Dictionary in test.grains:particles.append_array(PackedFloat32Array([g.x,g.y,g.radius,g.drag,g.density,g.material,0,0]))
		buffers.append(rd.storage_buffer_create(particles.size()*4,particles.to_byte_array())) # 5
		var contacts:=PackedByteArray();contacts.resize(test.contacts.size()*48)
		for k in range(test.contacts.size()):
			var c:Array=test.contacts[k]
			contacts.encode_float(k*48,c[2]);contacts.encode_float(k*48+4,c[3]);contacts.encode_float(k*48+8,c[4])
			var mobility:float=1.0/float(test.grains[int(c[0])].drag)
			if int(c[1])>=0:mobility+=1.0/float(test.grains[int(c[1])].drag)
			contacts.encode_float(k*48+12,mobility)
			contacts.encode_s32(k*48+16,int(c[0]));contacts.encode_s32(k*48+20,int(c[1]))
			contacts.encode_float(k*48+32,1.0 if test.name=="active_capacity_rejected" else float(c[5]))
			contacts.encode_float(k*48+36,c[6])
		buffers.append(rd.storage_buffer_create(contacts.size(),contacts)) # 6
		buffers.append(rd.storage_buffer_create(64)) # 7 selection
		buffers.append(rd.storage_buffer_create(16)) # 8 metadata
		var assembly_uniforms:Array[RDUniform]=[]
		var refs:=[buffers[5],buffers[6],buffers[0],buffers[1],buffers[7],buffers[8]]
		for binding in range(6):
			var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=binding;u.add_id(refs[binding]);assembly_uniforms.append(u)
		var assembly_set:=rd.uniform_set_create(assembly_uniforms,assembly,0)
		var assembly_params:=PackedByteArray();assembly_params.resize(32)
		assembly_params.encode_u32(0,test.grains.size());assembly_params.encode_u32(4,test.contacts.size())
		assembly_params.encode_float(8,test.dt);assembly_params.encode_float(12,.5)
		assembly_params.encode_float(16,test.gravity[0]);assembly_params.encode_float(20,test.gravity[1]);assembly_params.encode_float(24,1e-7)
		var uniforms:Array[RDUniform]=[]
		for binding in range(6):
			var u:=RDUniform.new()
			u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.binding=binding
			u.add_id(buffers[8] if binding==5 else buffers[binding])
			uniforms.append(u)
		var uniform_set:=rd.uniform_set_create(uniforms,shader,0)
		var params:=PackedByteArray();params.resize(16)
		params.encode_u32(0,n);params.encode_u32(4,16);params.encode_float(8,1e-6);params.encode_u32(12,1)
		rd.capture_timestamp("svd_begin")
		var list:=rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list,assembly_pipeline)
		rd.compute_list_bind_uniform_set(list,assembly_set,0)
		rd.compute_list_set_push_constant(list,assembly_params,32)
		rd.compute_list_dispatch(list,1,1,1)
		rd.compute_list_add_barrier(list)
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
		var construction:=rd.buffer_get_data(buffers[8])
		var matrix_data:=rd.buffer_get_data(buffers[0]).to_float32_array()
		var rhs_data:=rd.buffer_get_data(buffers[1]).to_float32_array()
		var matrix_error:=0.0;var rhs_error:=0.0
		for k in range(1024):matrix_error=maxf(matrix_error,absf(matrix_data[k]-float(test.matrix[k])))
		for k in range(32):rhs_error=maxf(rhs_error,absf(rhs_data[k]-float(test.rhs[k])))
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
		if rd.buffer_get_data(buffers[5])!=particles.to_byte_array() or rd.buffer_get_data(buffers[6])!=contacts: failures+=1
		if test.name=="captured_network":
			var selected:=rd.buffer_get_data(buffers[7])
			for k in range(test.selected_contacts.size()):
				if selected.decode_u32(k*4)!=int(test.selected_contacts[k]):failures+=1
			if construction.decode_u32(0)!=1 or construction.decode_u32(4)!=15 or rank!=int(test.rank) or difference>2e-8 or matrix_error>1e-4 or rhs_error>2e-7: failures+=1
		else:
			if construction.decode_u32(0)!=0 or construction.decode_u32(12)!=2 or rd.buffer_get_data(buffers[3]).decode_u32(12)!=1:failures+=1
		rows.append({"name":test.name,"rank":rank,"active_count":construction.decode_u32(4),"assembly_valid":construction.decode_u32(0)==1,"matrix_error":matrix_error,"rhs_error":rhs_error,"absolute_direction_error":difference,"relative_solution_error":relative_error,"null_residual":null_error,"gpu_ms":float(end-start)/1e6})
		rd.free_rid(assembly_set)
		rd.free_rid(uniform_set)
		for rid in buffers:rd.free_rid(rid)
	var report:={"failures":failures,"systems":rows,"scope":"Current checkpoint forces assembled on GPU then passed directly to SVD; no CPU matrix upload or intermediate readback. Still no line search or state commit."}
	var file:=FileAccess.open("res://reports/active-system-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("ACTIVE_SYSTEM_RESULT ",JSON.stringify(report))
	rd.free_rid(assembly_pipeline);rd.free_rid(assembly)
	rd.free_rid(pipeline);rd.free_rid(shader);rd.free()
	quit(0 if failures==0 else 1)
