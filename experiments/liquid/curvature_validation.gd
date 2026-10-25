extends SceneTree
const Physics = preload("res://src/physics_engine.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd==null:
		quit(2)
		return
	var shader := Physics.compile_shader(rd,"res://experiments/liquid/curvature.glsl")
	if not shader.is_valid():
		quit(2)
		return
	var pipeline := rd.compute_pipeline_create(shader)
	var extend_shader := Physics.compile_shader(rd,"res://experiments/liquid/curvature_extend.glsl")
	var extend_pipeline := rd.compute_pipeline_create(extend_shader)
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://reports/curvature-fixtures.json"))
	var failures := 0
	var cases: Array = []
	for fixture: Dictionary in fixtures:
		var data := PackedFloat32Array(fixture.fraction).to_byte_array()
		var input := rd.storage_buffer_create(data.size(),data)
		var output := rd.storage_buffer_create(data.size()*2)
		var uniforms: Array[RDUniform] = []
		for binding in range(2):
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = binding
			uniform.add_id(input if binding==0 else output)
			uniforms.append(uniform)
		var set := rd.uniform_set_create(uniforms,shader,0)
		var extended := rd.storage_buffer_create(data.size()*2)
		var extend_uniforms: Array[RDUniform] = []
		var refs := [input,output,extended]
		for binding in range(3):
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = binding
			uniform.add_id(refs[binding])
			extend_uniforms.append(uniform)
		var extend_set := rd.uniform_set_create(extend_uniforms,extend_shader,0)
		var params := PackedByteArray()
		params.resize(16)
		params.encode_u32(0,fixture.size)
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list,pipeline)
		rd.compute_list_bind_uniform_set(list,set,0)
		rd.compute_list_set_push_constant(list,params,16)
		rd.compute_list_dispatch(list,ceili(float(fixture.fraction.size())/64),1,1)
		rd.compute_list_add_barrier(list)
		rd.compute_list_bind_compute_pipeline(list,extend_pipeline)
		rd.compute_list_bind_uniform_set(list,extend_set,0)
		rd.compute_list_set_push_constant(list,params,16)
		rd.compute_list_dispatch(list,ceili(float(fixture.fraction.size())/64),1,1)
		rd.compute_list_end()
		rd.submit()
		rd.sync()
		var actual := rd.buffer_get_data(output)
		var extended_data := rd.buffer_get_data(extended)
		var extension_error := 0.0
		var extension_mismatches := 0
		for i in range(fixture.fraction.size()):
			var valid := extended_data.decode_float(i*8+4)==1.0
			if valid != (fixture.extended[i]!=null):
				extension_mismatches += 1
			if valid and fixture.extended[i]!=null:
				extension_error = maxf(extension_error,absf(extended_data.decode_float(i*8)-float(fixture.extended[i])))
		if extension_mismatches>0 or extension_error>0.002:
			failures += 1
		var error := 0.0
		var resolved := 0
		var mismatches := 0
		for i in range(fixture.fraction.size()):
			var valid := actual.decode_float(i*8+4)==1.0
			if valid != (fixture.expected[i]!=null):
				mismatches += 1
			if valid:
				resolved += 1
				var value := actual.decode_float(i*8)
				if not is_finite(value):
					failures += 1
				if fixture.expected[i]!=null:
					error = maxf(error,absf(value-float(fixture.expected[i])))
		if mismatches>0 or error>0.002:
			failures += 1
		cases.append({"name":fixture.name,"resolved":resolved,"validity_mismatches":mismatches,"max_error":error,"extension_mismatches":extension_mismatches,"extension_error":extension_error})
		rd.free_rid(extend_set)
		rd.free_rid(extended)
		rd.free_rid(set)
		rd.free_rid(input)
		rd.free_rid(output)
	var result := {"failures":failures,"cases":cases,"device":rd.get_device_name(),"scope":"Height-function curvature on current fractions only; no force or evolution."}
	var file := FileAccess.open("res://reports/curvature-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("CURVATURE_RESULT ",JSON.stringify(result))
	rd.free_rid(pipeline)
	rd.free_rid(shader)
	rd.free_rid(extend_pipeline)
	rd.free_rid(extend_shader)
	rd.free()
	quit(0 if failures==0 else 1)
