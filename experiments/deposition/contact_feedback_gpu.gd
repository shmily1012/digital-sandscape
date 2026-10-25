extends RefCounted
const Physics=preload("res://src/physics_engine.gd")
var rd:RenderingDevice
var shader:RID
var pipeline:RID
var sets:Dictionary={}
var buffers:Array[RID]=[]
func initialize(device:RenderingDevice, initial:PackedByteArray, face_count:int) -> bool:
	rd=device;shader=Physics.compile_shader(rd,"res://experiments/deposition/contact_feedback.glsl")
	if not shader.is_valid():return false
	pipeline=rd.compute_pipeline_create(shader)
	var zeros:=PackedByteArray();zeros.resize(face_count*4)
	buffers=[rd.storage_buffer_create(initial.size(),initial),rd.storage_buffer_create(zeros.size(),zeros),rd.storage_buffer_create(16),rd.storage_buffer_create(initial.size()/4)]
	return true
func _dispatch(list:int, refs:Array, params:PackedByteArray, phase:int, work:int) -> void:
	var key:=str(refs)
	if not sets.has(key):
		var uniforms:Array[RDUniform]=[]
		for i in range(refs.size()):
			var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(refs[i]);uniforms.append(u)
		sets[key]=rd.uniform_set_create(uniforms,shader,0)
	var set:RID=sets[key]
	params.encode_u32(12,phase)
	rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set,0);rd.compute_list_set_push_constant(list,params,32)
	rd.compute_list_dispatch(list,ceili(work/64.0),1,1);rd.compute_list_add_barrier(list)
var pressure_solver:RefCounted
var prepared_params:=PackedByteArray()
var prepared_refs:Array=[]
var prepared_work:=0
func prepare(online:RefCounted, src:RID, candidate:RID, contacts:RID, contact_status:RID, contact_count:int, gravity:Vector2, dt:float) -> void:
	pressure_solver=online.solvers[-1]
	pressure_solver.reset_statistics()
	prepared_params=PackedByteArray();prepared_params.resize(32)
	prepared_params.encode_u32(0,online.count);prepared_params.encode_u32(4,online.faces);prepared_params.encode_u32(8,contact_count)
	prepared_params.encode_float(16,gravity.x);prepared_params.encode_float(20,gravity.y);prepared_params.encode_float(24,dt);prepared_params.encode_u32(28,32)
	prepared_refs=[src,candidate,contacts,contact_status,online.buffers[3],online.buffers[4],pressure_solver.levels[0].equations,online.buffers[6],pressure_solver.levels[0].p[pressure_solver.levels[0].parity],pressure_solver.control,buffers[0],buffers[1],buffers[2],buffers[3],online.buffers[7]]
	var list:=rd.compute_list_begin()
	_dispatch(list,prepared_refs,prepared_params,0,online.count)
	_dispatch(list,prepared_refs,prepared_params,1,online.faces)
	_dispatch(list,prepared_refs,prepared_params,2,1024)
	prepared_work=maxi(online.count,online.faces)
	rd.compute_list_end()
func pressure_packet(budget:int) -> void:
	var list:=rd.compute_list_begin()
	prepared_refs[8]=pressure_solver.record_adaptive(list,budget,2e-6,true)
	rd.compute_list_end()
func validate_candidate() -> void:
	var list:=rd.compute_list_begin()
	_dispatch(list,prepared_refs,prepared_params,3,1)
	rd.compute_list_end()
func publish_candidate() -> void:
	var list:=rd.compute_list_begin()
	_dispatch(list,prepared_refs,prepared_params,4,prepared_work)
	rd.compute_list_end()
func record(online:RefCounted, src:RID, candidate:RID, contacts:RID, contact_status:RID, contact_count:int, gravity:Vector2, dt:float, budget:int=96) -> bool:
	if budget<1 or budget>128:return false
	prepare(online,src,candidate,contacts,contact_status,contact_count,gravity,dt)
	pressure_packet(budget)
	validate_candidate()
	publish_candidate()
	return true
func release() -> void:
	for set:RID in sets.values():rd.free_rid(set)
	for rid:RID in buffers+[pipeline,shader]:
		if rid.is_valid():rd.free_rid(rid)
