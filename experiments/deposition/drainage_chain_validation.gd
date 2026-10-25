extends SceneTree
const Pressure=preload("res://experiments/liquid/multigrid_gpu.gd")
const Physics=preload("res://src/physics_engine.gd")
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(2);return
	var shader:=Physics.compile_shader(rd,"res://experiments/deposition/geometric_operator.glsl")
	if not shader.is_valid():rd.free();quit(2);return
	var pipeline:=rd.compute_pipeline_create(shader)
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/drainage-gpu-fixtures.json"))
	var chain_shader:=Physics.compile_shader(rd,"res://experiments/deposition/drainage_chain.glsl")
	if not chain_shader.is_valid():rd.free_rid(pipeline);rd.free_rid(shader);rd.free();quit(2);return
	var chain_pipeline:=rd.compute_pipeline_create(chain_shader)
	var failures:=0;var rows:Array=[]
	var baseline:Dictionary={}
	var expanded:Array=[]
	for test:Dictionary in fixture.cases:
		for mode in ["baseline","skip","fused"]:
			var entry:Dictionary=test.duplicate(true);entry["skip"]=mode!="baseline";entry["mode"]=mode;expanded.append(entry)
	var repeated:Array=[]
	for repeat in range(3):
		for test:Dictionary in expanded:
			var entry:Dictionary=test.duplicate(true);entry["repeat"]=repeat;repeated.append(entry)
	for test:Dictionary in repeated:
		var n:int=test.grains.size();var nf:int=test.faces.size()
		var particles:=PackedFloat32Array();var velocities:=PackedFloat32Array();var faces:=PackedByteArray();faces.resize(nf*16)
		for g:Array in test.grains:particles.append_array(PackedFloat32Array(g))
		for v:Array in test.velocities:velocities.append_array(PackedFloat32Array(v))
		for i in range(nf):
			for j in range(4):faces.encode_u32(i*16+j*4,int(test.faces[i][j]))
		var mask:=PackedByteArray();mask.resize(test.active.size()*4)
		for i in range(test.active.size()):mask.encode_u32(i*4,int(test.active[i]))
		var mobility:=PackedFloat32Array(test.mobility)
		var liquid:=PackedFloat32Array();liquid.resize(nf);liquid.fill(0.)
		match str(test.fault):
			"overlap":particles[4]=particles[0]
			"wall":particles[0]=0.02
			"mobility":mobility[nf-1]=-1.
			"nan":velocities[n*2-1]=NAN
			"overflow":mobility.fill(1e-30);liquid.fill(3e38)
		var source:=PackedFloat32Array();source.resize(nf);source.fill(.125)
		var adjoint:=PackedFloat32Array();adjoint.resize(n*2);adjoint.fill(-.25)
		var arrays:Array[PackedByteArray]=[particles.to_byte_array(),velocities.to_byte_array(),faces,mask,liquid.to_byte_array(),mobility.to_byte_array(),source.to_byte_array(),adjoint.to_byte_array()]
		var refs:Array[RID]=[]
		for data:PackedByteArray in arrays:refs.append(rd.storage_buffer_create(data.size(),data))
		refs.append(rd.storage_buffer_create(maxi(n,nf)*4));refs.append(rd.storage_buffer_create(4))
		refs.append(rd.storage_buffer_create(nf*4));refs.append(rd.storage_buffer_create(n*8))
		var uniforms:Array[RDUniform]=[]
		for i in range(refs.size()):
			var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(refs[i]);uniforms.append(u)
		var set:=rd.uniform_set_create(uniforms,shader,0)
		var solver=Pressure.new()
		solver.fuse_coarse=str(test.mode)=="fused"
		if not solver.initialize(rd,test.levels):quit(2);return
		var adjacency:=PackedInt32Array(test.adjacency).to_byte_array()
		var sentinel:=PackedFloat32Array();sentinel.resize(n*2);sentinel.fill(-.625)
		var extra:Array[RID]=[rd.storage_buffer_create(adjacency.size(),adjacency),rd.storage_buffer_create(n*8),rd.storage_buffer_create(n*8,sentinel.to_byte_array()),rd.storage_buffer_create(n*4),rd.storage_buffer_create(4),rd.storage_buffer_create(4,PackedFloat32Array([1.]).to_byte_array())]
		var pressure_output:RID=solver.output_after(int(test.budget))
		var chain_refs:Array[RID]=[refs[2],refs[6],extra[0],solver.levels[0].equations,pressure_output,refs[5],refs[4],refs[9],solver.control,refs[1],refs[7],extra[1],extra[2],extra[3],extra[4],extra[5]]
		var cu:Array[RDUniform]=[]
		for i in range(chain_refs.size()):
			var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(chain_refs[i]);cu.append(u)
		var chain_set:=rd.uniform_set_create(cu,chain_shader,0)
		rd.capture_timestamp("geometry_begin")
		var list:=rd.compute_list_begin()
		for phase in range(5):dispatch(rd,list,pipeline,set,n,nf,int(test.side),phase,1 if phase==1 or phase==3 else ceili(float(maxi(n,nf))/64))
		dispatch(rd,list,chain_pipeline,chain_set,n,nf,int(test.side),0,ceili(float(test.side*test.side)/64))
		solver.record_adaptive(list,int(test.budget),2e-6,true,bool(test.skip))
		dispatch(rd,list,chain_pipeline,chain_set,n,nf,int(test.side),1,ceili(float(nf)/64))
		# Geometry retains its rejection flag; only recompute with GPU-generated q.
		for phase in [2,3,4]:dispatch(rd,list,pipeline,set,n,nf,int(test.side),phase,1 if phase==3 else ceili(float(maxi(n,nf))/64))
		for phase in [2,3,4]:dispatch(rd,list,chain_pipeline,chain_set,n,nf,int(test.side),phase,1 if phase==3 else ceili(float(n)/64))
		rd.compute_list_end();rd.capture_timestamp("geometry_end");rd.submit();rd.sync()
		var start:int=-1;var finish:int=-1
		for t in range(rd.get_captured_timestamps_count()):
			if rd.get_captured_timestamp_name(t)=="geometry_begin":start=rd.get_captured_timestamp_gpu_time(t)
			if rd.get_captured_timestamp_name(t)=="geometry_end":finish=rd.get_captured_timestamp_gpu_time(t)
		if start<0 or finish<=start:failures+=1
		var accepted:bool=rd.buffer_get_data(extra[4]).decode_u32(0)==1
		var output:=rd.buffer_get_data(extra[2]);var q:=rd.buffer_get_data(refs[4]);var status:=rd.buffer_get_data(solver.control)
		if accepted!=bool(test.accepted):failures+=1
		var key:=str(test.name)
		if not bool(test.skip):baseline[key]=[output,q,status]
		elif baseline[key]!=[output,q,status]:failures+=1
		var force_error:=0.;var flux_error:=0.
		if not accepted:
			if output!=sentinel.to_byte_array():failures+=1
		else:
			for i in range(n*2):
				var value:=output.decode_float(i*4)
				if not is_finite(value):failures+=1
				force_error=maxf(force_error,absf(value-float(test.expected_h[i])))
			for i in range(nf):
				var value:=q.decode_float(i*4)
				if not is_finite(value):failures+=1
				flux_error=maxf(flux_error,absf(value-float(test.expected_q[i])))
			if force_error>1e-7 or flux_error>3e-6:failures+=1
		rows.append({"name":test.name,"repeat":test.repeat,"mode":test.mode,"skip_converged_checks":test.skip,"accepted":accepted,"force_error":force_error,"flux_error":flux_error,"pressure_residual":status.decode_float(0),"cycles":status.decode_u32(8),"gpu_ms":float(finish-start)/1e6})
		rd.free_rid(chain_set)
		for rid in extra:rd.free_rid(rid)
		solver.release()
		rd.free_rid(set)
		for rid in refs:rd.free_rid(rid)
	var report:={"failures":failures,"cases":rows,"scope":"GPU Bv -> sealed pressure -> liquid flux -> Dv - B^T Wq; prescribed velocity, no particle advancement"}
	var file:=FileAccess.open("res://reports/drainage-chain-gpu.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("DRAINAGE_CHAIN_RESULT ",JSON.stringify(report))
	rd.free_rid(chain_pipeline);rd.free_rid(chain_shader);rd.free_rid(pipeline);rd.free_rid(shader);rd.free();quit(0 if failures==0 else 1)

func dispatch(rd:RenderingDevice,list:int,pipeline:RID,set:RID,n:int,nf:int,side:int,phase:int,groups:int)->void:
	var pc:=PackedByteArray();pc.resize(16);pc.encode_u32(0,n);pc.encode_u32(4,nf);pc.encode_u32(8,side);pc.encode_u32(12,phase)
	rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set,0)
	rd.compute_list_set_push_constant(list,pc,16);rd.compute_list_dispatch(list,groups,1,1);rd.compute_list_add_barrier(list)
