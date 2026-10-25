extends RefCounted
const Physics = preload("res://src/physics_engine.gd")
const Solver = preload("res://experiments/liquid/multigrid_gpu.gd")
var rd: RenderingDevice
var shaders: Array[RID] = []
var pipelines: Array[RID] = []
var sets: Dictionary = {}
var buffers: Array[RID] = []
var solvers: Array = []
var count := 0
var faces := 0
var parity := 0
var fast := false

func initialize(device: RenderingDevice, base: Dictionary, particles: Array, use_fast: bool = false) -> bool:
	fast = use_fast
	if particles.is_empty() or particles.size()>8 or int(base.geometry.size)!=32: return false
	if fast:
		if base.geometry.active.size()!=1024: return false
		for i in range(1024):
			var point := Vector2((i%32+0.5)/32.0,(floori(float(i)/32)+0.5)/32.0)-Vector2(0.5,0.5)
			if bool(base.geometry.active[i])!=(point.length_squared()<0.46*0.46): return false
		for face: Array in base.faces:
			if absf(float(face[2])-1.0)>1e-12: return false
	for g: Dictionary in particles:
		for key in ["x","y","radius","drag","density"]:
			if not is_finite(float(g[key])): return false
		if minf(float(g.radius),minf(float(g.drag),float(g.density)))<=0: return false
	rd = device
	count = particles.size()
	faces = base.faces.size()
	var names := ["grain_coupling","grain_calibration","grain_status"]
	if fast: names = ["grain_coupling","fast_self","grain_status","fast_grain_guard"]
	for name in names:
		var shader := Physics.compile_shader(rd,"res://experiments/liquid/%s.glsl" % name)
		if not shader.is_valid(): return false
		shaders.append(shader)
		pipelines.append(rd.compute_pipeline_create(shader))
	for i in range(1 if fast else 2*count+1):
		var solver := Solver.new()
		if not solver.initialize(rd,base.levels): return false
		solvers.append(solver)
	var data := PackedFloat32Array()
	for g: Dictionary in particles: data.append_array(PackedFloat32Array([g.x,g.y,g.radius,g.drag,g.density,g.material,0,0]))
	for i in range(2): buffers.append(rd.storage_buffer_create(data.size()*4,data.to_byte_array()))
	buffers.append(rd.storage_buffer_create(data.size()*4)) # candidate 2
	buffers.append(rd.storage_buffer_create(count*8)) # normalization 3
	var face_data := PackedByteArray()
	face_data.resize(faces*16)
	for i in range(faces):
		face_data.encode_u32(i*16,base.faces[i][0])
		face_data.encode_u32(i*16+4,base.faces[i][1])
		face_data.encode_float(i*16+8,base.faces[i][2])
	buffers.append(rd.storage_buffer_create(face_data.size(),face_data)) # faces 4
	buffers.append(rd.storage_buffer_create(count*4)) # valid 5
	var adjacency := PackedInt32Array(base.geometry.adjacency).to_byte_array()
	buffers.append(rd.storage_buffer_create(adjacency.size(),adjacency)) # adjacency 6
	buffers.append(rd.storage_buffer_create(count*16)) # self 7
	buffers.append(rd.storage_buffer_create(count*count*16)) # full response 8
	buffers.append(rd.storage_buffer_create(4)) # certificate 9
	buffers.append(rd.storage_buffer_create((2*count+1)*16)) # pressure summaries 10
	buffers.append(rd.storage_buffer_create(16)) # combined status 11
	if fast:
		var kernel: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/self-response-kernel.json"))
		var coefficients := PackedFloat32Array()
		for component: Array in kernel.values:
			for row: Array in component: coefficients.append_array(PackedFloat32Array(row))
		buffers.append(rd.storage_buffer_create(coefficients.size()*4,coefficients.to_byte_array())) # kernel 12
		buffers.append(rd.storage_buffer_create(count*4)) # kernel validity 13
	return true

func _uniform_set(kind: int, refs: Array) -> RID:
	var key := str(kind)+str(refs)
	if not sets.has(key):
		var uniforms: Array[RDUniform] = []
		for binding in range(refs.size()):
			var u := RDUniform.new()
			u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.binding = binding
			u.add_id(refs[binding])
			uniforms.append(u)
		sets[key]=rd.uniform_set_create(uniforms,shaders[kind],0)
	return sets[key]

func _dispatch(list: int, kind: int, phase: int, refs: Array, params: PackedByteArray, work: int) -> void:
	params.encode_u32(12,phase)
	rd.compute_list_bind_compute_pipeline(list,pipelines[kind])
	rd.compute_list_bind_uniform_set(list,_uniform_set(kind,refs),0)
	rd.compute_list_set_push_constant(list,params,32)
	rd.compute_list_dispatch(list,ceili(float(work)/64),1,1)
	rd.compute_list_add_barrier(list)

func advance(gravity: Vector2, dt: float, cycle_budget: int = 96) -> bool:
	if not gravity.is_finite() or not is_finite(dt) or dt<=0 or cycle_budget<1 or cycle_budget>128: return false
	for solver in solvers: solver.reset_statistics()
	var params := PackedByteArray()
	params.resize(32)
	params.encode_u32(0,count)
	params.encode_u32(4,faces)
	params.encode_u32(8,32)
	params.encode_float(16,gravity.x)
	params.encode_float(20,gravity.y)
	params.encode_float(24,dt)
	var main = solvers[-1]
	var refs := [buffers[parity],buffers[2],buffers[1-parity],buffers[3],buffers[4],main.levels[0].equations,main.levels[0].p[main.levels[0].parity],main.control,buffers[5],buffers[6],buffers[7]]
	var list := rd.compute_list_begin()
	_dispatch(list,0,0,refs,params,count)
	if fast:
		var query := PackedByteArray()
		query.resize(16)
		query.encode_u32(0,32)
		query.encode_u32(4,count)
		query.encode_u32(8,8)
		rd.compute_list_bind_compute_pipeline(list,pipelines[1])
		rd.compute_list_bind_uniform_set(list,_uniform_set(1,[buffers[parity],buffers[7],buffers[13],buffers[12]]),0)
		rd.compute_list_set_push_constant(list,query,16)
		rd.compute_list_dispatch(list,ceili(float(count)/64),1,1)
		rd.compute_list_add_barrier(list)
	else:
		var calibration := params.duplicate()
		for unit in range(2*count):
			var solver = solvers[unit]
			calibration.encode_u32(16,unit)
			var cal_refs := [buffers[parity],buffers[3],buffers[4],solver.levels[0].equations,solver.levels[0].p[solver.levels[0].parity],solver.control,buffers[7],buffers[8],buffers[9],buffers[6]]
			_dispatch(list,1,0,cal_refs,calibration,faces)
			_dispatch(list,1,1,cal_refs,calibration,1024)
			cal_refs[4]=solver.record_adaptive(list,cycle_budget,2e-6)
			_dispatch(list,1,2,cal_refs,calibration,count)
			if unit==2*count-1: _dispatch(list,1,3,cal_refs,calibration,1)
	_dispatch(list,0,1,refs,params,faces)
	_dispatch(list,0,2,refs,params,1024)
	refs[6]=main.record_adaptive(list,cycle_budget,2e-6)
	_dispatch(list,0,3,refs,params,count)
	if fast:
		_dispatch(list,3,0,[buffers[parity],buffers[2],buffers[5],buffers[13],buffers[9]],params,count)
	_dispatch(list,0,4,refs,params,count)
	rd.compute_list_end()
	for i in range(solvers.size()):
		rd.buffer_copy(solvers[i].control,buffers[10],0,i*16,16)
	var summary_params := params.duplicate()
	summary_params.encode_u32(4,solvers.size())
	list = rd.compute_list_begin()
	_dispatch(list,2,0,[buffers[10],buffers[9],buffers[5],buffers[11]],summary_params,1)
	rd.compute_list_end()
	parity=1-parity
	return true

func output() -> RID: return buffers[parity]
func status() -> RID: return buffers[11]

func release() -> void:
	for rid: RID in sets.values(): rd.free_rid(rid)
	for rid in buffers+pipelines+shaders: rd.free_rid(rid)
	for solver in solvers: solver.release()


# Calibration-only command chain for the contact experiment. No particle commit.
# Caller owns submit/sync (local RD) or asynchronous scheduling (main RD).
func record_mobility(cycle_budget:int=96) -> bool:
	if fast or cycle_budget<1 or cycle_budget>128:return false
	for solver in solvers:solver.reset_statistics()
	var params:=PackedByteArray();params.resize(32)
	params.encode_u32(0,count);params.encode_u32(4,faces);params.encode_u32(8,32)
	var main=solvers[-1]
	var list:=rd.compute_list_begin()
	var refs:=[buffers[parity],buffers[2],buffers[1-parity],buffers[3],buffers[4],main.levels[0].equations,main.levels[0].p[main.levels[0].parity],main.control,buffers[5],buffers[6],buffers[7]]
	_dispatch(list,0,0,refs,params,count)
	for unit in range(2*count):
		var solver=solvers[unit]
		params.encode_u32(16,unit)
		var cal_refs:=[buffers[parity],buffers[3],buffers[4],solver.levels[0].equations,solver.levels[0].p[solver.levels[0].parity],solver.control,buffers[7],buffers[8],buffers[9],buffers[6]]
		_dispatch(list,1,0,cal_refs,params,faces)
		_dispatch(list,1,1,cal_refs,params,1024)
		cal_refs[4]=solver.record_adaptive(list,cycle_budget,2e-6)
		_dispatch(list,1,2,cal_refs,params,count)
		if unit==2*count-1:
			_dispatch(list,1,3,cal_refs,params,1)
			_dispatch(list,1,4,cal_refs,params,1)
	rd.compute_list_end()
	return true
