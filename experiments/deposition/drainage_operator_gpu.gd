extends RefCounted
# Device ownership stays with the caller. Record only: no submit, sync, or readback.
# Static topology/levels must come from a validated builder; geometry/velocity are mutable GPU inputs.
const Physics=preload("res://src/physics_engine.gd")
const Pressure=preload("res://experiments/liquid/multigrid_gpu.gd")
var rd:RenderingDevice
var n:int
var nf:int
var side:int
var shader:RID
var pipeline:RID
var chain_shader:RID
var chain_pipeline:RID
var geometry_set:RID
var refs:Array[RID]=[]
var extra:Array[RID]=[]
var chain_sets:Dictionary={}
var solver:RefCounted
var pressure_backward_error := false

func initialize(device:RenderingDevice,test:Dictionary)->bool:
	rd=device
	shader=Physics.compile_shader(rd,"res://experiments/deposition/geometric_operator.glsl")
	chain_shader=Physics.compile_shader(rd,"res://experiments/deposition/drainage_chain.glsl")
	if not shader.is_valid() or not chain_shader.is_valid():return false
	pipeline=rd.compute_pipeline_create(shader);chain_pipeline=rd.compute_pipeline_create(chain_shader)
	n=test.grains.size();nf=test.faces.size();side=int(test.side)
	var particles:=PackedFloat32Array();var velocities:=PackedFloat32Array();var faces:=PackedByteArray();faces.resize(nf*16)
	for g:Array in test.grains:particles.append_array(PackedFloat32Array(g))
	for v:Array in test.velocities:velocities.append_array(PackedFloat32Array(v))
	for i in range(nf):
		for j in range(4):faces.encode_u32(i*16+j*4,int(test.faces[i][j]))
	var mask:=PackedByteArray();mask.resize(test.active.size()*4)
	for i in range(test.active.size()):mask.encode_u32(i*4,int(test.active[i]))
	var mobility:=PackedFloat32Array(test.mobility)
	var liquid:=PackedFloat32Array();liquid.resize(nf);liquid.fill(0.)
	var source:=PackedFloat32Array();source.resize(nf);source.fill(0.)
	var adjoint:=PackedFloat32Array();adjoint.resize(n*2);adjoint.fill(0.)
	var arrays:Array[PackedByteArray]=[particles.to_byte_array(),velocities.to_byte_array(),faces,mask,liquid.to_byte_array(),mobility.to_byte_array(),source.to_byte_array(),adjoint.to_byte_array()]
	refs=[]
	for data:PackedByteArray in arrays:refs.append(rd.storage_buffer_create(data.size(),data))
	refs.append(rd.storage_buffer_create(maxi(n,nf)*4));refs.append(rd.storage_buffer_create(4))
	refs.append(rd.storage_buffer_create(nf*4));refs.append(rd.storage_buffer_create(n*8))
	var uniforms:Array[RDUniform]=[]
	for i in range(refs.size()):
		var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(refs[i]);uniforms.append(u)
	geometry_set=rd.uniform_set_create(uniforms,shader,0)
	solver=Pressure.new()
	solver.fuse_coarse=true
	if not solver.initialize(rd,test.levels):return false
	var adjacency:=PackedInt32Array(test.adjacency).to_byte_array()
	var sentinel:=PackedFloat32Array();sentinel.resize(n*2);sentinel.fill(0.)
	extra=[rd.storage_buffer_create(adjacency.size(),adjacency),rd.storage_buffer_create(n*8),rd.storage_buffer_create(n*8,sentinel.to_byte_array()),rd.storage_buffer_create(n*4),rd.storage_buffer_create(4),rd.storage_buffer_create(4,PackedFloat32Array([1.]).to_byte_array())]
	for pressure:RID in solver.levels[0].p:
		var chain_refs:Array[RID]=[refs[2],refs[6],extra[0],solver.levels[0].equations,pressure,refs[5],refs[4],refs[9],solver.control,refs[1],refs[7],extra[1],extra[2],extra[3],extra[4],extra[5]]
		var chain_uniforms:Array[RDUniform]=[]
		for i in range(chain_refs.size()):
			var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(chain_refs[i]);chain_uniforms.append(u)
		chain_sets[pressure]=rd.uniform_set_create(chain_uniforms,chain_shader,0)
	return true


# True means commands were recorded, not that GPU convergence succeeded.
# Consumers must gate on output_status(); output_force() retains its prior value on rejection.
func input_grains()->RID:return refs[0]
func input_velocity()->RID:return refs[1]
func output_force()->RID:return extra[2]
func output_status()->RID:return extra[4]

func record(list:int,budget:int=128)->bool:
	if solver==null or budget<1 or budget>128:return false
	var initial_set:RID=chain_sets[solver.levels[0].p[int(solver.levels[0].parity)]]
	# Clear scratch flux and counters on GPU; failed/NaN candidates cannot poison the next call.
	dispatch(list,chain_pipeline,initial_set,5,ceili(float(nf)/64))
	for phase in range(5):dispatch(list,pipeline,geometry_set,phase,1 if phase==1 or phase==3 else ceili(float(maxi(n,nf))/64))
	dispatch(list,chain_pipeline,initial_set,6,1)
	dispatch(list,chain_pipeline,initial_set,0,ceili(float(side*side)/64))
	var pressure:RID=solver.record_adaptive(list,budget,2e-6,true,true,pressure_backward_error)
	var final_set:RID=chain_sets[pressure]
	dispatch(list,chain_pipeline,final_set,1,ceili(float(nf)/64))
	for phase in [2,3,4]:dispatch(list,pipeline,geometry_set,phase,1 if phase==3 else ceili(float(maxi(n,nf))/64))
	for phase in [2,3,4]:dispatch(list,chain_pipeline,final_set,phase,1 if phase==3 else ceili(float(n)/64))
	return true

func dispatch(list:int,pipe:RID,uniforms:RID,phase:int,groups:int)->void:
	var pc:=PackedByteArray();pc.resize(16);pc.encode_u32(0,n);pc.encode_u32(4,nf);pc.encode_u32(8,side);pc.encode_u32(12,phase)
	rd.compute_list_bind_compute_pipeline(list,pipe);rd.compute_list_bind_uniform_set(list,uniforms,0)
	rd.compute_list_set_push_constant(list,pc,16);rd.compute_list_dispatch(list,groups,1,1);rd.compute_list_add_barrier(list)

func release()->void:
	for rid:RID in chain_sets.values():rd.free_rid(rid)
	chain_sets.clear()
	if geometry_set.is_valid():rd.free_rid(geometry_set);geometry_set=RID()
	for rid:RID in refs+extra:rd.free_rid(rid)
	refs.clear();extra.clear()
	if solver!=null:solver.release();solver=null
	for rid:RID in [pipeline,chain_pipeline,shader,chain_shader]:
		if rid.is_valid():rd.free_rid(rid)
	pipeline=RID();chain_pipeline=RID();shader=RID();chain_shader=RID()
