extends SceneTree
const Physics = preload("res://src/physics_engine.gd")
const Solver = preload("res://experiments/liquid/multigrid_gpu.gd")
func _initialize() -> void: _run.call_deferred()

func _make_set(rd: RenderingDevice,shader: RID,refs: Array) -> RID:
	var uniforms: Array[RDUniform] = []
	for i in range(refs.size()):
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = i
		uniform.add_id(refs[i])
		uniforms.append(uniform)
	return rd.uniform_set_create(uniforms,shader,0)

func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd==null:
		quit(2)
		return
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/grain-fixtures.json"))
	var shader := Physics.compile_shader(rd,"res://experiments/liquid/grain_coupling.glsl")
	if not shader.is_valid():
		quit(2)
		return
	var pipeline := rd.compute_pipeline_create(shader)
	var failures := 0
	var rows: Array = []
	for test: Dictionary in fixture.cases:
		var solver := Solver.new()
		if not solver.initialize(rd,fixture.base.levels):
			quit(2)
			return
		var particles := PackedFloat32Array()
		for g: Dictionary in test.grains: particles.append_array(PackedFloat32Array([g.x,g.y,g.radius,g.drag,g.density,g.material,0,0]))
		var initial := particles.to_byte_array()
		var input := rd.storage_buffer_create(initial.size(),initial)
		var candidate := rd.storage_buffer_create(initial.size())
		var output := rd.storage_buffer_create(initial.size())
		var normalization := rd.storage_buffer_create(test.grains.size()*8)
		var valid := rd.storage_buffer_create(test.grains.size()*4)
		var face_data := PackedByteArray()
		face_data.resize(fixture.base.faces.size()*16)
		for i in range(fixture.base.faces.size()):
			face_data.encode_u32(i*16,fixture.base.faces[i][0])
			face_data.encode_u32(i*16+4,fixture.base.faces[i][1])
			face_data.encode_float(i*16+8,fixture.base.faces[i][2])
		var faces := rd.storage_buffer_create(face_data.size(),face_data)
		var adjacency_data := PackedInt32Array(fixture.base.geometry.adjacency).to_byte_array()
		var adjacency := rd.storage_buffer_create(adjacency_data.size(),adjacency_data)
		var self_data := PackedFloat32Array()
		for block: Array in test.self_response: self_data.append_array(PackedFloat32Array(block))
		var self_buffer := rd.storage_buffer_create(self_data.size()*4,self_data.to_byte_array())
		var refs := [input,candidate,output,normalization,faces,solver.levels[0].equations,solver.levels[0].p[0],solver.control,valid,adjacency,self_buffer]
		var first := _make_set(rd,shader,refs)
		var params := PackedByteArray()
		params.resize(32)
		params.encode_u32(0,test.grains.size())
		params.encode_u32(4,fixture.base.faces.size())
		params.encode_u32(8,32)
		params.encode_float(16,test.gravity[0])
		params.encode_float(20,test.gravity[1])
		params.encode_float(24,test.dt)
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list,pipeline)
		rd.compute_list_bind_uniform_set(list,first,0)
		for phase in range(3):
			params.encode_u32(12,phase)
			rd.compute_list_set_push_constant(list,params,32)
			var count: int = test.grains.size() if phase==0 else (fixture.base.faces.size() if phase==1 else 1024)
			rd.compute_list_dispatch(list,ceili(float(count)/64),1,1)
			rd.compute_list_add_barrier(list)
		refs[6] = solver.record_adaptive(list,test.budget,2e-6)
		var second := _make_set(rd,shader,refs)
		rd.compute_list_bind_compute_pipeline(list,pipeline)
		rd.compute_list_bind_uniform_set(list,second,0)
		for phase in [3,4]:
			params.encode_u32(12,phase)
			rd.compute_list_set_push_constant(list,params,32)
			rd.compute_list_dispatch(list,ceili(float(test.grains.size())/64),1,1)
			rd.compute_list_add_barrier(list)
		rd.compute_list_end()
		rd.submit()
		rd.sync()
		var actual := rd.buffer_get_data(output)
		var source := rd.buffer_get_data(faces)
		var error := 0.0
		var source_error := 0.0
		for i in range(test.grains.size()):
			var x := actual.decode_float(i*32)
			var y := actual.decode_float(i*32+4)
			if not is_finite(x) or not is_finite(y): failures += 1
			error=maxf(error,maxf(absf(x-float(test.expected[i].x)),absf(y-float(test.expected[i].y))))
			if actual.slice(i*32+8,i*32+32)!=initial.slice(i*32+8,i*32+32): failures += 1
		for i in range(test.source.size()): source_error=maxf(source_error,absf(source.decode_float(i*16+12)-float(test.source[i])))
		if error>2e-6 or source_error>2e-6 or (not test.accepted and actual!=initial): failures += 1
		rows.append({"name":test.name,"max_position_error":error,"max_spread_error":source_error,"retained":actual==initial})
		for rid in [first,second,input,candidate,output,normalization,faces,valid,adjacency,self_buffer]: rd.free_rid(rid)
		solver.release()
	var result := {"failures":failures,"cases":rows,"scope":"Single-step dilute grains with CPU-calibrated current-position self response uploaded for GPU validation. No online GPU calibration, packing, gas exclusion or wall drag correction."}
	var file := FileAccess.open("res://reports/grain-coupling-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("GRAIN_COUPLING_RESULT ",JSON.stringify(result))
	rd.free_rid(pipeline)
	rd.free_rid(shader)
	rd.free()
	quit(0 if failures==0 else 1)

