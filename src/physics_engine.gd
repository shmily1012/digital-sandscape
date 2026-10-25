class_name SandPhysicsEngine
extends RefCounted

const Randomness = preload("res://src/randomness_manager.gd")
var rd: RenderingDevice
var side: int
var seed_value: int
var tick: int = 0
var state := RID()
var shader := RID()
var pipeline := RID()
var uniform_set := RID()
var error_message := ""
var liquid_model := false
var scratch := RID()
var liquid_sets:Array[RID]=[]

# Invoke only on the owning device's thread. Local devices are used by GPU tests.
func initialize(device: RenderingDevice, grid_size: int, world_seed: int, use_liquid:bool=false, restored:PackedByteArray=PackedByteArray()) -> bool:
	rd = device
	liquid_model=use_liquid
	side = grid_size
	seed_value = world_seed
	if rd == null:
		error_message = "RenderingDevice unavailable. Use Vulkan Mobile/Forward+."
		return false
	shader = compile_shader(rd, "res://shaders/liquid_sand.glsl" if liquid_model else "res://shaders/settle.glsl")
	if not shader.is_valid():
		error_message = "Physics compute shader compilation failed. See console."
		return false
	var format := RDTextureFormat.new()
	format.format = RenderingDevice.DATA_FORMAT_R32_UINT
	format.width = side
	format.height = side
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var initial:=restored if not restored.is_empty() else (Randomness.liquid_state(side, seed_value) if liquid_model else Randomness.initial_state(side, seed_value))
	if initial.size()!=side*side*4:return false
	state = rd.texture_create(format, RDTextureView.new(), [initial])
	if not state.is_valid():
		error_message = "R32_UINT storage texture unsupported."
		return false
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(state)
	if liquid_model:
		scratch=rd.texture_create(format,RDTextureView.new())
		for phase in range(2):
			var items:Array[RDUniform]=[]
			for binding in range(2):
				var item:=RDUniform.new();item.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;item.binding=binding
				item.add_id(state if binding==phase else scratch);items.append(item)
			liquid_sets.append(rd.uniform_set_create(items,shader,0))
		uniform_set=liquid_sets[0]
	else:
		uniform_set = rd.uniform_set_create([uniform], shader, 0)
	pipeline = rd.compute_pipeline_create(shader)
	return uniform_set.is_valid() and pipeline.is_valid()

static func compile_shader(device: RenderingDevice, path: String) -> RID:
	var source := RDShaderSource.new()
	source.source_compute = FileAccess.get_file_as_string(path).replace("#[compute]", "")
	var spirv := device.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():
		push_error(spirv.compile_error_compute)
		return RID()
	return device.shader_create_from_spirv(spirv)

func advance(gravity: Vector2i, count: int) -> void:
	if count <= 0:
		return
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	for _step in range(count):
		for phase in range(2):
			if liquid_model:rd.compute_list_bind_uniform_set(list,liquid_sets[phase],0)
			var params := PackedByteArray()
			params.resize(32)
			params.encode_u32(0, side)
			params.encode_u32(4, seed_value & 0xffffffff)
			params.encode_u32(8, tick & 0xffffffff)
			params.encode_u32(12, phase)
			params.encode_s32(16, gravity.x)
			params.encode_s32(20, gravity.y)
			rd.compute_list_set_push_constant(list, params, 32)
			var groups := ceili((side / 2.0 + 1.0) / 8.0)
			rd.compute_list_dispatch(list, groups, groups, 1)
			rd.compute_list_add_barrier(list)
		tick += 1
	rd.compute_list_end()

func release() -> void:
	if rd == null:
		return
	for extra in liquid_sets.slice(1):rd.free_rid(extra)
	liquid_sets.clear()
	for resource in [uniform_set, pipeline, scratch, state, shader]:
		if resource.is_valid():
			rd.free_rid(resource)
	scratch=RID()
	uniform_set = RID()
	pipeline = RID()
	state = RID()
	shader = RID()
