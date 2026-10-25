extends RefCounted
const Compiler=preload("res://src/physics_engine.gd")
var rd:RenderingDevice
var texture:=RID()
var shader:=RID()
var pipeline:=RID()
var sets:Array[RID]=[]
var side:int
func initialize(device:RenderingDevice,states:Array[RID],n:int,materials:RID)->bool:
	rd=device;side=n
	shader=Compiler.compile_shader(rd,"res://shaders/phase_colorize.glsl")
	if not shader.is_valid():return false
	var format:=RDTextureFormat.new();format.width=n;format.height=n
	format.format=RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	texture=rd.texture_create(format,RDTextureView.new())
	pipeline=rd.compute_pipeline_create(shader)
	for state in states:
		var input:=RDUniform.new();input.binding=0;input.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;input.add_id(state)
		var output:=RDUniform.new();output.binding=1;output.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;output.add_id(texture)
		var wall:=RDUniform.new();wall.binding=2;wall.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;wall.add_id(materials)
		sets.append(rd.uniform_set_create([input,output,wall],shader,0))
	return texture.is_valid() and pipeline.is_valid()
func refresh(parity:int)->void:
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,sets[parity],0);rd.compute_list_dispatch(list,ceili(side/8.),ceili(side/8.),1);rd.compute_list_end()
func release()->void:
	for resource in sets+[pipeline,texture,shader]:
		if resource.is_valid():rd.free_rid(resource)
