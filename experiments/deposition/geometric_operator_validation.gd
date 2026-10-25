extends SceneTree
const Physics=preload("res://src/physics_engine.gd")
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(2);return
	var shader:=Physics.compile_shader(rd,"res://experiments/deposition/geometric_operator.glsl")
	if not shader.is_valid():rd.free();quit(2);return
	var pipeline:=rd.compute_pipeline_create(shader)
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/geometric-operator-fixtures.json"))
	var failures:=0;var rows:Array=[]
	for test:Dictionary in fixture.cases:
		var n:int=test.grains.size();var nf:int=test.faces.size()
		var particles:=PackedFloat32Array();var velocities:=PackedFloat32Array();var faces:=PackedByteArray();faces.resize(nf*16)
		for g:Array in test.grains:particles.append_array(PackedFloat32Array(g))
		for v:Array in test.velocities:velocities.append_array(PackedFloat32Array(v))
		for i in range(nf):
			for j in range(4):faces.encode_u32(i*16+j*4,int(test.faces[i][j]))
		var mask:=PackedByteArray();mask.resize(test.active.size()*4)
		for i in range(test.active.size()):mask.encode_u32(i*4,int(test.active[i]))
		var mobility:=PackedFloat32Array(test.mobility)
		var liquid:=PackedFloat32Array(test.q)
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
		rd.capture_timestamp("geometry_begin")
		var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set,0)
		for phase in range(5):
			var pc:=PackedByteArray();pc.resize(16);pc.encode_u32(0,n);pc.encode_u32(4,nf);pc.encode_u32(8,int(test.side));pc.encode_u32(12,phase)
			rd.compute_list_set_push_constant(list,pc,16);rd.compute_list_dispatch(list,1 if phase==1 or phase==3 else ceili(float(maxi(n,nf))/64),1,1);rd.compute_list_add_barrier(list)
		rd.compute_list_end();rd.capture_timestamp("geometry_end");rd.submit();rd.sync()
		var start:int=-1;var finish:int=-1
		for t in range(rd.get_captured_timestamps_count()):
			if rd.get_captured_timestamp_name(t)=="geometry_begin":start=rd.get_captured_timestamp_gpu_time(t)
			if rd.get_captured_timestamp_name(t)=="geometry_end":finish=rd.get_captured_timestamp_gpu_time(t)
		if start<0 or finish<=start:failures+=1
		var accepted:bool=rd.buffer_get_data(refs[9]).decode_u32(0)==1
		var src:=rd.buffer_get_data(refs[6]);var adj:=rd.buffer_get_data(refs[7])
		if accepted!=bool(test.accepted):failures+=1
		var source_error:=0.;var adjoint_error:=0.;var work:=0.
		if not accepted:
			if src!=arrays[6] or adj!=arrays[7]:failures+=1
		else:
			for i in range(nf):
				var v:=src.decode_float(i*4)
				if not is_finite(v):failures+=1
				source_error=maxf(source_error,absf(v-float(test.expected_source[i])))
				work+=v*float(test.q[i])/float(test.side*test.side)/float(mobility[i])
			for i in range(n):
				for a in range(2):
					var v:=adj.decode_float((i*2+a)*4)
					if not is_finite(v):failures+=1
					adjoint_error=maxf(adjoint_error,absf(v-float(test.expected_adjoint[i][a])))
					work+=v*float(velocities[i*2+a])
			if source_error>3e-6 or adjoint_error>1e-7 or absf(work)>1e-7:failures+=1
		rows.append({"name":test.name,"accepted":accepted,"source_error":source_error,"adjoint_error":adjoint_error,"work_error":absf(work),"gpu_ms":float(finish-start)/1e6})
		rd.free_rid(set)
		for rid in refs:rd.free_rid(rid)
	var report:={"failures":failures,"cases":rows,"scope":"GPU geometric B and adjoint, prescribed velocity and liquid flux; pressure solve is CPU oracle only"}
	var file:=FileAccess.open("res://reports/geometric-operator-gpu.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("GEOMETRIC_OPERATOR_RESULT ",JSON.stringify(report))
	rd.free_rid(pipeline);rd.free_rid(shader);rd.free();quit(0 if failures==0 else 1)
