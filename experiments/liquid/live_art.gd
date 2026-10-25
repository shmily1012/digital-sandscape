extends RefCounted
const Physics = preload("res://src/physics_engine.gd")
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var texture: RID
var sets: Dictionary = {}

func initialize(device: RenderingDevice) -> bool:
	rd = device
	shader = Physics.compile_shader(rd,"res://experiments/liquid/live_color.glsl")
	if not shader.is_valid(): return false
	pipeline = rd.compute_pipeline_create(shader)
	var format := RDTextureFormat.new()
	format.width = 32
	format.height = 32
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	texture = rd.texture_create(format,RDTextureView.new())
	return texture.is_valid()

func record(list: int, fraction: RID) -> void:
	var key := str(fraction)
	if not sets.has(key):
		var uniforms: Array[RDUniform] = []
		for binding in range(2):
			var uniform := RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER if binding==0 else RenderingDevice.UNIFORM_TYPE_IMAGE
			uniform.binding = binding
			uniform.add_id(fraction if binding==0 else texture)
			uniforms.append(uniform)
		sets[key] = rd.uniform_set_create(uniforms,shader,0)
	rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,sets[key],0)
	rd.compute_list_dispatch(list,4,4,1)

func release() -> void:
	for uniform: RID in sets.values(): rd.free_rid(uniform)
	for resource in [texture,pipeline,shader]:
		if resource.is_valid(): rd.free_rid(resource)
