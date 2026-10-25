extends RefCounted
# Device-owner-thread command recorder. Caller submits/awaits one packet before consume.
var online:RefCounted
var rd:RenderingDevice
var state:="idle"
var pending:=false
var unit:=0
var cycles_recorded:=0
var packets:=0
var maximum_cycles:=96
var batch_cycles:=8
var prepare:=true
var awaiting:=""
var status_rid:RID
var status_size:=16
func initialize(model:RefCounted) -> void:
	online=model;rd=model.rd
func start(cycle_budget:int=96, packet_cycles:int=8) -> bool:
	if pending or state in ["solve","capture"] or online.fast or cycle_budget<1 or cycle_budget>128 or packet_cycles<1 or packet_cycles>8:return false
	state="solve";unit=0;cycles_recorded=0;packets=0;maximum_cycles=cycle_budget;batch_cycles=packet_cycles;prepare=true
	var zero:=PackedByteArray();zero.resize(4)
	rd.buffer_update(online.buffers[9],0,4,zero)
	return true
func record_next() -> bool:
	if pending or state not in ["solve","capture"]:return false
	var solver=online.solvers[unit]
	var params:=PackedByteArray();params.resize(32)
	params.encode_u32(0,online.count);params.encode_u32(4,online.faces);params.encode_u32(8,32);params.encode_u32(16,unit)
	if state=="solve" and prepare:solver.reset_statistics()
	var refs:=[online.output(),online.buffers[3],online.buffers[4],solver.levels[0].equations,solver.levels[0].p[solver.levels[0].parity],solver.control,online.buffers[7],online.buffers[8],online.buffers[9],online.buffers[6]]
	var list:=rd.compute_list_begin()
	if state=="solve":
		if prepare:
			if unit==0:
				var main=online.solvers[-1]
				var normal_refs:=[online.output(),online.buffers[2],online.buffers[1-online.parity],online.buffers[3],online.buffers[4],main.levels[0].equations,main.levels[0].p[main.levels[0].parity],main.control,online.buffers[5],online.buffers[6],online.buffers[7]]
				online._dispatch(list,0,0,normal_refs,params,online.count)
			online._dispatch(list,1,0,refs,params,online.faces)
			online._dispatch(list,1,1,refs,params,1024)
			prepare=false
		var work:=mini(batch_cycles,maximum_cycles-cycles_recorded)
		solver.record_adaptive(list,work,2e-6)
		cycles_recorded+=work
		status_rid=solver.control;status_size=16
	else:
		online._dispatch(list,1,2,refs,params,online.count)
		if unit==2*online.count-1:
			online._dispatch(list,1,3,refs,params,1)
			online._dispatch(list,1,4,refs,params,1)
			status_rid=online.buffers[9];status_size=4
		else:status_rid=solver.control;status_size=16
	rd.compute_list_end()
	pending=true;awaiting=state;packets+=1
	return true
func consume(data:PackedByteArray) -> bool:
	if not pending:return false
	pending=false
	if data.size()!=status_size:state="failed";return false
	if awaiting=="solve":
		if data.decode_u32(12)!=0:state="failed"
		elif data.decode_u32(4)==1:state="capture"
		elif cycles_recorded>=maximum_cycles:state="failed"
	else:
		if unit==2*online.count-1:state="done" if data.decode_u32(0)==1 else "failed"
		else:unit+=1;cycles_recorded=0;prepare=true;state="solve"
	return state!="failed"
func cancel() -> bool:
	# In-flight cancellation is handled by the caller after the status callback.
	if pending:return false
	if state not in ["solve","capture"]:return false
	state="cancelled"
	return true
