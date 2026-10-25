extends "res://src/cut_cell_operator.gd"
## Candidate pressure only; no geometry, gas or particle publication.
## Inherited force/output are scratch. Published pressure/force share a generation.
## Generation zero means no accepted pair. Generations are local to this frozen
## topology instance; callers must wait for the RD job/barriers before consuming.
var solution:RID
var candidate_pressure:RID
var candidate_pressure_low:RID
var solution_low:RID
var solution_force_low:RID
var solution_force:RID
var accepted_generation:RID
var solve_status:RID
var solve_pipeline:RID
var solve_set:RID
var candidate_set:RID
var direction_set:RID
var groups:int
var components:int

func initialize(device:RenderingDevice,data:Dictionary)->bool:
	if not super.initialize(device,data):return false
	groups=ceili(nodes/64.)
	# Frozen test topology is validated once. Dynamic GPU topology is separate.
	var edges:Dictionary={}
	for i in range(nodes):
		for k in range(int(data.edge_rows[i]),int(data.edge_rows[i+1])):
			var key:=Vector2i(i,int(data.edges[k][0]))
			edges[key]=float(edges.get(key,0.))+float(data.edges[k][1])
	for key in edges:
		if edges.get(Vector2i(key.y,key.x),-1.)!=edges[key]:return false
	var labels:=PackedInt32Array();labels.resize(nodes);labels.fill(-1)
	var component_rows:=PackedInt32Array([0]);var component_ids:=PackedInt32Array()
	for start in range(nodes):
		if labels[start]>=0:continue
		var pending:Array[int]=[start];labels[start]=component_rows.size()-1
		while not pending.is_empty():
			var i:int=pending.pop_back();component_ids.append(i)
			for k in range(int(data.edge_rows[i]),int(data.edge_rows[i+1])):
				var j:=int(data.edges[k][0])
				if labels[j]<0:labels[j]=labels[start];pending.append(j)
		component_rows.append(component_ids.size())
	components=component_rows.size()-1
	var shader:=Compiler.compile_shader(rd,"res://shaders/cut_cell_pressure.glsl")
	if not shader.is_valid():return false
	resources.append(shader);solve_pipeline=rd.compute_pipeline_create(shader);resources.append(solve_pipeline)
	var zero:=PackedByteArray();zero.resize(nodes*4)
	var candidate:=buffer(zero);var direction:=buffer(zero);var residual:=buffer(zero)
	candidate_pressure=candidate
	candidate_pressure_low=buffer(zero);solution_low=buffer(zero)
	zero=PackedByteArray();zero.resize(groups*8);var partial:=buffer(zero)
	zero=PackedByteArray();zero.resize(16);var control:=buffer(zero)
	zero.resize(32);solve_status=buffer(zero)
	solution=buffer(PackedFloat32Array(data.pressure).to_byte_array())
	zero=PackedByteArray();zero.resize(grains*8);solution_force=buffer(zero)
	solution_force_low=buffer(zero)
	zero=PackedByteArray();zero.resize(16);accepted_generation=buffer(zero)
	var ids:Array[RID]=[candidate,direction,residual,output,partial,control,solve_status,solution,
		buffer(component_rows.to_byte_array()),buffer(component_ids.to_byte_array()),force,solution_force,accepted_generation,
		candidate_pressure_low,solution_low,output_low,force_low,solution_force_low]
	var uniforms:Array[RDUniform]=[]
	for i in range(ids.size()):
		var u:=RDUniform.new();u.binding=i;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(ids[i]);uniforms.append(u)
	solve_set=rd.uniform_set_create(uniforms,shader,0);resources.append(solve_set)
	candidate_set=input_bindings(candidate,control,candidate_pressure_low);direction_set=input_bindings(direction,control,pressure_low)
	return solve_set.is_valid() and candidate_set.is_valid() and direction_set.is_valid()

func vector_pass(list:int,mode:int,tolerance:float)->void:
	var push:=PackedByteArray();push.resize(32)
	push.encode_u32(0,nodes);push.encode_u32(4,mode);push.encode_u32(8,groups);push.encode_float(12,tolerance)
	push.encode_u32(16,components)
	push.encode_u32(20,grains)
	rd.compute_list_bind_compute_pipeline(list,solve_pipeline);rd.compute_list_bind_uniform_set(list,solve_set,0)
	var dispatch_groups:=components if mode==11 else (ceili(maxi(nodes,grains)/64.) if mode in [10,13] else groups)
	rd.compute_list_set_push_constant(list,push,32);rd.compute_list_dispatch(list,dispatch_groups,1,1);rd.compute_list_add_barrier(list)

func record_pressure(dt:float,iterations:int=128,tolerance:float=1e-6)->bool:
	if not solve_set.is_valid() or iterations<1 or iterations>256 or not is_finite(dt) or dt<0. or dt>1.:return false
	if not is_finite(tolerance) or tolerance<1e-9 or tolerance>1e-4:return false
	var list:=rd.compute_list_begin()
	vector_pass(list,0,tolerance);record_into(list,dt,candidate_set)
	vector_pass(list,1,tolerance)
	# With inertia, a component's uniform pressure can move a bounding grain;
	# a nonzero component source is then not evidence of incompatibility.
	if dt==0.:vector_pass(list,11,tolerance)
	vector_pass(list,2,tolerance)
	for _iteration in range(iterations):
		record_into(list,dt,direction_set,true)
		record_into(list,dt,candidate_set,false,true)
		for mode in [3,4,5,6,7]:vector_pass(list,mode,tolerance)
	# Always check the original equation, not just the CG recurrence.
	record_into(list,dt,candidate_set)
	for mode in [13,8,9,10,12]:vector_pass(list,mode,tolerance)
	rd.compute_list_end();return true

func release()->void:
	solution=RID();candidate_pressure=RID();solution_force=RID();accepted_generation=RID();solve_status=RID()
	candidate_pressure_low=RID();solution_low=RID();solution_force_low=RID()
	candidate_set=RID();direction_set=RID();solve_set=RID();solve_pipeline=RID();super.release()
