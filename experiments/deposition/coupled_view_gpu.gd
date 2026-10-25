extends RefCounted
const Physics=preload("res://src/physics_engine.gd")
var rd:RenderingDevice
var texture:RID
var shader:RID
var pipeline:RID
var uniform_set:RID
var params:=PackedByteArray()
func initialize(device:RenderingDevice, model:RefCounted) -> bool:
	rd=device;shader=Physics.compile_shader(rd,"res://experiments/deposition/coupled_view.glsl")
	if not shader.is_valid():return false
	var format:=RDTextureFormat.new();format.width=512;format.height=512;format.format=RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	texture=rd.texture_create(format,RDTextureView.new());pipeline=rd.compute_pipeline_create(shader)
	var refs:=[model.output(),texture,model.buffers[1]]
	var uniforms:Array[RDUniform]=[]
	for i in range(3):
		var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE if i==1 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(refs[i]);uniforms.append(u)
	uniform_set=rd.uniform_set_create(uniforms,shader,0)
	params.resize(16);params.encode_u32(0,model.count);params.encode_u32(4,512);params.encode_u32(8,model.plane_count)
	return texture.is_valid() and uniform_set.is_valid()
func refresh() -> void:
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,uniform_set,0);rd.compute_list_set_push_constant(list,params,16)
	rd.compute_list_dispatch(list,64,64,1);rd.compute_list_add_barrier(list);rd.compute_list_end()
func release() -> void:
	for rid:RID in [uniform_set,texture,pipeline,shader]:
		if rid.is_valid():rd.free_rid(rid)
