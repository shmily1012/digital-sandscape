extends SceneTree
const Physics = preload("res://src/physics_engine.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd==null:
		quit(2)
		return
	var shader := Physics.compile_shader(rd,"res://experiments/liquid/fast_self.glsl")
	if not shader.is_valid():
		quit(2)
		return
	var pipeline := rd.compute_pipeline_create(shader)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/kernel-self-validation.json"))
	var kernel: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/self-response-kernel.json"))
	var values := PackedFloat32Array()
	for matrix: Array in kernel.values:
		for row: Array in matrix: values.append_array(PackedFloat32Array(row))
	var kernel_buffer := rd.storage_buffer_create(values.size()*4,values.to_byte_array())
	var rows: Array = []
	var failures := 0
	fixture.rows.append({"size":32,"position":[0.9,0.5],"accepted":false})
	for test: Dictionary in fixture.rows:
		var positions := PackedFloat32Array()
		for i in range(128): positions.append_array(PackedFloat32Array(test.position))
		var input := rd.storage_buffer_create(positions.size()*4,positions.to_byte_array())
		var output := rd.storage_buffer_create(128*16)
		var validity := rd.storage_buffer_create(128*4)
		var uniforms: Array[RDUniform] = []
		var refs := [input,output,validity,kernel_buffer]
		for binding in range(4):
			var u := RDUniform.new()
			u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.binding=binding
			u.add_id(refs[binding])
			uniforms.append(u)
		var set := rd.uniform_set_create(uniforms,shader,0)
		var params := PackedByteArray()
		params.resize(16)
		params.encode_u32(0,test.size)
		params.encode_u32(4,128)
		rd.capture_timestamp("begin")
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list,pipeline)
		rd.compute_list_bind_uniform_set(list,set,0)
		rd.compute_list_set_push_constant(list,params,16)
		rd.compute_list_dispatch(list,2,1,1)
		rd.compute_list_end()
		rd.capture_timestamp("end")
		rd.submit()
		rd.sync()
		var begin := -1
		var end := -1
		for i in range(rd.get_captured_timestamps_count()):
			if rd.get_captured_timestamp_name(i)=="begin": begin=rd.get_captured_timestamp_gpu_time(i)
			if rd.get_captured_timestamp_name(i)=="end": end=rd.get_captured_timestamp_gpu_time(i)
		var actual := rd.buffer_get_data(output)
		var valid := rd.buffer_get_data(validity)
		var error := 0.0
		for i in range(128):
			if (valid.decode_u32(i*4)==1)!=bool(test.accepted): failures += 1
			if test.accepted:
				for j in range(4):
					var value := actual.decode_float(i*16+j*4)
					if not is_finite(value): failures += 1
					error=maxf(error,absf(value-float(test.estimate[j])))
		if error>0.002: failures += 1
		rows.append({"side":test.size,"position":test.position,"accepted":test.accepted,"max_gpu_reference_error":error,"batch_128_gpu_ms":float(end-begin)/1e6 if begin>=0 and end>=begin else -1.0})
		for rid in [set,input,output,validity]: rd.free_rid(rid)
	var report := {"failures":failures,"cases":rows,"kernel_bytes":values.size()*4,"scope":"128 repeated-position kernel queries per case, one cold timing sample. No pressure solve, particle integration, whole-mobility certificate or near-wall support."}
	var file := FileAccess.open("res://reports/fast-self-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("FAST_SELF_RESULT ",JSON.stringify(report))
	for rid in [kernel_buffer,pipeline,shader]: rd.free_rid(rid)
	rd.free()
	quit(0 if failures==0 else 1)
