extends RefCounted

const Physics = preload("res://src/physics_engine.gd")
var rd: RenderingDevice
var levels: Array = []
var shaders: Array[RID] = []
var pipelines: Array[RID] = []
var sets: Dictionary = {}
var dispatches := 0
var control := RID()
var adaptive := false
var fuse_coarse := false

func initialize(device: RenderingDevice, descriptions: Array) -> bool:
	rd = device
	for name in ["pressure", "restrict", "prolong", "residual_control", "pressure_coarse"]:
		var shader := Physics.compile_shader(rd, "res://experiments/liquid/%s.glsl" % name)
		if not shader.is_valid():
			return false
		shaders.append(shader)
		pipelines.append(rd.compute_pipeline_create(shader))
	for description: Dictionary in descriptions:
		var n := int(description.size)
		var zero := PackedByteArray()
		zero.resize(n*n*4)
		zero.fill(0)
		var data := PackedFloat32Array(description.equations).to_byte_array()
		levels.append({"n": n, "parity": 0, "p": [rd.storage_buffer_create(zero.size(), zero), rd.storage_buffer_create(zero.size(), zero)], "equations": rd.storage_buffer_create(data.size(), data)})
	var metadata := PackedByteArray()
	metadata.resize(16+16*levels.size())
	metadata.fill(0)
	control = rd.storage_buffer_create(metadata.size(), metadata, RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	return true

func uniform_set(kind: int, buffers: Array) -> RID:
	var key := str(kind)+str(buffers)
	if sets.has(key):
		return sets[key]
	var uniforms: Array[RDUniform] = []
	for binding in range(buffers.size()):
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = binding
		uniform.add_id(buffers[binding])
		uniforms.append(uniform)
	var result := rd.uniform_set_create(uniforms, shaders[kind], 0)
	sets[key] = result
	return result

func dispatch(list: int, kind: int, n: int, count: int, buffers: Array) -> void:
	var params := PackedByteArray()
	params.resize(16)
	params.encode_u32(0, n)
	params.encode_float(4, 0.8)
	rd.compute_list_bind_compute_pipeline(list, pipelines[kind])
	rd.compute_list_bind_uniform_set(list, uniform_set(kind, buffers), 0)
	rd.compute_list_set_push_constant(list, params, 16)
	if adaptive:
		var index := 0
		while int(levels[index].n)*int(levels[index].n) != count:
			index += 1
		rd.compute_list_dispatch_indirect(list, control, 16+16*index)
	else:
		rd.compute_list_dispatch(list, ceili(float(count)/64), 1, 1)
	rd.compute_list_add_barrier(list)
	dispatches += 1

func smooth(list: int, level: int, steps: int) -> void:
	var current: Dictionary = levels[level]
	if fuse_coarse and int(current.n) == 4 and steps == 32:
		# Use distinct storage buffers even though shared memory contains all
		# inputs. In-place binding failed the downstream GPU parity regression.
		var parity := int(current.parity)
		dispatch(list, 4, 4, 16, [current.p[parity], current.p[1-parity], current.equations])
		current.parity = 1-parity
		return
	for step in range(steps):
		var parity := int(current.parity)
		dispatch(list, 0, current.n, current.n*current.n, [current.p[parity],current.p[1-parity],current.equations])
		current.parity = 1-parity

func cycle(list: int, level: int = 0) -> void:
	if level == levels.size()-1:
		smooth(list, level, 32)
		return
	smooth(list, level, 3)
	var fine: Dictionary = levels[level]
	var coarse: Dictionary = levels[level+1]
	dispatch(list, 1, fine.n, coarse.n*coarse.n, [fine.p[fine.parity],fine.equations,coarse.equations,coarse.p[0]])
	coarse.parity = 0
	cycle(list, level+1)
	dispatch(list, 2, fine.n, fine.n*fine.n, [fine.p[fine.parity],coarse.p[coarse.parity],fine.p[1-int(fine.parity)]])
	fine.parity = 1-int(fine.parity)
	smooth(list, level, 3)

func output_after(cycles: int) -> RID:
	# Each non-coarsest cycle flips parity (3 smooth + prolong + 3 smooth).
	return levels[0].p[cycles%2 if levels.size()>1 or fuse_coarse else 0]

func check_residual(list: int, tolerance: float, final_check: bool, roundoff_relative: bool = false, skip_if_converged: bool = false, backward_error: bool = false) -> void:
	var fine: Dictionary = levels[0]
	var params := PackedByteArray()
	params.resize(16)
	params.encode_u32(0, fine.n)
	params.encode_u32(4, levels.size())
	params.encode_float(8, tolerance)
	params.encode_u32(12, (1 if final_check else 0) | (2 if roundoff_relative else 0) | (4 if skip_if_converged else 0) | (8 if backward_error else 0))
	rd.compute_list_bind_compute_pipeline(list, pipelines[3])
	rd.compute_list_bind_uniform_set(list, uniform_set(3, [fine.p[fine.parity],fine.equations,control,fine.p[1-int(fine.parity)]]), 0)
	rd.compute_list_set_push_constant(list, params, 16)
	rd.compute_list_dispatch(list, 1, 1, 1)
	rd.compute_list_add_barrier(list)

func record_adaptive(list: int, budget: int, tolerance: float, roundoff_relative: bool = false, skip_converged_checks: bool = false, backward_error: bool = false) -> RID:
	if budget < 1 or budget > 128 or not is_finite(tolerance) or tolerance <= 0:
		push_error("Adaptive pressure requires 1..128 cycles and a finite positive tolerance")
		return RID()
	adaptive = true
	for step in range(budget):
		check_residual(list, tolerance, false, roundoff_relative, skip_converged_checks and step > 0, backward_error)
		cycle(list)
	check_residual(list, tolerance, true, roundoff_relative, skip_converged_checks, backward_error)
	adaptive = false
	return levels[0].p[levels[0].parity]

func reset_statistics() -> void:
	var zero := PackedByteArray()
	zero.resize(16)
	zero.fill(0)
	rd.buffer_update(control, 0, 16, zero)

func release() -> void:
	for rid: RID in sets.values():
		rd.free_rid(rid)
	for level: Dictionary in levels:
		for rid: RID in level.p+[level.equations]:
			rd.free_rid(rid)
	for rid in pipelines+shaders:
		rd.free_rid(rid)
	if control.is_valid():
		rd.free_rid(control)
