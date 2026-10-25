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
	var backtrack:=Physics.compile_shader(rd,"res://experiments/deposition/active_backtrack.glsl")
	if not backtrack.is_valid():
		quit(2)
		return
	var backtrack_pipeline:=rd.compute_pipeline_create(backtrack)
	var commit:=Physics.compile_shader(rd,"res://experiments/deposition/active_commit.glsl")
	if not commit.is_valid():
		quit(2)
		return
	var commit_pipeline:=rd.compute_pipeline_create(commit)
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/active-system-fixture.json"))
	var fixture:Dictionary={"cases":[source.duplicate(true),source.duplicate(true),source.duplicate(true)]}
	fixture.cases[0]["name"]="captured_network"
	fixture.cases[1]["name"]="active_capacity_rejected"
	fixture.cases[2]["name"]="insufficient_refinement_budget"
	var failures:=0
	var rows:Array=[]
	for test:Dictionary in fixture.cases:
		var rounds:int=1 if test.name=="insufficient_refinement_budget" else 8
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
		buffers.append(rd.storage_buffer_create(contacts.size(),contacts)) # 9 work A
		buffers.append(rd.storage_buffer_create(contacts.size(),contacts)) # 10 work B
		var chain_sets:Array[RID]=[]
		var construction_sets:Array[RID]=[]
		for parity in range(2):
			construction_sets.append(_make_set(rd,assembly,[buffers[5],buffers[9+parity],buffers[0],buffers[1],buffers[7],buffers[8]]))
		for step in range(8):
			buffers.append(rd.storage_buffer_create(32))
			chain_sets.append(_make_set(rd,backtrack,[buffers[5],buffers[9+step%2],buffers[7],buffers[8],buffers[2],buffers[3],buffers[4],buffers[9+(1-step%2)],buffers[11+step]]))
		buffers.append(rd.storage_buffer_create(particles.size()*4)) # 19 committed
		buffers.append(rd.storage_buffer_create(16)) # 20 commit status
		var commit_set:=_make_set(rd,commit,[buffers[5],buffers[9+rounds%2],buffers[19],buffers[20],buffers[8]])
		rd.capture_timestamp("svd_begin")
		var list:=rd.compute_list_begin()
		for step in range(rounds):
			rd.compute_list_bind_compute_pipeline(list,assembly_pipeline)
			rd.compute_list_bind_uniform_set(list,construction_sets[step%2],0)
			rd.compute_list_set_push_constant(list,assembly_params,32)
			rd.compute_list_dispatch(list,1,1,1)
			rd.compute_list_add_barrier(list)
			rd.compute_list_bind_compute_pipeline(list,pipeline)
			rd.compute_list_bind_uniform_set(list,uniform_set,0)
			rd.compute_list_set_push_constant(list,params,16)
			rd.compute_list_dispatch(list,1,1,1)
			rd.compute_list_add_barrier(list)
			rd.compute_list_bind_compute_pipeline(list,backtrack_pipeline)
			rd.compute_list_bind_uniform_set(list,chain_sets[step],0)
			rd.compute_list_set_push_constant(list,assembly_params,32)
			rd.compute_list_dispatch(list,1,1,1)
			rd.compute_list_add_barrier(list)
		rd.compute_list_bind_compute_pipeline(list,commit_pipeline)
		rd.compute_list_bind_uniform_set(list,commit_set,0)
		rd.compute_list_set_push_constant(list,assembly_params,32)
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
		var history:Array=[]
		for step in range(rounds):
			var data:=rd.buffer_get_data(buffers[11+step])
			history.append({"mode":data.decode_u32(0),"attempts":data.decode_u32(4),"before":data.decode_float(8),"after":data.decode_float(12),"merit_before":data.decode_float(16),"merit_after":data.decode_float(20),"alpha":data.decode_float(24)})
		if rd.buffer_get_data(buffers[5])!=particles.to_byte_array() or rd.buffer_get_data(buffers[6])!=contacts:failures+=1
		var final_contacts:=rd.buffer_get_data(buffers[9+rounds%2])
		var output:=FileAccess.open("res://reports/backtrack-"+str(test.name)+".bin",FileAccess.WRITE)
		output.store_buffer(final_contacts);output.close()
		var committed:=rd.buffer_get_data(buffers[19])
		var commit_status:=rd.buffer_get_data(buffers[20])
		output=FileAccess.open("res://reports/backtrack-"+str(test.name)+"-particles.bin",FileAccess.WRITE)
		output.store_buffer(committed);output.close()
		for g in range(test.grains.size()):
			if committed.slice(g*32+8,g*32+32)!=particles.to_byte_array().slice(g*32+8,g*32+32):failures+=1
		if test.name=="captured_network":
			if commit_status.decode_u32(0)!=1 or absf(commit_status.decode_float(8)-float(test.dt))>1e-8:failures+=1
			if not is_finite(history[-1].after) or history[-1].after>1e-7:failures+=1
		else:
			if committed!=particles.to_byte_array() or commit_status.decode_u32(0)!=0:failures+=1
			if test.name=="active_capacity_rejected" and final_contacts!=contacts:failures+=1
		rows.append({"name":test.name,"history":history,"committed":commit_status.decode_u32(0)==1,"gpu_ms":float(end-start)/1e6})
		rd.free_rid(commit_set)
		for rid in chain_sets+construction_sets:rd.free_rid(rid)
		rd.free_rid(assembly_set)
		rd.free_rid(uniform_set)
		for rid in buffers:rd.free_rid(rid)
	var report:={"failures":failures,"systems":rows,"scope":"Eight bounded GPU assembly/SVD/backtracking iterations from a contact checkpoint; no intermediate CPU readback, gated particle position commit after full residual and geometry validation."}
	var file:=FileAccess.open("res://reports/active-backtrack-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("ACTIVE_BACKTRACK_RESULT ",JSON.stringify(report))
	rd.free_rid(commit_pipeline);rd.free_rid(commit)
	rd.free_rid(backtrack_pipeline);rd.free_rid(backtrack)
	rd.free_rid(assembly_pipeline);rd.free_rid(assembly)
	rd.free_rid(pipeline);rd.free_rid(shader);rd.free()
	quit(0 if failures==0 else 1)

func _make_set(rd:RenderingDevice,shader:RID,refs:Array) -> RID:
	var uniforms:Array[RDUniform]=[]
	for i in range(refs.size()):
		var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(refs[i]);uniforms.append(u)
	return rd.uniform_set_create(uniforms,shader,0)
