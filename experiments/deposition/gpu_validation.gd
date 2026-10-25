extends SceneTree
const Physics = preload("res://src/physics_engine.gd")
func _initialize() -> void: _run.call_deferred()

func _make_set(rd: RenderingDevice, shader: RID, refs: Array) -> RID:
	var uniforms: Array[RDUniform] = []
	for i in range(refs.size()):
		var u := RDUniform.new()
		u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding=i
		u.add_id(refs[i])
		uniforms.append(u)
	return rd.uniform_set_create(uniforms,shader,0)

func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd==null:
		quit(2)
		return
	var cycle := "--contact-cycle" in OS.get_cmdline_user_args()
	var interval := cycle or "--contact-interval" in OS.get_cmdline_user_args()
	var benchmark := "--contact-benchmark" in OS.get_cmdline_user_args()
	var parallel := interval or "--parallel" in OS.get_cmdline_user_args()
	var shader := Physics.compile_shader(rd,"res://experiments/deposition/contact_interval.glsl" if interval else "res://experiments/deposition/contact_parallel.glsl" if parallel else "res://experiments/deposition/contact_reference.glsl")
	if not shader.is_valid():
		quit(2)
		return
	var pipeline := rd.compute_pipeline_create(shader)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/contact-cycle-fixtures.json" if cycle else "res://reports/contact-interval-fixtures.json" if interval else "res://reports/contact-gpu-fixtures.json"))
	var failures := 0
	var rows: Array=[]
	for test: Dictionary in fixture.cases:
		if benchmark and test.name!="captured_half": continue
		if benchmark:
			var repeated: Array=[]
			for i in range(40): repeated.append(test.steps[0])
			test.steps=repeated
		var samples: Array[float]=[]
		var step_index:=0
		var data:=PackedFloat32Array()
		for g: Dictionary in test.initial: data.append_array(PackedFloat32Array([g.x,g.y,g.radius,g.drag,g.density,g.material,0,0]))
		var initial:=data.to_byte_array()
		var buffers: Array[RID]=[rd.storage_buffer_create(initial.size(),initial),rd.storage_buffer_create(initial.size(),initial)]
		var planes:=PackedFloat32Array()
		for plane: Array in test.planes: planes.append_array(PackedFloat32Array(plane))
		buffers.append(rd.storage_buffer_create(planes.size()*4,planes.to_byte_array()))
		var count: int=test.initial.size()
		buffers.append(rd.storage_buffer_create((count*(count-1)/2+count*test.planes.size())*48))
		buffers.append(rd.storage_buffer_create(32 if interval else 16))
		var sets: Array[RID]=[]
		for parity in range(2): sets.append(_make_set(rd,shader,[buffers[parity],buffers[1-parity],buffers[2],buffers[3],buffers[4]]))
		var params:=PackedByteArray()
		params.resize(32)
		params.encode_u32(0,count)
		params.encode_u32(4,test.planes.size())
		params.encode_u32(8,test.budget)
		params.encode_u32(12,8)
		params.encode_float(24,test.dt)
		params.encode_float(28,test.friction)
		var parity:=0
		var contact_law_error:=0.0
		var net_force_error:=0.0
		var force_error:=0.0
		var error:=0.0
		var max_residual:=0.0
		var retained:=true
		var total_ms:=0.0
		var accepted_steps:=0
		var rejection_detail: Dictionary={}
		var first_rejection:=0
		var first_divergence:=0
		var largest_substeps:=0
		var largest_attempts:=0
		for step: Dictionary in test.steps:
			if benchmark: rd.buffer_update(buffers[parity],0,initial.size(),initial)
			var before:=rd.buffer_get_data(buffers[parity])
			params.encode_float(16,step.gravity[0])
			params.encode_float(20,step.gravity[1])
			rd.capture_timestamp("begin")
			var list:=rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(list,pipeline)
			rd.compute_list_bind_uniform_set(list,sets[parity],0)
			rd.compute_list_set_push_constant(list,params,32)
			rd.compute_list_dispatch(list,1,1,1)
			rd.compute_list_add_barrier(list)
			rd.compute_list_end()
			rd.capture_timestamp("end")
			rd.submit()
			rd.sync()
			var begin: int=-1
			var end: int=-1
			for i in range(rd.get_captured_timestamps_count()):
				if rd.get_captured_timestamp_name(i)=="begin": begin=rd.get_captured_timestamp_gpu_time(i)
				if rd.get_captured_timestamp_name(i)=="end": end=rd.get_captured_timestamp_gpu_time(i)
			if begin<0 or end<begin: failures+=1
			else:
				var elapsed:=float(end-begin)/1e6
				total_ms+=elapsed
				if not benchmark or step_index>=10: samples.append(elapsed)
			step_index+=1
			parity=1-parity
			var actual:=rd.buffer_get_data(buffers[parity])
			var status:=rd.buffer_get_data(buffers[4])
			var accepted:=status.decode_u32(0)==1
			if interval:
				largest_substeps=maxi(largest_substeps,status.decode_u32(16))
				largest_attempts=maxi(largest_attempts,status.decode_u32(20))
				var elapsed:=status.decode_float(24)
				if largest_substeps>8 or largest_attempts>15 or not is_finite(elapsed): failures+=1
				if accepted and absf(elapsed-float(test.dt))>1e-8: failures+=1
				if not accepted and elapsed!=0.0: failures+=1
			if accepted: accepted_steps+=1
			if accepted!=bool(step.accepted): failures+=1
			if not accepted:
				if cycle and first_rejection==0:
					first_rejection=step_index
					rejection_detail={"reason":status.decode_u32(12),"iterations":status.decode_u32(4),"substeps":status.decode_u32(16),"attempts":status.decode_u32(20),"last_dt":status.decode_float(28),"gravity":step.gravity}
					var saved:=FileAccess.open("res://reports/contact-cycle-rejected-input.bin",FileAccess.WRITE)
					saved.store_buffer(before)
					saved.close()
				retained=retained and actual==before
				if actual!=before: failures+=1
			else:
				var residual:=status.decode_float(8)
				if not is_finite(residual) or residual>1e-7: failures+=1
				max_residual=maxf(max_residual,residual)
				var contacts:=rd.buffer_get_data(buffers[3])
				var net_actual: Array[Vector2]=[]
				var net_expected: Array[Vector2]=[]
				for g in range(count):
					net_actual.append(Vector2.ZERO)
					net_expected.append(Vector2.ZERO)
				for c in range(step.reactions.size()):
					if interval:
						var last_dt:=status.decode_float(28)
						var gap:=contacts.decode_float(c*48+8)
						var mobility:=contacts.decode_float(c*48+12)
						var ln:=contacts.decode_float(c*48+32)
						var lt:=contacts.decode_float(c*48+36)
						var un:=contacts.decode_float(c*48+40)
						var ut:=contacts.decode_float(c*48+44)
						var pn:=maxf(0,ln-(un+gap/last_dt)/mobility)
						var pt:=clampf(lt-ut/mobility,-float(test.friction)*ln,float(test.friction)*ln)
						var law_error:=mobility*maxf(absf(pn-ln),absf(pt-lt))
						if not is_finite(law_error): failures+=1
						contact_law_error=maxf(contact_law_error,law_error)
						var row: Array=step.contacts[c]
						var n:=Vector2(contacts.decode_float(c*48),contacts.decode_float(c*48+4))
						var force:=n*contacts.decode_float(c*48+32)+Vector2(-n.y,n.x)*contacts.decode_float(c*48+36)
						var reference:=Vector2(row[2],row[3])*float(row[5])+Vector2(-float(row[3]),row[2])*float(row[6])
						net_actual[int(row[0])]+=force
						net_expected[int(row[0])]+=reference
						if int(row[1])>=0:
							net_actual[int(row[1])]-=force
							net_expected[int(row[1])]-=reference
					if parallel and not interval and contacts.decode_u32(c*48+24)!=status.decode_u32(4): failures+=1
					for axis in range(2):
						var force:=contacts.decode_float(c*48+32+axis*4)
						if not is_finite(force): failures+=1
						force_error=maxf(force_error,absf(force-float(step.reactions[c][axis])))
				if interval:
					for g in range(count): net_force_error=maxf(net_force_error,net_actual[g].distance_to(net_expected[g]))
			for i in range(count):
				var x:=actual.decode_float(i*32)
				var y:=actual.decode_float(i*32+4)
				if not is_finite(x) or not is_finite(y): failures+=1
				error=maxf(error,maxf(absf(x-float(step.expected[i].x)),absf(y-float(step.expected[i].y))))
				if actual.slice(i*32+8,i*32+32)!=initial.slice(i*32+8,i*32+32): failures+=1
			if cycle and first_divergence==0 and error>2e-6: first_divergence=step_index
		if interval and test.name=="partial_rollback" and (largest_substeps==0 or accepted_steps!=0): failures+=1
		if error>2e-6 or (not interval and force_error>2e-6) or (interval and (net_force_error>2e-6 or contact_law_error>2e-7)): failures+=1
		samples.sort()
		rows.append({"gpu_p50_ms":samples[samples.size()/2],"gpu_p95_ms":samples[mini(samples.size()-1,ceili(samples.size()*0.95)-1)],"samples":samples.size(),"name":test.name,"first_rejection":first_rejection,"rejection_detail":rejection_detail,"first_position_divergence":first_divergence,"largest_substeps":largest_substeps,"largest_attempts":largest_attempts,"position_error":error,"reaction_error":force_error,"net_reaction_error":net_force_error,"contact_law_error":contact_law_error,"accepted_steps":accepted_steps,"rejected_retained":retained,"max_residual":max_residual,"mean_gpu_ms":total_ms/test.steps.size()})
		for rid in sets+buffers: rd.free_rid(rid)
	var report:={"failures":failures,"cases":rows,"scope":"Serial small-island GPU contact reference, float32 residual 1e-7 and geometry allowance 2e-7; CPU same residual. No fluid, spin, substep controller or scalable parallel solve."}
	report["benchmark"] = benchmark
	report["parallel"] = parallel
	if parallel: report["scope"]="One 16-thread workgroup, disjoint pair rounds and per-particle wall solves; bounded 16-particle island, no inter-island coupling or fluid."
	var output_path := "res://reports/contact-parallel-validation.json" if parallel else "res://reports/contact-gpu-validation.json"
	if interval: output_path="res://reports/contact-interval-validation.json"
	if interval: report["scope"]="GPU-internal bounded bisection of a 16-particle contact island; entire interval commits or retains input, no intermediate CPU particle readback."
	if cycle: output_path="res://reports/contact-cycle-validation.json"
	if benchmark: output_path="res://reports/contact-parallel-benchmark.json" if parallel else "res://reports/contact-serial-benchmark.json"
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("CONTACT_GPU_RESULT ",JSON.stringify(report))
	rd.free_rid(pipeline)
	rd.free_rid(shader)
	rd.free()
	quit(0 if failures==0 else 1)
