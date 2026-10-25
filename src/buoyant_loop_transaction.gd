extends RefCounted
## Physics-internal bounded loop transaction and optional GPU search; no readback.
const Compiler=preload("res://src/physics_engine.gd")
var rd:RenderingDevice
var shader:=RID()
var pipeline:=RID()
var bindings:Array[RID]=[]
var path_buffer:=RID()
var result:=RID()
var count:=0
func initialize(device:RenderingDevice,solver:RefCounted,path:PackedInt32Array,automatic:bool=false)->bool:
	if not automatic and (path.size()<4 or path.size()>192):return false
	rd=device;count=path.size()
	shader=Compiler.compile_shader(rd,"res://shaders/buoyant_loop_search.glsl" if automatic else "res://shaders/buoyant_loop_transaction.glsl")
	if not shader.is_valid():return false
	pipeline=rd.compute_pipeline_create(shader)
	path_buffer=rd.storage_buffer_create(4 if automatic else path.size()*4,PackedByteArray() if automatic else path.to_byte_array())
	var zero:=PackedByteArray();zero.resize(32);result=rd.storage_buffer_create(32,zero)
	for parity in range(2):
		var uniforms:Array[RDUniform]=[]
		var buffers:Array[RID]=[solver.phase[parity],solver.materials,solver.distributions[parity],solver.mass_residual,solver.grain_energy_stamp,path_buffer,result]
		for i in range(buffers.size()):
			var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;uniform.binding=i;uniform.add_id(buffers[i]);uniforms.append(uniform)
		bindings.append(rd.uniform_set_create(uniforms,shader,0))
	return bindings[0].is_valid() and bindings[1].is_valid()
func record(list:int,solver:RefCounted,gravity:Vector2,parity:int=-1)->void:
	var push:=PackedByteArray();push.resize(48)
	push.encode_u32(0,solver.side);push.encode_float(4,.01);push.encode_float(8,4.);push.encode_float(12,solver.grain_wetting_cosine)
	push.encode_u32(16,solver.tick);push.encode_u32(20,solver.grain_seed);push.encode_u32(24,count)
	push.encode_float(32,gravity.x);push.encode_float(36,gravity.y);push.encode_float(40,solver.grain_weight_scale);push.encode_float(44,solver.grain_mobility_scale)
	rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,bindings[solver.tick%2 if parity<0 else parity],0)
	rd.compute_list_set_push_constant(list,push,48);rd.compute_list_dispatch(list,1,1,1);rd.compute_list_add_barrier(list)
func release()->void:
	for rid in bindings+[path_buffer,result,pipeline,shader]:
		if rid.is_valid():rd.free_rid(rid)
