extends RefCounted
const ACTIVE_CAPACITY:=24
const MATRIX_SIZE:=2*ACTIVE_CAPACITY
var rd:RenderingDevice
var shaders:Array[RID]=[]
var pipelines:Array[RID]=[]
var sets:Dictionary={}
var particles:Array[RID]=[]
var contacts:Array[RID]=[]
var buffers:Dictionary={}
var parity:=0
var contact_parity:=0
var count:=0
var contact_count:=0
var plane_count:=0
var pending:=false
var refined:=false
var rounds_used:=0
var tick:=0
var simulated_time:=0.0
var step_dt:=0.0
var params:=PackedByteArray()

func initialize(device:RenderingDevice, initial:Array, planes:Array) -> bool:
	if initial.is_empty() or initial.size()>16 or planes.is_empty() or planes.size()>64:return false
	rd=device;count=initial.size();plane_count=planes.size()
	contact_count=count*(count-1)/2+count*plane_count
	for name in ["contact_parallel","active_system","active_svd","active_backtrack","active_commit"]:
		var source:=RDShaderSource.new()
		source.source_compute=FileAccess.get_file_as_string("res://experiments/deposition/"+name+".glsl").replace("#[compute]", "").replace("#version 450", "#version 450\n#define CONTACT_CAPACITY %d\n#define SVD_SIZE %d" % [ACTIVE_CAPACITY,MATRIX_SIZE])
		var spirv:=rd.shader_compile_spirv_from_source(source)
		if not spirv.compile_error_compute.is_empty():
			push_error(spirv.compile_error_compute);return false
		var shader:=rd.shader_create_from_spirv(spirv)
		if not shader.is_valid():return false
		shaders.append(shader);pipelines.append(rd.compute_pipeline_create(shader))
	var data:=PackedFloat32Array()
	for g:Dictionary in initial:data.append_array(PackedFloat32Array([g.x,g.y,g.radius,g.drag,g.density,g.material,0,0]))
	for i in range(2):particles.append(rd.storage_buffer_create(data.size()*4,data.to_byte_array()))
	for i in range(2):contacts.append(rd.storage_buffer_create(contact_count*48))
	var walls:=PackedFloat32Array()
	for plane:Array in planes:walls.append_array(PackedFloat32Array(plane))
	buffers.walls=rd.storage_buffer_create(walls.size()*4,walls.to_byte_array())
	var sizes:Dictionary={"pgs_status":16,"matrix":MATRIX_SIZE*MATRIX_SIZE*4,"rhs":MATRIX_SIZE*4,"selection":ACTIVE_CAPACITY*4,"assembly":16,"direction":MATRIX_SIZE*4,"null":MATRIX_SIZE*4,"svd":16,"backtrack":32,"commit":16}
	for key in sizes:buffers[key]=rd.storage_buffer_create(sizes[key])
	return true

func _set_for(kind:int, refs:Array) -> RID:
	var key:=str(kind)+str(refs)
	if not sets.has(key):
		var uniforms:Array[RDUniform]=[]
		for i in range(refs.size()):
			var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(refs[i]);uniforms.append(u)
		sets[key]=rd.uniform_set_create(uniforms,shaders[kind],0)
	return sets[key]

func _dispatch(list:int, kind:int, refs:Array, push:PackedByteArray) -> void:
	rd.compute_list_bind_compute_pipeline(list,pipelines[kind])
	rd.compute_list_bind_uniform_set(list,_set_for(kind,refs),0)
	rd.compute_list_set_push_constant(list,push,push.size())
	rd.compute_list_dispatch(list,1,1,1)
	rd.compute_list_add_barrier(list)

func record_step(gravity:Vector2, dt:float) -> bool:
	if pending or not gravity.is_finite() or not is_finite(dt) or dt<=0:return false
	pending=true;refined=false;rounds_used=0;contact_parity=0;step_dt=dt
	params=PackedByteArray();params.resize(32)
	params.encode_u32(0,count);params.encode_u32(4,contact_count)
	params.encode_float(8,dt);params.encode_float(12,.5)
	params.encode_float(16,gravity.x);params.encode_float(20,gravity.y);params.encode_float(24,1e-7)
	var pgs:=PackedByteArray();pgs.resize(32)
	pgs.encode_u32(0,count);pgs.encode_u32(4,plane_count);pgs.encode_u32(8,256)
	pgs.encode_float(16,gravity.x);pgs.encode_float(20,gravity.y);pgs.encode_float(24,dt);pgs.encode_float(28,.5)
	var list:=rd.compute_list_begin()
	_dispatch(list,0,[particles[parity],particles[1-parity],buffers.walls,contacts[0],buffers.pgs_status],pgs)
	# Rebuild velocity from stored reactions even on the fast path.
	_dispatch(list,4,[particles[parity],contacts[0],particles[1-parity],buffers.commit,buffers.pgs_status],params)
	rd.compute_list_end()
	return true

func record_refinement(rounds:int=1) -> bool:
	if not pending or rounds<1 or rounds>4 or rounds_used+rounds>16:return false
	var svd_params:=PackedByteArray();svd_params.resize(16)
	svd_params.encode_u32(0,MATRIX_SIZE);svd_params.encode_u32(4,16);svd_params.encode_float(8,1e-6);svd_params.encode_u32(12,1)
	var list:=rd.compute_list_begin()
	for iteration in range(rounds):
		_dispatch(list,1,[particles[parity],contacts[contact_parity],buffers.matrix,buffers.rhs,buffers.selection,buffers.assembly],params)
		_dispatch(list,2,[buffers.matrix,buffers.rhs,buffers.direction,buffers.svd,buffers["null"],buffers.assembly],svd_params)
		_dispatch(list,3,[particles[parity],contacts[contact_parity],buffers.selection,buffers.assembly,buffers.direction,buffers.svd,buffers["null"],contacts[1-contact_parity],buffers.backtrack],params)
		contact_parity=1-contact_parity
	_dispatch(list,4,[particles[parity],contacts[contact_parity],particles[1-parity],buffers.commit,buffers.assembly],params)
	rd.compute_list_end()
	rounds_used+=rounds;refined=true
	return true

func status_buffer() -> RID:return buffers.commit
func output() -> RID:return particles[parity]
func accept(status:PackedByteArray) -> bool:
	if not pending or status.size()!=16 or status.decode_u32(0)!=1:return false
	parity=1-parity;tick+=1;simulated_time+=step_dt;pending=false
	return true
func cancel() -> void:pending=false
func release() -> void:
	for rid:RID in sets.values():rd.free_rid(rid)
	for rid:RID in particles+contacts:rd.free_rid(rid)
	for rid:RID in buffers.values():rd.free_rid(rid)
	for rid:RID in pipelines+shaders:rd.free_rid(rid)

