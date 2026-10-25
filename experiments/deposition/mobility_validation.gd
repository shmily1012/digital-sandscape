extends SceneTree
const Feedback=preload("res://experiments/deposition/contact_feedback_gpu.gd")
const Online=preload("res://experiments/liquid/online_grains.gd")
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(2);return
	var source:=RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string("res://experiments/deposition/contact_reference.glsl").replace("#[compute]", "").replace("#version 450", "#version 450\n#define FULL_MOBILITY")
	var spirv:=rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():push_error(spirv.compile_error_compute);quit(2);return
	var shader:=rd.shader_create_from_spirv(spirv)
	var pipeline:=rd.compute_pipeline_create(shader)
	var feedback:="--feedback" in OS.get_cmdline_user_args()
	var calibrated:=feedback or "--calibrated" in OS.get_cmdline_user_args()
	var prefix:="feedback" if feedback else ("calibrated" if calibrated else "mobility")
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/"+prefix+"-contact-fixtures.json"))
	var failures:=0
	var rows:Array=[]
	for test:Dictionary in fixture.cases:
		var data:=PackedFloat32Array()
		for g:Dictionary in test.grains:data.append_array(PackedFloat32Array([g.x,g.y,g.radius,g.drag,g.density,g.material,0,0]))
		var initial:=data.to_byte_array()
		var walls:=PackedFloat32Array()
		for plane:Array in test.planes:walls.append_array(PackedFloat32Array(plane))
		var matrix:=PackedFloat32Array()
		for row:Array in test.matrix:matrix.append_array(PackedFloat32Array(row))
		var count:int=test.grains.size()
		var contact_count:int=count*(count-1)/2+count*test.planes.size()
		var buffers:Array[RID]=[rd.storage_buffer_create(initial.size(),initial),rd.storage_buffer_create(initial.size(),initial),rd.storage_buffer_create(walls.size()*4,walls.to_byte_array()),rd.storage_buffer_create(contact_count*48),rd.storage_buffer_create(16),rd.storage_buffer_create(matrix.size()*4) if calibrated else rd.storage_buffer_create(matrix.size()*4,matrix.to_byte_array())]
		var online:RefCounted
		if calibrated:
			online=Online.new()
			if not online.initialize(rd,fixture.base,test.grains):quit(2);return
		var coupling:RefCounted
		if feedback:
			coupling=Feedback.new()
			if not coupling.initialize(rd,initial,online.faces):quit(2);return
		var uniforms:Array[RDUniform]=[]
		for binding in range(buffers.size()):
			var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=binding;u.add_id(online.buffers[8] if calibrated and binding==5 else buffers[binding]);uniforms.append(u)
		var uniform_set:=rd.uniform_set_create(uniforms,shader,0)
		var params:=PackedByteArray();params.resize(32)
		params.encode_u32(0,count);params.encode_u32(4,test.planes.size());params.encode_u32(8,test.budget)
		params.encode_float(16,test.gravity[0]);params.encode_float(20,test.gravity[1]);params.encode_float(24,.01);params.encode_float(28,.5)
		rd.capture_timestamp("begin")
		if calibrated and not online.record_mobility(test.calibration_budget):failures+=1
		var list:=rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,uniform_set,0)
		rd.compute_list_set_push_constant(list,params,32);rd.compute_list_dispatch(list,1,1,1);rd.compute_list_add_barrier(list);rd.compute_list_end()
		if feedback and not coupling.record(online,buffers[0],buffers[1],buffers[3],buffers[4],contact_count,Vector2(test.gravity[0],test.gravity[1]),.01,test.feedback_budget):failures+=1
		rd.capture_timestamp("end");rd.submit();rd.sync()
		var first:int=-1;var last:int=-1
		for i in range(rd.get_captured_timestamps_count()):
			if rd.get_captured_timestamp_name(i)=="begin":first=rd.get_captured_timestamp_gpu_time(i)
			if rd.get_captured_timestamp_name(i)=="end":last=rd.get_captured_timestamp_gpu_time(i)
		if first<0 or last<first:failures+=1
		var status:=rd.buffer_get_data(coupling.buffers[2] if feedback else buffers[4])
		var output:=rd.buffer_get_data(coupling.buffers[0] if feedback else buffers[1])
		var accepted:=status.decode_u32(0)==1
		var error:=0.0
		for i in range(count):
			var g:Dictionary=test.expected[i]
			error=maxf(error,Vector2(output.decode_float(i*32)-g.x,output.decode_float(i*32+4)-g.y).length())
			if output.slice(i*32+8,i*32+32)!=initial.slice(i*32+8,i*32+32):failures+=1
		if accepted!=test.accepted or error>2e-6 or (not accepted and output!=initial):failures+=1
		if rd.buffer_get_data(buffers[0])!=initial:failures+=1
		FileAccess.open("res://reports/"+prefix+"-"+test.name+"-forces.bin",FileAccess.WRITE).store_buffer(rd.buffer_get_data(buffers[3]))
		FileAccess.open("res://reports/"+prefix+"-"+test.name+"-particles.bin",FileAccess.WRITE).store_buffer(output)
		if feedback:
			var published_flux:=rd.buffer_get_data(coupling.buffers[1])
			if not accepted:
				for i in range(published_flux.size()/4):
					if published_flux.decode_float(i*4)!=0:failures+=1
			FileAccess.open("res://reports/"+prefix+"-"+test.name+"-flux.bin",FileAccess.WRITE).store_buffer(published_flux)
			FileAccess.open("res://reports/"+prefix+"-"+test.name+"-net.bin",FileAccess.WRITE).store_buffer(rd.buffer_get_data(coupling.buffers[3]))
		var matrix_error:=0.0
		if calibrated:
			var gpu_matrix:=rd.buffer_get_data(online.buffers[8])
			FileAccess.open("res://reports/"+prefix+"-"+test.name+"-matrix.bin",FileAccess.WRITE).store_buffer(gpu_matrix)
			if test.accepted:
				for i in range(matrix.size()):
					if not is_finite(gpu_matrix.decode_float(i*4)):failures+=1
					matrix_error=maxf(matrix_error,absf(gpu_matrix.decode_float(i*4)-matrix[i]))
				if matrix_error>0.001:failures+=1
		var retained_nonzero:Variant=null
		if feedback and test.name=="release":
			var old_flux:=rd.buffer_get_data(coupling.buffers[1])
			# Cold-start the scratch pressure only to exercise a genuine final-stage failure.
			for level:Dictionary in online.solvers[-1].levels:
				for pressure_buffer:RID in level.p:rd.buffer_clear(pressure_buffer,0,int(level.n)*int(level.n)*4)
			if not coupling.record(online,buffers[0],buffers[1],buffers[3],buffers[4],contact_count,Vector2(test.gravity[0],test.gravity[1]),.01,1):failures+=1
			rd.submit();rd.sync()
			retained_nonzero=rd.buffer_get_data(coupling.buffers[2]).decode_u32(0)==0 and rd.buffer_get_data(coupling.buffers[0])==output and rd.buffer_get_data(coupling.buffers[1])==old_flux
			if not retained_nonzero:failures+=1
		var contact_state:=rd.buffer_get_data(buffers[4])
		rows.append({"retained_nonzero":retained_nonzero,"joint_position_error":status.decode_float(4) if feedback else 0.0,"matrix_error":matrix_error,"name":test.name,"accepted":accepted,"position_error":error,"gpu_ms":(last-first)/1000000.0,"iterations":contact_state.decode_u32(4),"residual":contact_state.decode_float(8)})
		rd.free_rid(uniform_set)
		if feedback:coupling.release()
		if calibrated:online.release()
		for rid in buffers:rd.free_rid(rid)
	var report:={"failures":failures,"cases":rows,"scope":"GPU calibration/contact/net-force pressure feedback with joint particle and flux publication; single step only" if feedback else "GPU pressure calibration to GPU contact; no CPU matrix upload or intermediate readback; net-force feedback not yet connected" if calibrated else "GPU contact with CPU-calibrated mobility"}
	FileAccess.open("res://reports/"+prefix+"-contact-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MOBILITY_CONTACT ",JSON.stringify(report))
	rd.free_rid(pipeline);rd.free_rid(shader);rd.free();quit(0 if failures==0 else 1)

