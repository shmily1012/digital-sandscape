extends RefCounted

const Physics = preload("res://src/physics_engine.gd")
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var sets: Dictionary = {}
var curvature_shader: RID
var curvature_pipeline: RID
var curvature: RID
var curvature_sets: Dictionary = {}
var raw_curvature: RID
var extend_shader: RID
var extend_pipeline: RID
var extend_sets: Dictionary = {}

func initialize(device: RenderingDevice) -> bool:
	rd = device
	shader = Physics.compile_shader(rd,"res://experiments/liquid/buoyancy.glsl")
	if not shader.is_valid():
		return false
	pipeline = rd.compute_pipeline_create(shader)
	curvature_shader = Physics.compile_shader(rd,"res://experiments/liquid/curvature.glsl")
	if not curvature_shader.is_valid():
		return false
	curvature_pipeline = rd.compute_pipeline_create(curvature_shader)
	extend_shader = Physics.compile_shader(rd,"res://experiments/liquid/curvature_extend.glsl")
	if not extend_shader.is_valid():
		return false
	extend_pipeline = rd.compute_pipeline_create(extend_shader)
	return true

func record(list: int, fraction: RID, faces: RID, adjacency: RID, equations: RID, side: int, face_count: int, gravity: Vector2, strength: float, tension: float = 0.0, reference: float = 0.0) -> void:
	if not curvature.is_valid():
		curvature = rd.storage_buffer_create(side*side*8)
		raw_curvature = rd.storage_buffer_create(side*side*8)
	if tension>0:
		var curvature_key := str(fraction)
		if not curvature_sets.has(curvature_key):
			var uniforms: Array[RDUniform] = []
			for binding in range(2):
				var uniform := RDUniform.new()
				uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
				uniform.binding = binding
				uniform.add_id(fraction if binding==0 else raw_curvature)
				uniforms.append(uniform)
			curvature_sets[curvature_key] = rd.uniform_set_create(uniforms,curvature_shader,0)
		var curvature_params := PackedByteArray()
		curvature_params.resize(16)
		curvature_params.encode_u32(0,side)
		rd.compute_list_bind_compute_pipeline(list,curvature_pipeline)
		rd.compute_list_bind_uniform_set(list,curvature_sets[curvature_key],0)
		rd.compute_list_set_push_constant(list,curvature_params,16)
		rd.compute_list_dispatch(list,ceili(float(side*side)/64),1,1)
		rd.compute_list_add_barrier(list)
		if not extend_sets.has(curvature_key):
			var extend_uniforms: Array[RDUniform] = []
			var references := [fraction,raw_curvature,curvature]
			for binding in range(3):
				var uniform := RDUniform.new()
				uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
				uniform.binding = binding
				uniform.add_id(references[binding])
				extend_uniforms.append(uniform)
			extend_sets[curvature_key] = rd.uniform_set_create(extend_uniforms,extend_shader,0)
		rd.compute_list_bind_compute_pipeline(list,extend_pipeline)
		rd.compute_list_bind_uniform_set(list,extend_sets[curvature_key],0)
		rd.compute_list_set_push_constant(list,curvature_params,16)
		rd.compute_list_dispatch(list,ceili(float(side*side)/64),1,1)
		rd.compute_list_add_barrier(list)
	var references := [fraction,faces,adjacency,equations,curvature]
	var key := str(references)
	if not sets.has(key):
		var uniforms: Array[RDUniform] = []
		for binding in range(5):
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = binding
			uniform.add_id(references[binding])
			uniforms.append(uniform)
		sets[key] = rd.uniform_set_create(uniforms,shader,0)
	var params := PackedByteArray()
	params.resize(32)
	params.encode_u32(0,side)
	params.encode_u32(4,face_count)
	params.encode_float(12,strength)
	params.encode_float(16,gravity.x)
	params.encode_float(20,gravity.y)
	params.encode_float(24,tension)
	params.encode_float(28,reference)
	rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,sets[key],0)
	for phase in range(2):
		params.encode_u32(8,phase)
		rd.compute_list_set_push_constant(list,params,32)
		rd.compute_list_dispatch(list,ceili(float(face_count if phase==0 else side*side)/64),1,1)
		rd.compute_list_add_barrier(list)

func release() -> void:
	for uniform: RID in extend_sets.values():
		rd.free_rid(uniform)
	for uniform: RID in curvature_sets.values():
		rd.free_rid(uniform)
	for uniform: RID in sets.values():
		rd.free_rid(uniform)
	rd.free_rid(pipeline)
	rd.free_rid(shader)
	if curvature.is_valid():
		rd.free_rid(curvature)
		rd.free_rid(raw_curvature)
	rd.free_rid(extend_pipeline)
	rd.free_rid(extend_shader)
	rd.free_rid(curvature_pipeline)
	rd.free_rid(curvature_shader)
