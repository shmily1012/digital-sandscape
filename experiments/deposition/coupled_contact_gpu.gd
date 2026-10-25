extends RefCounted
const Online=preload("res://experiments/liquid/online_grains.gd")
const Feedback=preload("res://experiments/deposition/contact_feedback_gpu.gd")
var rd:RenderingDevice
var online:RefCounted
var feedback:RefCounted
var shader:RID
var pipeline:RID
var uniform_set:RID
var buffers:Array[RID]=[]
var count:=0
var plane_count:=0
var contact_count:=0
var pending:=false
var tick:=0
var simulated_time:=0.0
var step_dt:=0.0
func initialize(device:RenderingDevice, base:Dictionary, particles:Array, planes:Array) -> bool:
	if planes.is_empty() or planes.size()>64:return false
	rd=device;online=Online.new()
	if not online.initialize(rd,base,particles):return false
	count=particles.size();plane_count=planes.size();contact_count=count*(count-1)/2+count*plane_count
	if plane_count<1 or plane_count>64:return false
	var initial:=PackedFloat32Array()
	for g:Dictionary in particles:initial.append_array(PackedFloat32Array([g.x,g.y,g.radius,g.drag,g.density,g.material,0,0]))
	feedback=Feedback.new()
	if not feedback.initialize(rd,initial.to_byte_array(),online.faces):return false
	var source:=RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string("res://experiments/deposition/contact_reference.glsl").replace("#[compute]", "").replace("#version 450", "#version 450\n#define FULL_MOBILITY")
	var spirv:=rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():push_error(spirv.compile_error_compute);return false
	shader=rd.shader_create_from_spirv(spirv);pipeline=rd.compute_pipeline_create(shader)
	var walls:=PackedFloat32Array()
	for plane:Array in planes:walls.append_array(PackedFloat32Array(plane))
	buffers=[rd.storage_buffer_create(count*32),rd.storage_buffer_create(walls.size()*4,walls.to_byte_array()),rd.storage_buffer_create(contact_count*48),rd.storage_buffer_create(16)]
	var refs:=[online.output(),buffers[0],buffers[1],buffers[2],buffers[3],online.buffers[8]]
	var uniforms:Array[RDUniform]=[]
	for i in range(refs.size()):
		var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(refs[i]);uniforms.append(u)
	uniform_set=rd.uniform_set_create(uniforms,shader,0)
	return true
func record_step(gravity:Vector2, dt:float, calibration_budget:int=96, feedback_budget:int=96) -> bool:
	if pending or not gravity.is_finite() or not is_finite(dt) or dt<=0 or calibration_budget<1 or calibration_budget>128 or feedback_budget<1 or feedback_budget>128:return false
	pending=true;step_dt=dt
	# Only the previously published physical world becomes the next input.
	rd.buffer_copy(feedback.buffers[0],online.output(),0,0,count*32)
	online.record_mobility(calibration_budget)
	record_contact(gravity,dt)
	return feedback.record(online,online.output(),buffers[0],buffers[2],buffers[3],contact_count,gravity,dt,feedback_budget)
func begin_transaction(dt:float) -> bool:
	if pending or not is_finite(dt) or dt<=0:return false
	pending=true;step_dt=dt
	rd.buffer_copy(feedback.buffers[0],online.output(),0,0,count*32)
	return true
func record_contact(gravity:Vector2, dt:float) -> void:
	var params:=PackedByteArray();params.resize(32)
	params.encode_u32(0,count);params.encode_u32(4,plane_count);params.encode_u32(8,2000)
	params.encode_float(16,gravity.x);params.encode_float(20,gravity.y);params.encode_float(24,dt);params.encode_float(28,.5)
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,uniform_set,0)
	rd.compute_list_set_push_constant(list,params,32);rd.compute_list_dispatch(list,1,1,1);rd.compute_list_add_barrier(list);rd.compute_list_end()
func complete(status:PackedByteArray) -> bool:
	if not pending:return false
	pending=false
	if status.size()!=16 or status.decode_u32(0)!=1:return false
	tick+=1;simulated_time+=step_dt;return true
func output() -> RID:return feedback.buffers[0]
func flux() -> RID:return feedback.buffers[1]
func status_buffer() -> RID:return feedback.buffers[2]
func release() -> void:
	if rd==null:return
	if uniform_set.is_valid():rd.free_rid(uniform_set)
	if feedback!=null:feedback.release()
	if online!=null:online.release()
	for rid:RID in buffers+[pipeline,shader]:
		if rid.is_valid():rd.free_rid(rid)
