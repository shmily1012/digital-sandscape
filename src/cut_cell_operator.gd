extends RefCounted
## Frozen split-region GPU operator. Caller owns RD thread and synchronization.
## Topology is supplied once; this class never reads back or writes world state.
const Compiler=preload("res://src/physics_engine.gd")
var rd:RenderingDevice
var resources:Array[RID]=[]
var pipeline:RID
var bindings:RID
var pressure:RID
var force:RID
var output:RID
var pressure_low:RID
var force_low:RID
var output_low:RID
var nodes:int
var grains:int
var operator_shader:RID
var storage_ids:Array[RID]=[]

func index_valid(value:Variant,limit:int)->bool:
	if typeof(value)!=TYPE_INT and typeof(value)!=TYPE_FLOAT:return false
	return is_finite(float(value)) and float(value)>=0. and float(value)<limit and float(value)==float(int(value))

func rows_valid(rows:Array,count:int,total:int)->bool:
	if rows.size()!=count+1 or rows[0]!=0 or rows[-1]!=total:return false
	var previous:=0
	for value in rows:
		if not index_valid(value,total+1) or int(value)<previous:return false
		previous=int(value)
	return true

func buffer(data:PackedByteArray)->RID:
	if data.size()<16:data.resize(16)
	var id:=rd.storage_buffer_create(data.size(),data);resources.append(id);return id

func initialize(device:RenderingDevice,data:Dictionary)->bool:
	if rd!=null:return false
	for key in ["nodes","grains","pressure","edges","edge_rows","weights","node_rows","node_ids","grain_rows","grain_ids","mass","velocity"]:
		if not data.has(key):return false
	if not index_valid(data.nodes,100001) or not index_valid(data.grains,100001):return false
	nodes=int(data.nodes);grains=int(data.grains)
	if device==null or nodes<1 or nodes>100000 or grains<0 or grains>100000:return false
	for key in ["pressure","edges","edge_rows","weights","node_rows","node_ids","grain_rows","grain_ids","mass","velocity"]:
		if not data[key] is Array:return false
	if data.edge_rows.size()!=nodes+1 or data.node_rows.size()!=nodes+1 or data.grain_rows.size()!=grains+1:return false
	if data.pressure.size()!=nodes or data.mass.size()!=grains or data.velocity.size()!=grains*2:return false
	if data.edges.size()>1000000 or data.weights.size()>1000000:return false
	if not rows_valid(data.edge_rows,nodes,data.edges.size()):return false
	if not rows_valid(data.node_rows,nodes,data.node_ids.size()) or not rows_valid(data.grain_rows,grains,data.grain_ids.size()):return false
	if data.node_ids.size()!=data.weights.size() or data.grain_ids.size()!=data.weights.size():return false
	for e in data.edges:
		if not e is Array or e.size()!=2 or not index_valid(e[0],nodes):return false
		if not is_finite(float(e[1])) or float(e[1])<=0.:return false
	for w in data.weights:
		if not w is Array or w.size()!=4 or not index_valid(w[0],nodes) or not index_valid(w[1],grains):return false
		if not is_finite(float(w[2])) or not is_finite(float(w[3])):return false
	for column in range(2):
		var rows:Array=data.node_rows if column==0 else data.grain_rows
		var ids:Array=data.node_ids if column==0 else data.grain_ids
		var seen:Dictionary={}
		for owner in range(rows.size()-1):
			for k in range(int(rows[owner]),int(rows[owner+1])):
				if not index_valid(ids[k],data.weights.size()) or seen.has(int(ids[k])):return false
				var id:=int(ids[k]);seen[id]=true
				if int(data.weights[id][column])!=owner:return false
	for m in data.mass:
		if not is_finite(float(m)) or float(m)<=0.:return false
	for values in [data.pressure,data.velocity]:
		for x in values:
			if not is_finite(float(x)):return false
	rd=device
	var shader:=Compiler.compile_shader(rd,"res://shaders/cut_cell_operator.glsl")
	if not shader.is_valid():return false
	resources.append(shader);pipeline=rd.compute_pipeline_create(shader);resources.append(pipeline)
	operator_shader=shader
	var edge_bytes:=PackedByteArray();edge_bytes.resize(data.edges.size()*8)
	for i in range(data.edges.size()):
		edge_bytes.encode_u32(i*8,int(data.edges[i][0]));edge_bytes.encode_float(i*8+4,float(data.edges[i][1]))
	var weight_bytes:=PackedByteArray();weight_bytes.resize(data.weights.size()*16)
	for i in range(data.weights.size()):
		weight_bytes.encode_u32(i*16,int(data.weights[i][0]));weight_bytes.encode_u32(i*16+4,int(data.weights[i][1]))
		weight_bytes.encode_float(i*16+8,float(data.weights[i][2]));weight_bytes.encode_float(i*16+12,float(data.weights[i][3]))
	pressure=buffer(PackedFloat32Array(data.pressure).to_byte_array())
	var ids:Array[RID]=[pressure,buffer(edge_bytes),buffer(PackedInt32Array(data.edge_rows).to_byte_array()),
		buffer(weight_bytes),buffer(PackedInt32Array(data.node_rows).to_byte_array()),buffer(PackedInt32Array(data.node_ids).to_byte_array()),
		buffer(PackedInt32Array(data.grain_rows).to_byte_array()),buffer(PackedInt32Array(data.grain_ids).to_byte_array()),
		buffer(PackedFloat32Array(data.mass).to_byte_array()),buffer(PackedFloat32Array(data.velocity).to_byte_array())]
	var zeros:=PackedByteArray();zeros.resize(grains*8);force=buffer(zeros)
	zeros=PackedByteArray();zeros.resize(nodes*8);output=buffer(zeros)
	ids.append(force);ids.append(output)
	zeros=PackedByteArray();zeros.resize(16);ids.append(buffer(zeros))
	zeros=PackedByteArray();zeros.resize(nodes*4);pressure_low=buffer(zeros)
	zeros=PackedByteArray();zeros.resize(grains*8);force_low=buffer(zeros)
	zeros=PackedByteArray();zeros.resize(nodes*8);output_low=buffer(zeros)
	ids.append(pressure_low);ids.append(force_low);ids.append(output_low)
	storage_ids=ids
	var uniforms:Array[RDUniform]=[]
	for i in range(ids.size()):
		var u:=RDUniform.new();u.binding=i;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(ids[i]);uniforms.append(u)
	bindings=rd.uniform_set_create(uniforms,shader,0);resources.append(bindings)
	return bindings.is_valid()

func input_bindings(input:RID,control:RID,low_input:RID)->RID:
	var uniforms:Array[RDUniform]=[]
	for i in range(storage_ids.size()):
		var u:=RDUniform.new();u.binding=i;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.add_id(input if i==0 else (control if i==12 else (low_input if i==13 else storage_ids[i])));uniforms.append(u)
	var result:=rd.uniform_set_create(uniforms,operator_shader,0);resources.append(result);return result

func record_into(list:int,dt:float,uniforms:RID,gated:bool=false,verify_only:bool=false)->void:
	var push:=PackedByteArray();push.resize(16)
	push.encode_u32(0,nodes);push.encode_u32(4,grains);push.encode_float(12,dt)
	rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,uniforms,0)
	for mode in range(2):
		push.encode_u32(8,mode+4 if verify_only else (mode if gated else mode+2));rd.compute_list_set_push_constant(list,push,16)
		rd.compute_list_dispatch(list,ceili(maxi(nodes,grains)/64.),1,1);rd.compute_list_add_barrier(list)

func record(dt:float)->bool:
	if not bindings.is_valid() or not is_finite(dt) or dt<0. or dt>1.:return false
	var list:=rd.compute_list_begin();record_into(list,dt,bindings)
	rd.compute_list_end();return true

func release()->void:
	for i in range(resources.size()-1,-1,-1):
		if resources[i].is_valid():rd.free_rid(resources[i])
	resources.clear();storage_ids.clear();bindings=RID();pipeline=RID();operator_shader=RID()
	pressure=RID();force=RID();output=RID();pressure_low=RID();force_low=RID();output_low=RID();rd=null
