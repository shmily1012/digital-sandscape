class_name SandArtRenderer
extends RefCounted

const Physics = preload("res://src/physics_engine.gd")
var rd: RenderingDevice
var texture := RID()
var shader := RID()
var pipeline := RID()
var uniform_set := RID()
var side: int
var output_side:int
var mineral_filter := true

func initialize(device: RenderingDevice, state: RID, grid_size: int) -> bool:
	rd = device
	side = grid_size
	output_side=side*2
	shader = Physics.compile_shader(rd, "res://shaders/colorize.glsl")
	if not shader.is_valid():
		return false
	var format := RDTextureFormat.new()
	format.width = output_side
	format.height = output_side
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	texture = rd.texture_create(format, RDTextureView.new())
	if not texture.is_valid():
		return false
	var uniforms: Array[RDUniform] = []
	for binding in range(2):
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = binding
		uniform.add_id(state if binding == 0 else texture)
		uniforms.append(uniform)
	uniform_set = rd.uniform_set_create(uniforms, shader, 0)
	pipeline = rd.compute_pipeline_create(shader)
	return uniform_set.is_valid() and pipeline.is_valid()

func refresh() -> void:
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	var params:=PackedByteArray();params.resize(16);params.encode_u32(0,1 if mineral_filter else 0)
	rd.compute_list_set_push_constant(list,params,16)
	rd.compute_list_dispatch(list, ceili(output_side / 8.0), ceili(output_side / 8.0), 1)
	rd.compute_list_end()

func release() -> void:
	if rd == null:
		return
	for resource in [uniform_set, pipeline, texture, shader]:
		if resource.is_valid():
			rd.free_rid(resource)
	uniform_set = RID()
	pipeline = RID()
	texture = RID()
	shader = RID()
