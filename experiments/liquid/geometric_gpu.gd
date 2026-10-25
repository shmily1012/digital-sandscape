extends RefCounted

const Physics = preload("res://src/physics_engine.gd")
var rd: RenderingDevice
var side := 0
var face_count := 0
var max_dt := INF
var parity := 0
var dynamic_velocity := false
var buffers: Array[RID] = []
var sets: Array[RID] = []
var shader := RID()
var pipeline := RID()
var velocity_shader := RID()
var velocity_pipeline := RID()
var velocity_sets: Dictionary = {}

func initialize(device: RenderingDevice, fixture: Dictionary) -> bool:
	rd = device
	side = int(fixture.size)
	face_count = fixture.faces.size()
	shader = Physics.compile_shader(rd, "res://experiments/liquid/geometric.glsl")
	if not shader.is_valid():
		return false
	pipeline = rd.compute_pipeline_create(shader)
	velocity_shader = Physics.compile_shader(rd, "res://experiments/liquid/transport_velocity.glsl")
	if not velocity_shader.is_valid():
		return false
	velocity_pipeline = rd.compute_pipeline_create(velocity_shader)
	var initial := PackedFloat32Array(fixture.initial).to_byte_array()
	buffers.append(rd.storage_buffer_create(initial.size(), initial))
	buffers.append(rd.storage_buffer_create(initial.size(), initial))
	for field in ["neighbors","adjacency"]:
		var bytes := PackedInt32Array(fixture[field]).to_byte_array()
		buffers.append(rd.storage_buffer_create(bytes.size(), bytes))
	var face_data := PackedByteArray()
	face_data.resize(face_count*16)
	var outgoing := PackedFloat64Array()
	outgoing.resize(side*side)
	for index in range(face_count):
		var face: Array = fixture.faces[index]
		face_data.encode_u32(index*16, int(face[0]))
		face_data.encode_u32(index*16+4, int(face[1]))
		face_data.encode_float(index*16+8, face[2])
		face_data.encode_u32(index*16+12, int(face[3]))
		outgoing[int(face[0] if float(face[2]) >= 0 else face[1])] += absf(float(face[2]))*side
	for rate in outgoing:
		if rate > 0:
			max_dt = minf(max_dt, 0.45/rate)
	buffers.append(rd.storage_buffer_create(face_data.size(), face_data))
	for bytes in [side*side*16,face_count*8,side*side*16,face_count*4]:
		buffers.append(rd.storage_buffer_create(bytes))
	var compensation := PackedByteArray()
	compensation.resize(side*side*4)
	compensation.fill(0)
	buffers.append(rd.storage_buffer_create(compensation.size(), compensation))
	var metadata := PackedByteArray()
	metadata.resize(16)
	metadata.fill(0)
	buffers.append(rd.storage_buffer_create(16, metadata))
	for order in range(2):
		var uniforms: Array[RDUniform] = []
		for binding in range(11):
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = binding
			uniform.add_id(buffers[(order+binding)%2] if binding < 2 else buffers[binding])
			uniforms.append(uniform)
		sets.append(rd.uniform_set_create(uniforms, shader, 0))
	return true

func record_steps(list: int, steps: int, dt: float) -> bool:
	# Cached CFL bounds apply only while the initial face velocities are immutable.
	if dynamic_velocity or steps < 0 or steps > 256 or not is_finite(dt) or dt <= 0 or dt > max_dt:
		return false
	_record_transport(list, steps, dt*side)
	return true

func _record_transport(list: int, steps: int, dt_h: float) -> void:
	var params := PackedByteArray()
	params.resize(16)
	params.encode_u32(0, side*side)
	params.encode_u32(4, face_count)
	params.encode_float(8, dt_h)
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	for step in range(steps):
		rd.compute_list_bind_uniform_set(list, sets[parity], 0)
		for phase in range(5):
			params.encode_u32(12, phase)
			rd.compute_list_set_push_constant(list, params, 16)
			var count := face_count if phase == 1 or phase == 3 else side*side
			rd.compute_list_dispatch(list, ceili(float(count)/64), 1, 1)
			rd.compute_list_add_barrier(list)
		parity = 1-parity

func record_dynamic_step(list: int, pressure: RID, forcing: RID, control: RID, requested_dt: float) -> bool:
	if not is_finite(requested_dt) or requested_dt <= 0:
		return false
	dynamic_velocity = true
	var references := [pressure,forcing,buffers[4],buffers[3],buffers[10],control]
	var key := str(references)
	if not velocity_sets.has(key):
		var uniforms: Array[RDUniform] = []
		for binding in range(references.size()):
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.binding = binding
			uniform.add_id(references[binding])
			uniforms.append(uniform)
		velocity_sets[key] = rd.uniform_set_create(uniforms, velocity_shader, 0)
	var params := PackedByteArray()
	params.resize(32)
	params.encode_u32(0, side*side)
	params.encode_u32(4, face_count)
	params.encode_u32(8, side)
	params.encode_float(16, requested_dt)
	params.encode_float(20, 1e-5)
	rd.compute_list_bind_compute_pipeline(list, velocity_pipeline)
	rd.compute_list_bind_uniform_set(list, velocity_sets[key], 0)
	for phase in range(2):
		params.encode_u32(12, phase)
		rd.compute_list_set_push_constant(list, params, 32)
		rd.compute_list_dispatch(list, ceili(float(face_count)/64) if phase==0 else 1, 1, 1)
		rd.compute_list_add_barrier(list)
	_record_transport(list, 1, -1.0)
	return true

func output() -> RID:
	return buffers[parity]

func release() -> void:
	for rid: RID in velocity_sets.values():
		rd.free_rid(rid)
	for rid in sets+buffers:
		rd.free_rid(rid)
	if pipeline.is_valid():
		rd.free_rid(pipeline)
	if shader.is_valid():
		rd.free_rid(shader)
	if velocity_pipeline.is_valid():
		rd.free_rid(velocity_pipeline)
	if velocity_shader.is_valid():
		rd.free_rid(velocity_shader)
